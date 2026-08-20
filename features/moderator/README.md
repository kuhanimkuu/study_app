# Moderator (orchestrator)

> Status: ✅ core v1 (start rule-based, swap in LLM later)

- **Input:** classified request (from the input engine)
- **Output:** assembled response blocks

## Responsibilities

1. Understand intent ("what are they asking?")
2. Decide the response format (respect user request OR reason the best format)
3. Pick the engine(s) — the "tools" (carpenter analogy)
4. **Author the explanation prose** (the engines only produce facts)
5. Assemble facts + its own prose → blocks

## State

- **Pending context** — short-term: "what did I just ask the user?" (clarification loop)
- **Activity table** — long-term: labelled memory log (see personalization)

See `PATHWAY.md` §0 and `json.md` for the full pipeline and shapes.

## JSON shape
<!-- fill in during the json.md mapping exercise -->

## Notes
- Engines are called as resumable coroutines; the moderator is the scheduler.
