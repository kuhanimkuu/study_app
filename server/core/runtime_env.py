"""
CPU/thread limits for the heavy engines, resolved once at startup.

Imported first by server/main.py (and server/engines.py), before numpy,
torch, ONNX Runtime or tesseract load — those read their thread counts from
the environment when they first start, so setting it later does nothing.

The features/ engines read these as plain integers from os.environ (they
can't import server/). `.env` normally only reaches pydantic's Settings
object, not os.environ, so it's loaded into os.environ here too — real
environment variables still win.

Tuned 2026-10-19 for a shared VPS (Contabo): its vCPUs are shared with
other customers' machines, so running every core flat out gets slower, not
faster (CPU steal), and starves the event loop, Postgres and nginx on the
same box. "auto" therefore uses about half the CPUs, never all of them.

  HEAVY_ENGINE_WORKERS  heavy jobs (OCR, Whisper, PDF, charts, ...) running at
                        once; the rest queue. auto = half the CPUs, 1-4, and
                        at most one per 1.5 GB of RAM.
  ENGINE_THREADS        native threads EACH heavy job may use (BLAS, OpenMP,
                        tesseract, ONNX/fastembed, Whisper). Default 1: many
                        single-threaded jobs side by side beat a few jobs
                        fighting over every core.
  LOCAL_MODEL_THREADS   torch threads for the free local LLM. auto = half the
                        CPUs, 1-8.
  HEAVY_ENGINE_NICE     Linux nice level for the heavy worker threads
                        (default 10), so the event loop answering everyone
                        else wins whenever the CPU is contended. 0 disables.
"""
from __future__ import annotations

import logging
import math
import os
from pathlib import Path

from dotenv import load_dotenv

logger = logging.getLogger("study_os.runtime")

load_dotenv(Path(__file__).resolve().parents[2] / ".env", override=False)


def _available_cpus() -> int:
    """CPUs this process may actually use: the cgroup quota inside a
    container (Render reports the host's cores to os.cpu_count but grants
    a fraction of one), else the CPU affinity set, else os.cpu_count."""
    try:
        quota, period = Path("/sys/fs/cgroup/cpu.max").read_text().split()
        if quota != "max":
            return max(1, math.ceil(int(quota) / int(period)))
    except (OSError, ValueError):
        pass
    if hasattr(os, "sched_getaffinity"):
        return max(1, len(os.sched_getaffinity(0)))
    return os.cpu_count() or 1


def _available_memory_gb() -> float | None:
    """The cgroup memory limit, else physical RAM. None where neither can be
    read (Windows), which then skips the memory cap."""
    try:
        limit = Path("/sys/fs/cgroup/memory.max").read_text().strip()
        if limit != "max":
            return int(limit) / 1024**3
    except (OSError, ValueError):
        pass
    try:
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 1024**3
    except (AttributeError, ValueError, OSError):
        return None


def _resolve(name: str, auto_value: int) -> int:
    raw = os.environ.get(name, "auto").strip().lower()
    value = auto_value if raw in ("", "auto") else max(1, int(raw))
    os.environ[name] = str(value)
    return value


CPUS = _available_cpus()
MEMORY_GB = _available_memory_gb()

_auto_workers = min(4, max(1, CPUS // 2))
if MEMORY_GB is not None:
    _auto_workers = min(_auto_workers, max(1, int(MEMORY_GB // 1.5)))

HEAVY_ENGINE_WORKERS = _resolve("HEAVY_ENGINE_WORKERS", _auto_workers)
ENGINE_THREADS = _resolve("ENGINE_THREADS", 1)
LOCAL_MODEL_THREADS = _resolve("LOCAL_MODEL_THREADS", min(8, max(1, CPUS // 2)))
os.environ.setdefault("HEAVY_ENGINE_NICE", "10")

# setdefault: an explicit value in the real environment still wins.
for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "OMP_THREAD_LIMIT"):
    os.environ.setdefault(_var, str(ENGINE_THREADS))

# warning, not info: nothing configures this logger's level, and this one
# line is worth seeing in `journalctl -u study-os` on every start.
logger.warning(
    "engine limits: %d CPUs, %s GB RAM -> %d heavy workers x %d threads, local model %d threads",
    CPUS,
    f"{MEMORY_GB:.1f}" if MEMORY_GB is not None else "?",
    HEAVY_ENGINE_WORKERS,
    ENGINE_THREADS,
    LOCAL_MODEL_THREADS,
)
