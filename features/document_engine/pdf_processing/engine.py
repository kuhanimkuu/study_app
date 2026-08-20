# PDF processing — engine.
#
# What this file is supposed to do:
#   - Open a PDF and extract metadata, text, page structure, images,
#     tables, and equations.
#   - Return the structured extraction for indexing/search.
#
# Input:  PDF file
# Output: {"metadata": {...}, "text": "...", "pages": [...], "tables": [], "equations": []}
# Status: ✅ core v1
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
