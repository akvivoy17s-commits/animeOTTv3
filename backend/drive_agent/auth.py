"""Admin-only guard: verifies the Firebase ID token and users/{uid}.role == 'admin' (same rule as the app)."""
from __future__ import annotations
import os
import time

from fastapi import Header, HTTPException


_SA_KEYS = (
    "type", "project_id", "private_key_id", "private_key", "client_email",
    "client_id", "auth_uri", "token_uri", "auth_provider_x509_cert_url",
    "client_x509_cert_url", "universe_domain",
)


def load_credentials():
    """Firebase service account, first match wins:
    1. FIREBASE_SERVICE_ACCOUNT_JSON  - the whole JSON text in one env var
    2. one env var per JSON field (project_id, private_key, client_email, ...)
    3. FIREBASE_SERVICE_ACCOUNT_FILE  - path to the JSON file (default serviceAccount.json)
    """
    import json
    from firebase_admin import credentials

    info = None
    raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    if raw:
        try:
            info = json.loads(raw)
        except ValueError:
            raise RuntimeError("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON.")
    else:
        def env(k: str) -> str:
            return os.getenv(k) or os.getenv(k.upper()) or ""

        if env("private_key") and env("client_email"):
            info = {k: env(k) for k in _SA_KEYS if env(k)}
            info.setdefault("type", "service_account")

    if info is not None:
        key = info.get("private_key")
        if isinstance(key, str):
            info["private_key"] = key.strip().strip('"').replace("\\n", "\n")
        return credentials.Certificate(info)

    path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE", "serviceAccount.json")
    if not os.path.isfile(path):
        raise RuntimeError(f"Server is missing the Firebase service account ({path}).")
    return credentials.Certificate(path)


def init_firebase() -> None:
    import firebase_admin
    if firebase_admin._apps:
        return
    try:
        firebase_admin.initialize_app(load_credentials())
    except RuntimeError as e:
        raise HTTPException(503, str(e))


_ADMIN_OK: dict[str, float] = {}   # uid -> expiry (skips Firestore read on every poll)


def require_admin(authorization: str | None = Header(default=None)) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Missing login token.")
    init_firebase()
    from firebase_admin import auth, firestore
    try:
        decoded = auth.verify_id_token(authorization[7:].strip())
    except Exception:
        raise HTTPException(401, "Invalid or expired login token.")
    uid = decoded["uid"]
    if _ADMIN_OK.get(uid, 0) < time.time():
        snap = firestore.client().collection("users").document(uid).get()
        if not snap.exists or (snap.to_dict() or {}).get("role") != "admin":
            _ADMIN_OK.pop(uid, None)
            raise HTTPException(403, "Admin access required.")
        _ADMIN_OK[uid] = time.time() + 60
    return {"uid": decoded["uid"], "email": decoded.get("email", "")}
