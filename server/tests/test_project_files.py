"""Opening and deleting project files (2026-10-07): uploaded originals and
Studio PDFs stored in Postgres and opened via short-lived signed links;
deleting an upload removes exactly the index chunks it added.

Reported from the phone: "I've generated a study guide but can't download
it, I can't view the file I uploaded or delete it."

Run with: python -m pytest server/tests/test_project_files.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import func, select, update

from server.core import security
from server.db.session import async_session
from server.domains.knowledge.models import Material, StoredFile

_PASSWORD = "testpass123"
_PDF_MAGIC = b"%PDF"


@pytest.fixture
async def project(client):
    email = f"pytest_files_{uuid.uuid4().hex[:12]}@example.com"
    token = (await client.post("/api/auth/signup", json={"email": email, "password": _PASSWORD})).json()["token"]
    h = {"Authorization": f"Bearer {token}"}
    slug = (await client.post("/api/projects", json={"display_name": "Cells"}, headers=h)).json()["slug"]
    user_id = (await client.get("/api/auth/me", headers=h)).json()["id"]
    yield {"headers": h, "slug": slug, "user_id": user_id}
    await client.request("DELETE", "/api/account", json={"password": _PASSWORD}, headers=h)


async def _upload_text_file(client, project, name: str, body: str) -> dict:
    r = await client.post(
        f"/api/projects/{project['slug']}/material",
        files={"file": (name, body.encode(), "text/plain")},
        headers=project["headers"],
    )
    assert r.status_code == 200, r.text
    return r.json()["material"]


async def _open(client, project, file_id: int):
    link = await client.post(f"/api/files/{file_id}/link", headers=project["headers"])
    assert link.status_code == 200, link.text
    return await client.get(link.json()["url"])  # no Authorization header, like a phone's browser


async def _search(client, project, q: str) -> list[str]:
    r = await client.get(f"/api/v1/knowledge-spaces/{project['slug']}/search", params={"q": q}, headers=project["headers"])
    return [x["chunk"] for x in r.json()["results"]]


async def test_uploaded_file_can_be_opened_without_auth_header(client, project):
    material = await _upload_text_file(client, project, "lecture.txt", "Mitochondria produce ATP. " * 20)
    assert material["file_id"]
    opened = await _open(client, project, material["file_id"])
    assert opened.status_code == 200
    assert opened.content.startswith(b"Mitochondria produce ATP.")
    assert "lecture.txt" in opened.headers["content-disposition"]


async def test_pasted_text_can_be_opened_too(client, project):
    r = await client.post(f"/api/projects/{project['slug']}/material", data={"text": "Osmosis notes " * 10}, headers=project["headers"])
    opened = await _open(client, project, r.json()["material"]["file_id"])
    assert opened.content.startswith(b"Osmosis notes")


async def test_studio_pdf_can_be_downloaded(client, project):
    await _upload_text_file(client, project, "lecture.txt", "Ribosomes build proteins from mRNA. " * 20)
    artifact = (await client.post(
        f"/api/projects/{project['slug']}/studio", json={"doc_type": "study_guide"}, headers=project["headers"]
    )).json()
    assert artifact["file_id"]
    opened = await _open(client, project, artifact["file_id"])
    assert opened.status_code == 200
    assert opened.headers["content-type"] == "application/pdf"
    assert opened.content.startswith(_PDF_MAGIC)


async def test_file_links_are_scoped_and_not_login_tokens(client, project):
    material = await _upload_text_file(client, project, "a.txt", "alpha " * 20)
    other = await _upload_text_file(client, project, "b.txt", "beta " * 20)
    token = security.create_file_token(material["file_id"], project["user_id"])

    # A link for one file doesn't open another.
    assert (await client.get(f"/api/files/{other['file_id']}?token={token}")).status_code == 403
    # A file link can't be used to log in...
    assert (await client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})).status_code == 401
    # ...and a login token isn't a file link.
    login_token = project["headers"]["Authorization"].split()[1]
    assert (await client.get(f"/api/files/{material['file_id']}?token={login_token}")).status_code == 401
    # Another user can't mint a link for this file.
    email = f"pytest_files_{uuid.uuid4().hex[:12]}@example.com"
    stranger = {"Authorization": f"Bearer {(await client.post('/api/auth/signup', json={'email': email, 'password': _PASSWORD})).json()['token']}"}
    try:
        assert (await client.post(f"/api/files/{material['file_id']}/link", headers=stranger)).status_code == 404
    finally:
        await client.request("DELETE", "/api/account", json={"password": _PASSWORD}, headers=stranger)


async def test_deleting_an_upload_removes_exactly_its_content(client, project):
    a = await _upload_text_file(client, project, "osmosis.txt", "Osmosis moves water across membranes. " * 30)
    b = await _upload_text_file(client, project, "golgi.txt", "The Golgi apparatus packages proteins. " * 30)
    c = await _upload_text_file(client, project, "ribosome.txt", "Ribosomes translate messenger RNA. " * 30)

    r = await client.delete(f"/api/projects/{project['slug']}/materials/{b['id']}", headers=project["headers"])
    assert r.status_code == 200, r.text

    remaining = " ".join(await _search(client, project, "Golgi apparatus proteins"))
    assert "Golgi" not in remaining
    assert any("Osmosis" in x for x in await _search(client, project, "osmosis water"))
    assert any("Ribosomes" in x for x in await _search(client, project, "ribosomes mRNA"))

    # The later upload's slice shifted down, so deleting it next still removes the right content.
    r = await client.delete(f"/api/projects/{project['slug']}/materials/{c['id']}", headers=project["headers"])
    assert r.status_code == 200
    assert not any("Ribosomes" in x for x in await _search(client, project, "ribosomes mRNA"))
    assert any("Osmosis" in x for x in await _search(client, project, "osmosis water"))

    listed = (await client.get(f"/api/projects/{project['slug']}/materials", headers=project["headers"])).json()["materials"]
    assert [m["id"] for m in listed] == [a["id"]]
    async with async_session() as db:  # stored originals went with them
        assert await db.scalar(select(func.count()).select_from(StoredFile).where(StoredFile.id.in_([b["file_id"], c["file_id"]]))) == 0


async def test_legacy_upload_without_a_recorded_slice(client, project):
    a = await _upload_text_file(client, project, "old.txt", "Osmosis moves water. " * 30)
    async with async_session() as db:  # what an upload from before chunk tracking looks like
        await db.execute(update(Material).where(Material.id == a["id"]).values(chunk_start=None, chunk_count=None))
        await db.commit()
    b = await _upload_text_file(client, project, "new.txt", "Golgi packages proteins. " * 30)

    blocked = await client.delete(f"/api/projects/{project['slug']}/materials/{a['id']}", headers=project["headers"])
    assert blocked.status_code == 409
    assert "recreate the project" in blocked.json()["detail"]

    # Once it's the only indexed material, removing it clears the index.
    assert (await client.delete(f"/api/projects/{project['slug']}/materials/{b['id']}", headers=project["headers"])).status_code == 200
    assert (await client.delete(f"/api/projects/{project['slug']}/materials/{a['id']}", headers=project["headers"])).status_code == 200
    assert await _search(client, project, "osmosis") == []


async def test_deleting_a_project_removes_its_stored_files(client, project):
    m = await _upload_text_file(client, project, "x.txt", "Chloroplasts photosynthesise. " * 20)
    assert (await client.delete(f"/api/projects/{project['slug']}", headers=project["headers"])).status_code == 200
    async with async_session() as db:
        assert await db.get(StoredFile, m["file_id"]) is None
