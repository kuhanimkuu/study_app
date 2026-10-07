"""AI generation from a Knowledge Space's material (2026-10-07) — concepts,
flashcards, and practice questions, through the real HTTP API and real
Postgres, with only the model call mocked (no live LLM in the suite).

The material is genuinely uploaded and indexed via POST /material, so the
material sampling and semantic-search grounding paths run for real.

Run with: python -m pytest server/tests/test_ai_generation.py -v
"""
from __future__ import annotations

import uuid

import pytest

from server import engines

_PASSWORD = "testpass123"
_MATERIAL = (
    "Mitochondria are the powerhouse of the cell and produce ATP through cellular respiration. "
    "The nucleus stores DNA and controls gene expression. Ribosomes synthesise proteins from mRNA. "
    "Osmosis is the diffusion of water across a semi-permeable membrane."
)


@pytest.fixture
async def space(client):
    email = f"pytest_gen_{uuid.uuid4().hex[:12]}@example.com"
    signup = await client.post("/api/auth/signup", json={"email": email, "password": _PASSWORD})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}
    slug = (await client.post("/api/projects", json={"display_name": "Cell Bio"}, headers=headers)).json()["slug"]
    added = await client.post(f"/api/projects/{slug}/material", data={"text": _MATERIAL}, headers=headers)
    assert added.status_code == 200, added.text

    yield {"headers": headers, "slug": slug}

    # Through the API rather than a raw DELETE — it also removes this
    # user's RAG index directory, which a row delete would leave behind.
    deleted = await client.request("DELETE", "/api/account", json={"password": _PASSWORD}, headers=headers)
    assert deleted.status_code == 200, deleted.text


def _mock_model(monkeypatch, text: str, captured: list | None = None):
    async def run(**kwargs):
        if captured is not None:
            captured.append(kwargs)
        return {"text": text, "tier": "tiny", "backend": "local"}

    monkeypatch.setattr(engines.model_router, "run", run)


async def test_generate_concepts_saves_new_ones_and_skips_existing(client, space, monkeypatch):
    h, slug = space["headers"], space["slug"]
    await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": "Osmosis"}, headers=h)
    captured: list = []
    _mock_model(
        monkeypatch,
        "Here are the concepts:\n"
        "1. Mitochondria — organelles that produce ATP\n"
        "2. osmosis — water diffusion across a membrane\n"
        "- Ribosomes: build proteins from mRNA\n"
        "- Mitochondria — duplicate line from the model\n",
        captured,
    )
    resp = await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts/generate", json={}, headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert [c["name"] for c in body["concepts"]] == ["Mitochondria", "Ribosomes"]
    assert body["skipped_existing"] == 1
    # Grounded in the real uploaded material, and told what already exists.
    assert "powerhouse of the cell" in captured[0]["prompt"]
    assert "Osmosis" in captured[0]["prompt"]

    listed = (await client.get(f"/api/v1/knowledge-spaces/{slug}/concepts", headers=h)).json()["concepts"]
    assert {c["name"] for c in listed} == {"Osmosis", "Mitochondria", "Ribosomes"}


async def test_generate_flashcards_go_into_the_real_deck(client, space, monkeypatch):
    h, slug = space["headers"], space["slug"]
    _mock_model(
        monkeypatch,
        "Q: What makes ATP? | A: Mitochondria.\nQ: What does the nucleus store? | A: DNA.\nQ: What makes ATP? | A: dup",
    )
    resp = await client.post(f"/api/v1/knowledge-spaces/{slug}/flashcards/generate", json={"count": 5}, headers=h)
    assert resp.status_code == 200, resp.text
    assert [c["front"] for c in resp.json()["flashcards"]] == ["What makes ATP?", "What does the nucleus store?"]

    # Real cards: listed in the deck and due for review like hand-made ones.
    deck = (await client.get(f"/api/v1/knowledge-spaces/{slug}/flashcards", headers=h)).json()["flashcards"]
    assert len(deck) == 2
    due = (await client.get("/api/v1/flashcards/due", headers=h)).json()
    assert len(due["flashcards"]) == 2

    # Running again doesn't duplicate.
    again = await client.post(f"/api/v1/knowledge-spaces/{slug}/flashcards/generate", json={}, headers=h)
    assert again.json()["flashcards"] == [] and again.json()["skipped_existing"] == 2


