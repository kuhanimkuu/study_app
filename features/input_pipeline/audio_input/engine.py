# Audio input — engine.
#
# What this file is supposed to do:
#   - Accept spoken audio.
#   - Run speech recognition (ASR) to transcribe it to text.
#   - Return the transcribed text to the moderator as a normal text request.
#
# Input:  voice / audio bytes
# Output: {"input_type": "text", "content": "..."}
# Status: ⏳ later phase
#
# The Python structure + JSON contract live in skeleton.py.
# Implement the real logic here.
