# Features

Each feature lives in its own folder:

```
features/
  <category>/
    <feature>/
      engine.py   # the engine's entry point (resumable coroutine)
      README.md   # input, output, status, notes
```

## Convention

- **One feature = one folder** — see `features.md` for the full inventory and statuses.
- **Build + test standalone:** run `python engine.py` (has a `__main__` test block).
- **JSON output is decided AFTER the engine works** (see `json.md`) — not up front.
- **Engines are `async` coroutines** so the moderator/scheduler can pause, yield
  partial results, and resume them (see `PATHWAY.md` §0).

## Status legend

- ✅ core v1 — build first
- ⏳ later phase
- 🚫 deferred / optional

## Notes

- `__init__.py` files are added later, once engines start importing each other
  (needed when the moderator begins calling engines).
