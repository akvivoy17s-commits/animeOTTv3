import os

from dotenv import load_dotenv

load_dotenv()  # must run before the imports below read env vars

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from drive_agent.api import router as drive_router

app = FastAPI(title="Anime Portal Drive Agent")

# Web builds need CORS. Production: ALLOWED_ORIGINS=https://your-web-domain.com
_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Authorization"],
)

app.include_router(drive_router)  # admin-only Drive upload agent


@app.get("/health")
def health():
    return {"ok": True}
