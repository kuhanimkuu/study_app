# Image input — engine.
#
# What this file is supposed to do:
#   - Accept image bytes from camera / gallery / file / screenshot.
#   - Pass the image to OCR + vision (content identification) to extract
#     text / math / table / graph content.
#   - Return a classified-request shape with the detected content.
#
# Input:  image bytes (or file reference)
# Output: {"input_type": "image", "content": ..., "detected": [...]}
# Status: ✅ core v1
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
