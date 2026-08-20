# Moderator — engine.
#
# What this file is supposed to do:
#   - Receive the classified request from the input engine.
#   - Understand intent ("what are they asking?").
#   - Decide the response format (respect user request, else reason best format).
#   - Pick the engines (tools) to call.
#   - Author the explanation prose (this is where the AI's language ability lives).
#   - Assemble the final blocks (facts from engines + its own prose).
#   - Handle clarification (ask the user) and error (surface honestly).
#   - Record activity to the memory log.
#
# Input:  classified request (input_type, content, task, requested_format)
# Output: {"blocks": [...]}
# Status: ⏳ later phase (rule-based stub first, LLM later)
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