async def test_generated_questions_are_valid_and_gradable(client, space, monkeypatch):
    h, slug = space["headers"], space["slug"]
    concept_id = (
        await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": "Mitochondria"}, headers=h)
    ).json()["id"]
    _mock_model(
        monkeypatch,
        "MCQ: What do mitochondria produce? | A) DNA | B) ATP | C) mRNA | D) Water | Answer: B\n"
        "TF: Mitochondria store the cell's DNA | Answer: False\n"
        "SA: Why are mitochondria called the powerhouse? | Answer: They produce ATP.\n"
        "MCQ: Broken question | A) one | Answer: C\n"  # answer letter not among options -> dropped
        "TF: Ambiguous | Answer: maybe\n",  # not true/false -> dropped
    )
    resp = await client.post(f"/api/v1/concepts/{concept_id}/questions/generate", json={"count": 6}, headers=h)
    assert resp.status_code == 200, resp.text
    questions = resp.json()["questions"]
    assert [q["type"] for q in questions] == ["mcq", "true_false", "short_answer"]
    assert "correct_answer" not in questions[0]  # practice payload never leaks answers

    mcq, tf = questions[0], questions[1]
    graded = await client.post(f"/api/v1/questions/{mcq['id']}/attempt", json={"answer": "ATP"}, headers=h)
    assert graded.status_code == 200 and graded.json()["correct"] is True
    graded = await client.post(f"/api/v1/questions/{tf['id']}/attempt", json={"answer": "false"}, headers=h)
    assert graded.status_code == 200 and graded.json()["correct"] is True


async def test_generation_without_material_is_a_clear_400(client, monkeypatch):
    email = f"pytest_gen_{uuid.uuid4().hex[:12]}@example.com"
    h = {"Authorization": f"Bearer {(await client.post('/api/auth/signup', json={'email': email, 'password': _PASSWORD})).json()['token']}"}
    try:
        slug = (await client.post("/api/projects", json={"display_name": "Empty"}, headers=h)).json()["slug"]
        resp = await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts/generate", json={}, headers=h)
        assert resp.status_code == 400
        assert "no material" in resp.json()["detail"]
    finally:
        await client.request("DELETE", "/api/account", json={"password": _PASSWORD}, headers=h)


async def test_free_model_unavailable_gives_actionable_503(client, space, monkeypatch):
    async def fail(**kwargs):
        raise ModuleNotFoundError("No module named 'torch'")

    monkeypatch.setattr(engines.model_router, "run", fail)
    resp = await client.post(
        f"/api/v1/knowledge-spaces/{space['slug']}/flashcards/generate", json={}, headers=space["headers"]
    )
    assert resp.status_code == 503
    assert "API key" in resp.json()["detail"]


async def test_unparseable_model_output_saves_nothing(client, space, monkeypatch):
    h, slug = space["headers"], space["slug"]
    _mock_model(monkeypatch, "I'm sorry, I can't help with that.")
    resp = await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts/generate", json={}, headers=h)
    assert resp.status_code == 502
    assert (await client.get(f"/api/v1/knowledge-spaces/{slug}/concepts", headers=h)).json()["concepts"] == []


async def test_equation_answers_accept_caret_powers(client, space):
    h, slug = space["headers"], space["slug"]
    concept_id = (
        await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": "Powers"}, headers=h)
    ).json()["id"]
    q = (
        await client.post(
            f"/api/v1/concepts/{concept_id}/questions",
            json={"type": "equation", "prompt": "Expand x*x", "correct_answer": "x**2"},
            headers=h,
        )
    ).json()
    graded = await client.post(f"/api/v1/questions/{q['id']}/attempt", json={"answer": "x^2"}, headers=h)
    assert graded.status_code == 200, graded.text
    assert graded.json()["correct"] is True


# --- the user's model choice reaches every /api/ask/* route (2026-10-07) ---
# Before this date image/pdf/audio/project hard-coded the free local model
# and silently ignored the caller's choice. An unknown hosted provider is
# rejected by resolve_model_config_async with a 400 *before* any model call
# — so a 400 here proves the route actually read the config.

_BAD_HOSTED = '{"backend": "hosted", "hosted_provider": "not-a-provider"}'


async def test_ask_pdf_followup_reads_the_form_model_config(client, space):
    resp = await client.post(
        "/api/ask/pdf",
        data={"query": "summarise it", "session_id": "gen-test", "model_config": _BAD_HOSTED},
        headers=space["headers"],
    )
    assert resp.status_code == 400
    assert "hosted_provider must be one of" in resp.json()["detail"]


