"""
Load test: N simulated students using the app at once (default 15).

    python -m server.scripts.load_test --base http://127.0.0.1:8001 --users 15 --duration 120

Each user signs up, makes a project with a little material, then loops for
--duration seconds over a mix of real requests — light DB pages, math,
graphs, chart images, photo OCR, audio transcription, PDF reading,
animations, project search and project chat — with 1-4 s of "thinking" in
between. Meanwhile one extra client pings /api/health every 200 ms: if any
request blocks the event loop, that's where it shows. Prints per-action
latency (p50/p95/max) and errors, then deletes every account it created.

Local runs give each user its own X-Forwarded-For address so signup's
per-IP rate limit (5/hour) doesn't stop it — uvicorn trusts that header
from 127.0.0.1 only. Through nginx in production a client can't set it, so
against a real server use --accounts with existing logins instead of
signing up 15 new ones (format: one "email password" per line).
"""
from __future__ import annotations

import argparse
import asyncio
import io
import math
import random
import struct
import time
import uuid
import wave
from collections import defaultdict

import httpx
from matplotlib.figure import Figure
from PIL import Image, ImageDraw

PASSWORD = "LoadTest-" + uuid.uuid4().hex[:10]

MATERIAL = (
    "Mitosis is the process by which a eukaryotic cell divides its nucleus into two identical nuclei. "
    "It has four phases: prophase, metaphase, anaphase and telophase. Photosynthesis converts light "
    "energy into chemical energy stored in glucose, using carbon dioxide and water and releasing oxygen. "
    "Entropy is a measure of disorder; the second law of thermodynamics says it never decreases in an "
    "isolated system. "
) * 20


def _png_with_text() -> bytes:
    img = Image.new("RGB", (900, 260), "white")
    draw = ImageDraw.Draw(img)
    draw.text((20, 60), "The mitochondria is the powerhouse of the cell", fill="black")
    draw.text((20, 140), "Photosynthesis happens in the chloroplast", fill="black")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _pdf_with_text() -> bytes:
    fig = Figure(figsize=(8.5, 11))
    fig.text(0.1, 0.9, "Cell biology notes", fontsize=20)
    for i, line in enumerate(MATERIAL.split(". ")[:12]):
        fig.text(0.1, 0.85 - i * 0.05, line[:90], fontsize=10)
    buf = io.BytesIO()
    fig.savefig(buf, format="pdf")
    return buf.getvalue()


def _wav_tone(seconds: float = 3.0, rate: int = 16000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(
            struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * t / rate))) for t in range(int(seconds * rate))
        ))
    return buf.getvalue()


PNG, PDF, WAV = _png_with_text(), _pdf_with_text(), _wav_tone()


class User:
    def __init__(self, client: httpx.AsyncClient, index: int, forwarded_ip: bool):
        self.c = client
        self.index = index
        self.headers: dict[str, str] = {}
        if forwarded_ip:
            self.headers["X-Forwarded-For"] = f"10.77.0.{index + 1}"
        self.email: str | None = None
        self.password = PASSWORD
        self.created = False
        self.slug: str | None = None

    async def signup(self) -> None:
        self.email = f"loadtest_{uuid.uuid4().hex[:10]}@example.com"
        r = await self.c.post("/api/auth/signup", headers=self.headers, json={"email": self.email, "password": self.password})
        r.raise_for_status()
        self.headers["Authorization"] = f"Bearer {r.json()['token']}"
        self.created = True

    async def login(self, email: str, password: str) -> None:
        self.email, self.password = email, password
        r = await self.c.post("/api/auth/login", headers=self.headers, json={"email": email, "password": password})
        r.raise_for_status()
        self.headers["Authorization"] = f"Bearer {r.json()['token']}"

    async def setup_project(self) -> None:
        r = await self.c.post("/api/projects", headers=self.headers, json={"display_name": f"Load test {uuid.uuid4().hex[:6]}"})
        r.raise_for_status()
        self.slug = r.json()["slug"]
        r = await self.c.post(f"/api/projects/{self.slug}/material", headers=self.headers, data={"text": MATERIAL})
        r.raise_for_status()

    async def cleanup(self) -> None:
        if self.created:
            await self.c.request("DELETE", "/api/account", headers=self.headers, json={"password": self.password})

    # --- actions: each returns the response so the runner can time it ---
    # A fresh session per request: in one shared session, a PDF's "what
    # would you like me to do with it?" turns the next text message into a
    # PDF follow-up (by design), which would measure the wrong engine.
    def _session(self) -> str:
        return f"u{self.index}_{uuid.uuid4().hex[:8]}"

    def ask(self, body: dict):
        return self.c.post("/api/ask/text", headers=self.headers, json={"session_id": self._session(), **body})

    def upload(self, path: str, name: str, data: bytes, mime: str):
        return self.c.post(path, headers=self.headers, files={"file": (name, data, mime)}, data={"session_id": self._session()})

    def actions(self) -> list[tuple[str, int, callable]]:
        expr = random.choice(["x**2 - 4", "sin(x)*x", "x**3 - 2*x", "cos(2*x) + x"])
        return [
            ("list projects", 14, lambda: self.c.get("/api/projects", headers=self.headers)),
            ("list materials", 10, lambda: self.c.get(f"/api/projects/{self.slug}/materials", headers=self.headers)),
            ("solve equation", 12, lambda: self.ask({"content": f"solve {random.randint(2, 9)}x + 3 = {random.randint(10, 40)}"})),
            ("graph", 8, lambda: self.ask({"content": f"graph {expr}"})),
            ("chart image", 8, lambda: self.ask({"content": f"image of {expr}"})),
            ("photo OCR", 9, lambda: self.upload("/api/ask/image", "notes.png", PNG, "image/png")),
            ("audio transcribe", 5, lambda: self.upload("/api/ask/audio", "clip.wav", WAV, "audio/wav")),
            ("read PDF", 6, lambda: self.upload("/api/ask/pdf", "notes.pdf", PDF, "application/pdf")),
            ("animation", 4, lambda: self.ask({"content": "", "task": "animation", "params": {
                "data": {"steps": [f"sin({k}*x)" for k in range(1, 9)]}, "range": [-6.28, 6.28]}})),
            ("project search", 14, lambda: self.c.get(
                f"/api/v1/knowledge-spaces/{self.slug}/search", headers=self.headers,
                params={"q": random.choice(["mitosis phases", "entropy", "photosynthesis"])})),
        ]


