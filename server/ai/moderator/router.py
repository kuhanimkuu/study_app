"""
POST /api/v1/concepts/{concept_id}/explain — the first real "adaptive"
capability: explains a Concept, depth adapted to the student's actual
Mastery state. See student_state.py / explain.py for the logic; this file
is just the HTTP boundary.

Response is a purpose-built model, not the full ModeratorResponse shape
from server/ai/schemas/ — session_id/activity are clarification-loop /
local-first-era fields (see routers/ask.py) that don't apply to a
standalone explain call. Block/TextBlock are still reused directly, since
those genuinely fit (this is the first consumer of that contract outside
/api/ask/*, real validation it wasn't over-specialized to one call site).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...core.model_config import ModelConfig, resolve_model_config
from ...db.session import get_db
from ...domains.learning.router import get_concept_or_404
from ..schemas import Block, TextBlock
from .explain import decide_depth, generate_explanation
from .student_state import get_student_state

router = APIRouter(prefix="/api/v1")


class ExplainRequest(BaseModel):
    # Same pydantic-v2-reserved-name workaround as TextAsk/SubmitAttempt.
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


class ExplainResponse(BaseModel):
    blocks: list[Block]
    depth: str
    reasoning: str


@router.post("/concepts/{concept_id}/explain", response_model=ExplainResponse)
async def explain_concept(
    concept_id: int,
    payload: ExplainRequest | None = None,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ExplainResponse:
    concept = await get_concept_or_404(db, current_user["id"], concept_id)
    state = await get_student_state(db, current_user["id"], concept)
    # get_student_state may have just get-or-created a default
    # PersonalityProfile row (flushed but not committed) — commit so a
    # first-time default actually persists instead of silently rolling
    # back at the end of this request every time.
    await db.commit()
    depth = decide_depth(state)

    model_config = resolve_model_config(payload.model_config_ if payload else None, current_user)
    text, reasoning = await generate_explanation(concept, state, depth, model_config)

    return ExplainResponse(blocks=[TextBlock(content=text, source="moderator")], depth=depth, reasoning=reasoning)
