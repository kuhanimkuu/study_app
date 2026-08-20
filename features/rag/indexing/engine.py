# Indexing (chunking + embedding + vector index) — engine.
#
# What this file is supposed to do:
#   - Chunk documents into pieces.
#   - Embed each chunk and build a vector index.
#   - Return a reference to the searchable index.
#
# Input:  documents (list of chunks)
# Output: {"index": "...", "chunks": N}
# Status: ⏳ later phase
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
