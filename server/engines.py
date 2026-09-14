"""
Loads and exposes every features/ engine the HTTP layer calls, once, so the
routers/ package shares a single set of loaded modules instead of each
router reloading its own copy.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

REPO_ROOT = Path(__file__).resolve().parent.parent
FEATURES_ROOT = REPO_ROOT / "features"


def _load_engine(relative_path: str) -> ModuleType:
    path = FEATURES_ROOT / relative_path
    module_name = "server_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


moderator = _load_engine("moderator/engine.py")
text_input = _load_engine("input_pipeline/text_input/engine.py")
image_input = _load_engine("input_pipeline/image_input/engine.py")
pdf_input = _load_engine("input_pipeline/pdf_input/engine.py")
audio_input = _load_engine("input_pipeline/audio_input/engine.py")
web_input = _load_engine("input_pipeline/web_input/engine.py")
query_memory = _load_engine("personalization/query_memory/engine.py")
rag_projects = _load_engine("rag/projects/engine.py")
generate_docs = _load_engine("document_generation/generate_docs/engine.py")

# Reuses the SAME loaded instance `moderator` already holds internally
# (as `_model_router`) rather than a second `_load_engine(...)` call —
# model_router eagerly loads LLM weights at import time (see its own
# README), so loading it twice would double memory usage and startup time
# for no benefit. Used by domains/assessment/grading.py for short-answer
# AI evaluation.
model_router = moderator._model_router
