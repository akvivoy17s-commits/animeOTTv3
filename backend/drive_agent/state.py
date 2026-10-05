"""State / queue manager (SQLite, stdlib only). Gives resume + no-duplicate guarantees."""
from __future__ import annotations
import json
import sqlite3
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional

from .log import get
from .models import DriveVideo, Job, Status, VideoMeta

log = get("state")

SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs(
  file_id TEXT PRIMARY KEY, source_folder TEXT, name TEXT, url TEXT,
  status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
  error TEXT DEFAULT '', doc_id TEXT DEFAULT '',
  video_json TEXT NOT NULL, meta_json TEXT DEFAULT '', override_json TEXT DEFAULT '',
  created_at TEXT, updated_at TEXT);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class StateStore:
    def __init__(self, db_path: Path, recover: bool = True):
        db_path = Path(db_path)
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(db_path)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)
        cols = {r["name"] for r in self.db.execute("PRAGMA table_info(jobs)")}
        if "override_json" not in cols:                 # DB created before the edit feature
            self.db.execute("ALTER TABLE jobs ADD COLUMN override_json TEXT DEFAULT ''")
            self.db.commit()
        n = self.recover_stale() if recover else 0
        if n:
            log.warning("Recovered %d job(s) left in_progress by a previous crash", n)

    def close(self) -> None:
        self.db.close()

    def __enter__(self): return self
    def __exit__(self, *a): self.close()

    # -- loading -------------------------------------------------------------
    def add_videos(self, videos: Iterable[DriveVideo], source_folder: str = "") -> int:
        """Insert unseen videos as pending. Known file_ids (any status) are left untouched."""
        before = self.db.total_changes
        now = _now()
        self.db.executemany(
            "INSERT OR IGNORE INTO jobs(file_id,source_folder,name,url,status,video_json,created_at,updated_at)"
            " VALUES(?,?,?,?,?,?,?,?)",
            [(v.file_id, source_folder, v.name, v.web_view_link, Status.PENDING.value,
              json.dumps(asdict(v)), now, now) for v in videos])
        self.db.commit()
        added = self.db.total_changes - before
        log.info("Queue: %d new video(s) added", added)
        return added

    # -- work loop -----------------------------------------------------------
    def claim_next(self, retry_failed: bool = False, max_attempts: int = 3) -> Optional[Job]:
        """Atomically take the next job (pending first, then retryable failed) and mark it in_progress."""
        row = self.db.execute(
            "SELECT * FROM jobs WHERE status='pending' OR (status='failed' AND ?=1 AND attempts<?)"
            " ORDER BY (status='failed'), rowid LIMIT 1", (int(retry_failed), max_attempts)).fetchone()
        if not row:
            return None
        self.db.execute("UPDATE jobs SET status=?, attempts=attempts+1, updated_at=? WHERE file_id=?",
                        (Status.IN_PROGRESS.value, _now(), row["file_id"]))
        self.db.commit()
        return self._job(self.db.execute("SELECT * FROM jobs WHERE file_id=?", (row["file_id"],)).fetchone())

    def set_meta(self, file_id: str, meta: VideoMeta) -> None:
        self._update(file_id, meta_json=json.dumps(asdict(meta)))

    def set_overrides(self, overrides: dict) -> int:
        """Save admin edits for jobs that have not been uploaded yet (done/skipped are left alone)."""
        n = 0
        for fid, ov in overrides.items():
            cur = self.db.execute(
                "UPDATE jobs SET override_json=?, updated_at=? WHERE file_id=? AND status IN ('pending','failed','in_progress')",
                (json.dumps(ov), _now(), fid))
            n += cur.rowcount
        self.db.commit()
        return n

    def get_overrides(self) -> dict:
        return {r["file_id"]: json.loads(r["override_json"]) for r in
                self.db.execute("SELECT file_id, override_json FROM jobs WHERE override_json!='' AND status!='done'")}

    def mark_done(self, file_id: str, doc_id: str = "") -> None:
        self._update(file_id, status=Status.DONE.value, doc_id=doc_id, error="")

    def mark_failed(self, file_id: str, error: str) -> None:
        self._update(file_id, status=Status.FAILED.value, error=str(error)[:500])

    def mark_skipped(self, file_id: str, reason: str = "") -> None:
        self._update(file_id, status=Status.SKIPPED.value, error=reason[:500])

    # -- maintenance / reporting ----------------------------------------------
    def recover_stale(self) -> int:
        cur = self.db.execute("UPDATE jobs SET status='pending', updated_at=? WHERE status='in_progress'", (_now(),))
        self.db.commit()
        return cur.rowcount

    def reset_failed(self) -> int:
        cur = self.db.execute("UPDATE jobs SET status='pending', attempts=0, error='', updated_at=? WHERE status='failed'", (_now(),))
        self.db.commit()
        return cur.rowcount

    def stats(self) -> dict:
        out = {s.value: 0 for s in Status}
        for r in self.db.execute("SELECT status, COUNT(*) c FROM jobs GROUP BY status"):
            out[r["status"]] = r["c"]
        out["total"] = sum(out.values())
        return out

    def failed(self) -> list[Job]:
        return [self._job(r) for r in self.db.execute("SELECT * FROM jobs WHERE status='failed' ORDER BY rowid")]

    # -- internals -----------------------------------------------------------
    def _update(self, file_id: str, **cols) -> None:
        cols["updated_at"] = _now()
        sets = ", ".join(f"{k}=?" for k in cols)
        self.db.execute(f"UPDATE jobs SET {sets} WHERE file_id=?", (*cols.values(), file_id))
        self.db.commit()

    @staticmethod
    def _job(r: sqlite3.Row) -> Job:
        return Job(
            file_id=r["file_id"], video=DriveVideo(**json.loads(r["video_json"])),
            meta=VideoMeta(**json.loads(r["meta_json"])) if r["meta_json"] else None,
            status=Status(r["status"]), attempts=r["attempts"], error=r["error"] or "", doc_id=r["doc_id"] or "",
            override=json.loads(r["override_json"]) if r["override_json"] else {})
