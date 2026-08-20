# Content identification (vision routing) — engine.
#
# What this file is supposed to do:
#   - Look at an image and classify what kind of content it holds:
#     text, handwriting, math, graph, diagram, photo, or table.
#   - Return the route + confidence so the moderator picks the right engine.
#
# Input:  image
# Output: {"route": "...", "confidence": 0.0}
# Status: ⏳ later phase
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
