# PDF input — engine.
#
# What this file is supposed to do:
#   - Accept a PDF file (notes / textbook / past paper / assignment).
#   - Extract metadata, text, and page structure.
#   - Hand the extracted text + structure to the moderator.
#
# Input:  PDF file
# Output: {"input_type": "pdf", "content": "...", "structure": {...}}
# Status: ✅ core v1
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
