# Memory log — engine.
#
# What this file is supposed to do:
#   - Record a labelled activity event (quiz, solve, read, ...) with topic,
#     score, and labels.
#   - Store it in one big, well-labelled log for later querying.
#
# Input:  activity event
# Output: {"status": "logged", "event_id": "..."}
# Status: ⏳ later phase
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