async def test_ask_project_reads_the_body_model_config(client, space):
    resp = await client.post(
        "/api/ask/project",
        json={"project": space["slug"], "query": "ATP?", "session_id": "gen-test",
              "model_config": {"backend": "hosted", "hosted_provider": "not-a-provider"}},
        headers=space["headers"],
    )
    assert resp.status_code == 400


async def test_malformed_form_model_config_is_a_422(client, space):
    resp = await client.post(
        "/api/ask/pdf",
        data={"query": "summarise it", "session_id": "gen-test", "model_config": "{not json"},
        headers=space["headers"],
    )
    assert resp.status_code == 422


def test_flashcard_parser_drops_copied_statement_fronts():
    from server.domains.learning import generation

    # Real free-model output shape captured 2026-10-07.
    text = (
        "1. **Q: What is the function of the cell membrane? | A: It regulates what enters and leaves the cell.**\n"
        "2. **Q: Mitochondria are double-membraned organelles that carry out aerobic respiration. | A: Glucose**\n"
        "3. **Q: Osmosis | A: Net movement of water across a partially permeable membrane.**\n"
    )
    assert [f for f, _ in generation.parse_flashcards(text, 10)] == [
        "What is the function of the cell membrane?",
        "Osmosis",
    ]


# --- the RAG index survives the host losing its disk (2026-10-07) ---


async def _wipe_index_dir(client, headers):
    """What a Render redeploy / idle spin-down does to the index files."""
    import shutil

    from server.domains.identity.router import _RAG_PROJECTS_ROOT

    user_id = (await client.get("/api/auth/me", headers=headers)).json()["id"]
    shutil.rmtree(_RAG_PROJECTS_ROOT / f"user_{user_id}")


async def test_material_survives_a_wiped_disk(client, space, monkeypatch):
    h, slug = space["headers"], space["slug"]
    await _wipe_index_dir(client, h)

    found = (await client.get(f"/api/v1/knowledge-spaces/{slug}/search", params={"q": "ATP"}, headers=h)).json()
    assert found["results"], "search lost the material after the disk wipe"

    await _wipe_index_dir(client, h)
    chat = await client.post(
        "/api/ask/project", json={"project": slug, "query": "what makes ATP?", "session_id": "wipe"}, headers=h
    )
    assert any(b["type"] == "source" for b in chat.json()["blocks"]), chat.text

    await _wipe_index_dir(client, h)
    _mock_model(monkeypatch, "Q: What makes ATP? | A: Mitochondria.")
    gen = await client.post(f"/api/v1/knowledge-spaces/{slug}/flashcards/generate", json={}, headers=h)
    assert gen.status_code == 200, gen.text

    await _wipe_index_dir(client, h)
    studio = await client.post(f"/api/projects/{slug}/studio", json={"doc_type": "summary"}, headers=h)
    assert studio.status_code == 200, studio.text

    await _wipe_index_dir(client, h)
    projects = (await client.get("/api/projects", headers=h)).json()["projects"]
    assert projects[0]["chunk_count"] > 0


async def test_index_from_before_the_table_existed_is_backfilled(client, space):
    """A space indexed before project_indexes existed has a file but no
    row — the first read must copy it in, so a later wipe can't lose it."""
    from sqlalchemy import delete, select

    from server.db.session import async_session
    from server.domains.knowledge.models import KnowledgeSpace, ProjectIndex

    h, slug = space["headers"], space["slug"]
    user_id = (await client.get("/api/auth/me", headers=h)).json()["id"]
    async with async_session() as db:  # simulate the pre-migration state — THIS space's row only
        space_id = await db.scalar(
            select(KnowledgeSpace.id).where(KnowledgeSpace.user_id == user_id, KnowledgeSpace.slug == slug)
        )
        await db.execute(delete(ProjectIndex).where(ProjectIndex.knowledge_space_id == space_id))
        await db.commit()

    await client.get(f"/api/v1/knowledge-spaces/{slug}/search", params={"q": "ATP"}, headers=h)  # backfills
    await _wipe_index_dir(client, h)
    found = (await client.get(f"/api/v1/knowledge-spaces/{slug}/search", params={"q": "ATP"}, headers=h)).json()
    assert found["results"]
