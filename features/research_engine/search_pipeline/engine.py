# Search pipeline — engine.
#
# What this file is supposed to do:
#   - Run the full research pipeline: search, fetch, parse, clean, rank,
#     dedupe, and extract sources.
#   - Return curated, ranked sources. (Deferred: realistically server-side.)
#
# Input:  query
# Output: {"sources": [{title, url, snippet, rank}]}
# Status: 🚫 deferred / optional (server-class work)
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
