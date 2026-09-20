"""
Per-user symmetric encryption — AES-256-GCM, a standard, modern AEAD
cipher with solid support in both Python and Dart (unlike trying to
replicate Python's Fernet token format byte-for-byte in Dart, which would
mean hand-rolling Fernet's exact framing in a language that has no native
Fernet library).

Each user gets their OWN key, generated at signup and stored both
server-side (users.encryption_key) and on the device (secure storage) —
see routers/auth.py, which returns the key once in the signup/login
response. This is the mechanism behind the project's local-first design:
the device is the source of truth for app data (chat history, memory log,
BYOK settings), encrypted at rest with this key; the server holds its own
copy solely so it CAN decrypt data the device sends along with a request
that needs server-side processing (e.g. a BYOK API key for a model call)
— the server does not persist that decrypted value afterward, only uses
it for the duration of the one request.

Wire format (must match the Dart-side implementation exactly — see
frontend/lib/core/crypto/... ): base64url(
    12-byte random nonce || AES-256-GCM(plaintext) with a 16-byte tag
)
"""
from __future__ import annotations

import base64
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

_KEY_BYTES = 32  # AES-256
_NONCE_BYTES = 12  # standard nonce size for GCM


def generate_user_key() -> str:
    """A fresh random key for a new user at signup — base64url text so it
    travels safely in JSON and secure-storage APIs on either side."""
    return base64.urlsafe_b64encode(os.urandom(_KEY_BYTES)).decode()


def encrypt_for_user(key_b64: str, plaintext: str) -> str:
    key = base64.urlsafe_b64decode(key_b64)
    aesgcm = AESGCM(key)
    nonce = os.urandom(_NONCE_BYTES)
    ciphertext = aesgcm.encrypt(nonce, plaintext.encode(), None)
    return base64.urlsafe_b64encode(nonce + ciphertext).decode()


def decrypt_for_user(key_b64: str, token_b64: str) -> str:
    key = base64.urlsafe_b64decode(key_b64)
    aesgcm = AESGCM(key)
    raw = base64.urlsafe_b64decode(token_b64)
    nonce, ciphertext = raw[:_NONCE_BYTES], raw[_NONCE_BYTES:]
    return aesgcm.decrypt(nonce, ciphertext, None).decode()
