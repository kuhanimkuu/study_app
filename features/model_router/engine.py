# Model router — engine.
#
# What this file is supposed to do:
#   - Decide which model tier handles a task (tiny / main / specialized).
#   - Return the model choice + reason.
#
# Input:  task + text
# Output: {"model": "...", "reason": "..."}
# Status: ⏳ later phase
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
