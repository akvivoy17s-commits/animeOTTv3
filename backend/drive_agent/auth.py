# """Admin-only guard: verifies the Firebase ID token and users/{uid}.role == 'admin' (same rule as the app)."""
# from __future__ import annotations
# import os

# from fastapi import Header, HTTPException


# def init_firebase() -> None:
#     import firebase_admin
#     from firebase_admin import credentials
#     if firebase_admin._apps:
#         return
#     path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE", "serviceAccount.json")
#     if not os.path.isfile(path):
#         raise HTTPException(503, f"Server is missing the Firebase service account file ({path}).")
#     firebase_admin.initialize_app(credentials.Certificate(path))


# def require_admin(authorization: str | None = Header(default=None)) -> dict:
#     if not authorization or not authorization.lower().startswith("bearer "):
#         raise HTTPException(401, "Missing login token.")
#     init_firebase()
#     from firebase_admin import auth, firestore
#     try:
#         decoded = auth.verify_id_token(authorization[7:].strip())
#     except Exception:
#         raise HTTPException(401, "Invalid or expired login token.")
#     snap = firestore.client().collection("users").document(decoded["uid"]).get()
#     if not snap.exists or (snap.to_dict() or {}).get("role") != "admin":
#         raise HTTPException(403, "Admin access required.")
#     return {"uid": decoded["uid"], "email": decoded.get("email", "")}

#     try:
#         decoded = auth.verify_id_token(authorization[7:].strip())
#     except Exception as e:
#         print("TOKEN VERIFY ERROR:", type(e).__name__, e)   # <-- add this
#         raise HTTPException(401, "Invalid or expired login token.")














"""Admin-only guard: verifies the Firebase ID token and users/{uid}.role == 'admin' (same rule as the app)."""
from __future__ import annotations
import os

from fastapi import Header, HTTPException


def init_firebase() -> None:
    import firebase_admin
    from firebase_admin import credentials
    if firebase_admin._apps:
        return
    path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE", "serviceAccount.json")
    if not os.path.isfile(path):
        raise HTTPException(503, f"Server is missing the Firebase service account file ({path}).")
    firebase_admin.initialize_app(credentials.Certificate(path))


def require_admin(authorization: str | None = Header(default=None)) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Missing login token.")
    init_firebase()
    from firebase_admin import auth, firestore
    try:
        decoded = auth.verify_id_token(authorization[7:].strip())
    except Exception as e:
        print("TOKEN VERIFY ERROR:", type(e).__name__, e)   # debug
        raise HTTPException(401, "Invalid or expired login token.")
    snap = firestore.client().collection("users").document(decoded["uid"]).get()
    if not snap.exists or (snap.to_dict() or {}).get("role") != "admin":
        raise HTTPException(403, "Admin access required.")
    return {"uid": decoded["uid"], "email": decoded.get("email", "")}