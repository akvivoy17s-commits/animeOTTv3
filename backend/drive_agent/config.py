"""Central configuration. Single source of truth; reads .env, CLI may override."""
from __future__ import annotations
import os
from dataclasses import dataclass
from pathlib import Path
from dotenv import load_dotenv


def _b(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Config:
    drive_folder_url: str
    google_api_key: str
    google_sa_file: str
    upload_mode: str
    firebase_sa_file: str
    uploaded_by_email: str
    uploaded_by_uid: str
    app_url: str
    app_email: str
    app_password: str
    category: str
    recursive: bool
    delay_seconds: float
    max_retries: int
    state_db: Path
    log_dir: Path
    log_level: str
    headless: bool

    @classmethod
    def load(cls, env_file: str = ".env", validate: bool = True, **overrides) -> "Config":
        load_dotenv(env_file)
        g = os.getenv
        cfg = dict(
            drive_folder_url=g("DRIVE_FOLDER_URL", ""),
            google_api_key=g("GOOGLE_API_KEY", ""),
            google_sa_file=g("GOOGLE_SERVICE_ACCOUNT_FILE", ""),
            upload_mode=g("UPLOAD_MODE", "firestore").lower(),
            firebase_sa_file=g("FIREBASE_SERVICE_ACCOUNT_FILE", "serviceAccount.json"),
            uploaded_by_email=g("UPLOADED_BY_EMAIL", ""),
            uploaded_by_uid=g("UPLOADED_BY_UID", ""),
            app_url=g("APP_URL", ""),
            app_email=g("APP_EMAIL", ""),
            app_password=g("APP_PASSWORD", ""),
            category=g("CATEGORY", "series").lower(),
            recursive=_b("RECURSIVE", True),
            delay_seconds=float(g("DELAY_SECONDS", "1.0")),
            max_retries=int(g("MAX_RETRIES", "3")),
            state_db=Path(g("STATE_DB", "data/state.db")),
            log_dir=Path(g("LOG_DIR", "logs")),
            log_level=g("LOG_LEVEL", "INFO").upper(),
            headless=_b("HEADLESS", True),
        )
        cfg.update({k: v for k, v in overrides.items() if v is not None})
        c = cls(**cfg)
        if validate:
            c.validate()
        return c

    def validate(self) -> None:
        errs = []
        if not self.drive_folder_url:
            errs.append("DRIVE_FOLDER_URL is required")
        if not (self.google_api_key or self.google_sa_file):
            errs.append("Set GOOGLE_API_KEY or GOOGLE_SERVICE_ACCOUNT_FILE")
        if self.upload_mode not in ("firestore", "browser"):
            errs.append("UPLOAD_MODE must be firestore or browser")
        if self.category not in ("series", "movies"):
            errs.append("CATEGORY must be series or movies")
        if self.upload_mode == "browser" and not (self.app_url and self.app_email and self.app_password):
            errs.append("browser mode needs APP_URL, APP_EMAIL, APP_PASSWORD")
        if errs:
            raise ValueError("Config errors:\n- " + "\n- ".join(errs))