def _pct(values: list[float], p: float) -> float:
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))]


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="http://127.0.0.1:8001")
    parser.add_argument("--users", type=int, default=15)
    parser.add_argument("--duration", type=int, default=120, help="seconds of load after setup")
    parser.add_argument("--accounts", help="file of existing 'email password' lines instead of signing up")
    args = parser.parse_args()

    limits = httpx.Limits(max_connections=args.users * 2 + 4)
    async with httpx.AsyncClient(base_url=args.base, timeout=300, limits=limits) as c:
        local = args.accounts is None
        users = [User(c, i, forwarded_ip=local) for i in range(args.users)]
        try:
            print(f"setting up {args.users} users...")
            if args.accounts:
                logins = [line.split() for line in open(args.accounts, encoding="utf-8") if line.strip()]
                await asyncio.gather(*(u.login(*logins[i % len(logins)]) for i, u in enumerate(users)))
            else:
                await asyncio.gather(*(u.signup() for u in users))
            await asyncio.gather(*(u.setup_project() for u in users))
            await asyncio.sleep(5)  # let the background indexing of their material finish

            timings: dict[str, list[float]] = defaultdict(list)
            errors: dict[str, list[str]] = defaultdict(list)
            health: list[float] = []
            deadline = time.monotonic() + args.duration

            async def pinger() -> None:
                while time.monotonic() < deadline:
                    t = time.perf_counter()
                    try:
                        await c.get("/api/health", timeout=60)
                        health.append(time.perf_counter() - t)
                    except httpx.HTTPError as exc:
                        errors["health"].append(type(exc).__name__)
                    await asyncio.sleep(0.2)

            async def run_user(u: User) -> None:
                await asyncio.sleep(random.uniform(0, 3))
                while time.monotonic() < deadline:
                    name, _, call = random.choices(u.actions(), weights=[w for _, w, _ in u.actions()])[0]
                    t = time.perf_counter()
                    try:
                        r = await call()
                        elapsed = time.perf_counter() - t
                        if r.status_code >= 400:
                            errors[name].append(f"{r.status_code} {r.text[:80]}")
                        else:
                            timings[name].append(elapsed)
                            # an engine failure comes back as a 200 with an error block
                            if r.headers.get("content-type", "").startswith("application/json"):
                                body = r.json()
                                for b in body.get("blocks", []) if isinstance(body, dict) else []:
                                    if b.get("type") == "error":
                                        errors[name].append(f"error block: {b.get('engine')}: {str(b.get('message'))[:60]}")
                    except httpx.HTTPError as exc:
                        errors[name].append(type(exc).__name__)
                    await asyncio.sleep(random.uniform(1, 4))

            print(f"running {args.duration}s of load...")
            started = time.monotonic()
            await asyncio.gather(pinger(), *(run_user(u) for u in users))
            wall = time.monotonic() - started

            total = sum(len(v) for v in timings.values())
            print(f"\n{total} successful requests in {wall:.0f}s ({total / wall:.1f}/s) from {args.users} users\n")
            print(f"{'action':<18}{'n':>5}{'p50 s':>9}{'p95 s':>9}{'max s':>9}{'errors':>8}")
            for name in sorted(set(timings) | set(errors) - {"health"}):
                v = timings.get(name, [])
                row = f"{_pct(v, 50):>9.2f}{_pct(v, 95):>9.2f}{max(v):>9.2f}" if v else f"{'-':>9}{'-':>9}{'-':>9}"
                print(f"{name:<18}{len(v):>5}{row}{len(errors.get(name, [])):>8}")
            if health:
                print(f"\nhealth ping (event loop responsiveness): n={len(health)} p50={_pct(health, 50) * 1000:.0f}ms "
                      f"p95={_pct(health, 95) * 1000:.0f}ms max={max(health) * 1000:.0f}ms")
            for name, errs in errors.items():
                for e in sorted(set(errs))[:3]:
                    print(f"  {name}: {e} (x{errs.count(e)})")
        finally:
            await asyncio.gather(*(u.cleanup() for u in users), return_exceptions=True)
            print(f"\ncleaned up {sum(u.created for u in users)} test accounts")


if __name__ == "__main__":
    asyncio.run(main())
