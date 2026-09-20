"""
Response block contracts — Shape 5 ("moderator -> Flutter") of json.md's
five-shape pipeline, and the block list described in
STUDY_OS_PRODUCTION_BLUEPRINT.md Section 28 ("Response Block Architecture").

Lives at server/ai/schemas/ rather than alongside features/moderator/ on
purpose: this is where the blueprint's target backend structure (Section 49)
puts contracts shared across the AI layer, and server/ already uses normal
package imports (unlike features/, which deliberately loads engines via
importlib — see features/README.md's "Notes" — so this module is not meant
to be imported from there; it's consumed at the HTTP boundary in
routers/ask.py only).

Each block model below was reverse-engineered from what features/moderator/
engine.py and the engines it calls ACTUALLY construct today (verified by
reading every block-producing call site and its source engine's real output
shape, not from json.md's aspirational examples alone — e.g. the diagram
engine's "elements" are {id, label, x, y} objects, not the bare strings the
INPUT side of that same engine accepts). Extend this union when a new block
type is genuinely produced somewhere; blueprint Section 28 lists several
block types (heading, video, audio, quiz, flashcards, progress,
recommendation, study_task, mistake, mastery, document, clarification) that
no engine emits yet — they belong here once real code produces them, not
before.
"""
from __future__ import annotations

from typing import Annotated, Any, Literal, Union

from pydantic import BaseModel, Field


class TextBlock(BaseModel):
    type: Literal["text"] = "text"
    content: str
    source: str


class EquationBlock(BaseModel):
    type: Literal["equation"] = "equation"
    latex: str
    source: str


class InteractiveGraphBlock(BaseModel):
    type: Literal["interactive_graph"] = "interactive_graph"
    data: dict[str, Any]
    latex: str | None = None
    source: str


class ClarificationBlock(BaseModel):
    type: Literal["clarification"] = "clarification"
    question: str


class ErrorBlock(BaseModel):
    type: Literal["error"] = "error"
    engine: str
    message: str


class SourceBlock(BaseModel):
    type: Literal["source"] = "source"
    content: str
    source: str


class TableBlock(BaseModel):
    type: Literal["table"] = "table"
    headers: list[str]
    rows: list[list[str]]
    source: str


class StaticImageBlock(BaseModel):
    type: Literal["static_image"] = "static_image"
    content: str
    format: str
    source: str


class PdfBlock(BaseModel):
    type: Literal["pdf"] = "pdf"
    content: str
    doc_type: str
    source: str


class DiagramElement(BaseModel):
    id: int
    label: str
    x: float
    y: float


class DiagramBlock(BaseModel):
    type: Literal["diagram"] = "diagram"
    kind: str
    elements: list[DiagramElement]
    relationships: list[list[int]]
    source: str


class AnimationBlock(BaseModel):
    type: Literal["animation"] = "animation"
    content: str
    fps: float
    source: str


class ThreeDBlock(BaseModel):
    type: Literal["3d"] = "3d"
    content: str
    format: str
    source: str


Block = Annotated[
    Union[
        TextBlock,
        EquationBlock,
        InteractiveGraphBlock,
        ClarificationBlock,
        ErrorBlock,
        SourceBlock,
        TableBlock,
        StaticImageBlock,
        PdfBlock,
        DiagramBlock,
        AnimationBlock,
        ThreeDBlock,
    ],
    Field(discriminator="type"),
]


class ModeratorResponse(BaseModel):
    """The shape every /api/ask/* endpoint returns. `activity` mirrors
    features/moderator/engine.py's run() doc comment: a suggested entry for
    the (local-first) client to write to its own activity log, never
    persisted server-side."""

    blocks: list[Block]
    session_id: str
    activity: dict[str, Any] | None = None
