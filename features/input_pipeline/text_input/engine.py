# Text input — engine.
#
# What this file is supposed to do:
#   - Accept a typed string from the user.
#   - Normalize/validate it into the classified-request shape
#     (input_type, content) that the moderator understands.
#   - Optionally trim, encode, and reject empty input.
#
# Input:  typed string (e.g. "2x + 3 = 7")
# Output: {"input_type": "text", "content": "2x + 3 = 7"}
# Status: ✅ core v1
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
