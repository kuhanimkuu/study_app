# OCR on scanned pages — engine.
#
# What this file is supposed to do:
#   - Detect image-only (scanned) pages in a PDF.
#   - Run OCR on those pages to extract text.
#   - Return the extracted text keyed by page number.
#
# Input:  scanned PDF + page range
# Output: {"text": {page_number: "..."}}
# Status: ⏳ later phase
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
