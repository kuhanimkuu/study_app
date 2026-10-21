"""The project chat as a full tutor (2026-10-21): it answers from the
student's notes when they cover the question (and may add general
knowledge, marked), and otherwise behaves like the general chat —
greetings, any topic, a project with no material yet — with a "Learn more"
card of real links under explanations. Real embeddings; the model, intent
analysis and web search are faked."""
from __future__ import annotations

import types

import pytest

from features.moderator import engine as moderator

NOTES = [
    "Mitosis is the division of a cell nucleus into two identical nuclei. Its phases are prophase, metaphase, anaphase and telophase.",
    "Meiosis produces four genetically different gametes with half the chromosome number, through two divisions.",
    "Enzymes are biological catalysts. Their activity depends on temperature and pH; high temperatures denature them.",
]


@pytest.fixture
def chat(monkeypatch):
    prompts: list[str] = []

    async def fake_model(prompt, max_tokens, **config):
        prompts.append(prompt)
        return {"text": "Here is the explanation.", "usage": None}

    async def no_external(**kwargs):
        return {"needs_external": False}

    web_searches: list[str] = []

    async def fake_search(**kwargs):
        web_searches.append(kwargs["query"])
        return {"sources": [{"title": "Photosynthesis - BBC Bitesize", "url": "https://www.bbc.co.uk/bitesize/photosynthesis", "snippet": "..."}]}

    monkeypatch.setattr(moderator, "_model_router", types.SimpleNamespace(run=fake_model))
    monkeypatch.setattr(moderator, "_intent_analysis", types.SimpleNamespace(run=no_external))
    monkeypatch.setattr(moderator, "_search_pipeline", types.SimpleNamespace(run=fake_search))

    index = {"chunks": NOTES, "vectors": moderator._rag_semantic_search._embed(NOTES)}
    state = {"index": index}
    monkeypatch.setattr(moderator, "_load_project_index", lambda project, projects_dir: state["index"])

    async def ask(query):
        return await moderator._route_project("", "biology", query, user_id=1)

    return types.SimpleNamespace(ask=ask, prompts=prompts, web_searches=web_searches, state=state)


def _types(blocks):
    return [b["type"] for b in blocks]


async def test_a_greeting_gets_a_normal_reply(chat):
    blocks, engine_used, _ = await chat.ask("hello")
    assert engine_used == "model_router"
    assert _types(blocks) == ["text"]  # no "not in your notes", no links


async def test_a_topic_outside_the_notes_is_explained_with_links(chat):
    blocks, _, _ = await chat.ask("explain photosynthesis")
    assert "isn't covered in your **biology** notes" in blocks[0]["content"]
    assert blocks[1]["content"] == "Here is the explanation."
    links = blocks[-1]
    assert links["type"] == "links"
    urls = [link["url"] for link in links["links"]]
    assert "https://en.wikipedia.org/w/index.php?search=photosynthesis" in urls
    assert any(u.startswith("https://www.khanacademy.org/search") for u in urls)
    assert chat.web_searches == []  # web search only when sources are asked for


async def test_a_question_the_notes_cover_is_answered_from_them(chat):
    blocks, engine_used, _ = await chat.ask("what are the phases of mitosis")
    assert engine_used == "project_answer"
    assert "source" in _types(blocks) and blocks[-1]["type"] == "links"
    prompt = chat.prompts[-1]
    assert "prophase" in prompt
    assert "add what you know" in prompt  # may go beyond the notes, marked as such
    assert "Don't write any web addresses" in prompt


async def test_asking_about_the_notes_uses_them_even_without_a_close_match(chat):
    blocks, engine_used, _ = await chat.ask("summarize my notes")
    assert engine_used == "project_answer"
    assert _types(blocks).count("source") == 3
    assert "links" not in _types(blocks)


async def test_a_project_with_no_material_still_answers(chat):
    chat.state["index"] = None
    blocks, engine_used, _ = await chat.ask("teach me quadratic equations")
    assert engine_used == "model_router"
    assert "isn't covered" not in blocks[0]["content"]  # nothing to be covered by
    assert blocks[-1]["type"] == "links"


async def test_asking_for_sources_adds_real_web_results(chat):
    blocks, _, _ = await chat.ask("give me links on photosynthesis")
    assert chat.web_searches == ["photosynthesis"]
    assert blocks[-1]["links"][0] == {"label": "Photosynthesis - BBC Bitesize", "url": "https://www.bbc.co.uk/bitesize/photosynthesis"}


@pytest.mark.parametrize(
    "starter", ["Summarise the main ideas", "What key terms should I know?", "Explain the hardest part simply", "What might come up in an exam?"]
)
async def test_the_apps_starter_cards_use_the_notes(chat, starter):
    _, engine_used, _ = await chat.ask(starter)
    assert engine_used == "project_answer"
