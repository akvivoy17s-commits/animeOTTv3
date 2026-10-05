"""Agent / orchestrator: Drive -> parse -> queue -> upload (resume, retries, circuit breaker, progress hooks)."""
from __future__ import annotations
import time
from typing import Callable, Optional

from .config import Config
from .drive_reader import DriveReader, extract_folder_id
from .log import get
from .parser import apply_override, parse
from .state import StateStore
from .uploader import UploadError, extract_drive_id, make_uploader

log = get("agent")
MAX_CONSECUTIVE_FAILURES = 5


def _firestore_alive(doc_ids: list[str]) -> set[str]:
    """Which of these videos/<doc_id> documents still exist in Firestore."""
    from firebase_admin import firestore
    from .auth import init_firebase
    init_firebase()
    db = firestore.client()
    col, alive = db.collection("videos"), set()
    for k in range(0, len(doc_ids), 300):
        refs = [col.document(d) for d in doc_ids[k:k + 300]]
        alive |= {s.id for s in db.get_all(refs, field_paths=["title"]) if s.exists}
    return alive


class Agent:
    def __init__(self, cfg: Config, reader=None, uploader=None, store: Optional[StateStore] = None,
                 on_event: Callable[[str, dict], None] | None = None,
                 should_stop: Callable[[], bool] | None = None):
        self.cfg = cfg
        self._reader, self._uploader = reader, uploader
        self.store = store or StateStore(cfg.state_db)
        self._emit = on_event or (lambda kind, data: None)
        self._stop = should_stop or (lambda: False)

    @property
    def reader(self):
        self._reader = self._reader or DriveReader(self.cfg)
        return self._reader

    @property
    def uploader(self):
        self._uploader = self._uploader or make_uploader(self.cfg)
        return self._uploader

    def forget(self, doc_ids=(), urls=()) -> int:
        """A video was deleted from the app: erase it from the agent DB (by Firestore doc id and/or Drive URL)."""
        fids = set(self.store.file_ids_for_docs(doc_ids))
        fids |= {d[6:] for d in doc_ids if d.startswith("drive_")}
        fids |= {f for f in (extract_drive_id(u) for u in urls if u) if f}
        return self.store.forget(fids)

    def reconcile(self, exists=None) -> int:
        """Safety net: forget every 'done' video whose Firestore document no longer exists
        (deleted from the app, the Firebase console, anywhere). Skipped on any lookup error, never wipes blindly."""
        if exists is None and self.cfg.upload_mode != "firestore":
            return 0
        rows = self.store.done_docs()
        if not rows:
            return 0
        try:
            alive = (exists or _firestore_alive)(sorted(set(rows.values())))
        except Exception as e:
            log.warning("Reconcile skipped: %s", e)
            return 0
        return self.store.forget([f for f, d in rows.items() if d not in alive])

    def plan(self, folder_url: str | None = None) -> list:
        rows = []
        self.reconcile()                                      # deleted-in-app videos become 'new' again
        saved = self.store.get_overrides()                    # edits kept from an earlier, unfinished run
        for v in self.reader.read_folder(folder_url):
            m = parse(v, self.cfg.category)
            known = self.store.db.execute("SELECT status FROM jobs WHERE file_id=?", (v.file_id,)).fetchone()
            if v.file_id in saved:
                apply_override(m, saved[v.file_id])
            rows.append((v, m, known["status"] if known else "new"))
        return rows

    def run(self, folder_url: str | None = None, retry_failed: bool = False,
            limit: int | None = None, scan: bool = True, overrides: dict | None = None) -> dict:
        url = folder_url or self.cfg.drive_folder_url
        stopped = False
        if scan:
            self.reconcile()
            self._emit("scanning", {})
            videos = self.reader.read_folder(url)
            added = self.store.add_videos(videos, source_folder=extract_folder_id(url))
            self._emit("scanned", {"found": len(videos), "new": added})
        if overrides:
            self.store.set_overrides(overrides)
        done = failed = streak = 0
        try:
            while limit is None or (done + failed) < limit:
                if self._stop():
                    stopped = True
                    log.warning("Stop requested")
                    break
                job = self.store.claim_next(retry_failed, self.cfg.max_retries)
                if job is None:
                    break
                tag = f"[{job.video.name}] (attempt {job.attempts})"
                self._emit("start", {"name": job.video.name})
                try:
                    job.meta = apply_override(parse(job.video, self.cfg.category), job.override)
                    self.store.set_meta(job.file_id, job.meta)
                    ref = self.uploader.upload(job)
                    self.store.mark_done(job.file_id, ref)
                    done, streak = done + 1, 0
                    log.info("OK  %s -> %s", tag, ref)
                    self._emit("ok", {"name": job.video.name, "title": job.meta.title,
                                      "season": job.meta.season, "episode": job.meta.episode})
                except Exception as e:                       # UploadError or unexpected: never lose the job
                    msg = str(e) if isinstance(e, UploadError) else f"{type(e).__name__}: {e}"
                    self.store.mark_failed(job.file_id, msg)
                    failed, streak = failed + 1, streak + 1
                    log.error("FAIL %s: %s", tag, msg)
                    self._emit("fail", {"name": job.video.name, "error": msg})
                if streak >= MAX_CONSECUTIVE_FAILURES:
                    log.critical("%d failures in a row - stopping", streak)
                    self._emit("aborted", {"reason": f"{streak} failures in a row (check credentials / Drive access)"})
                    break
                time.sleep(self.cfg.delay_seconds)
        except KeyboardInterrupt:
            self.store.recover_stale()
        finally:
            if self._uploader:
                self._uploader.close()
        res = {"run_done": done, "run_failed": failed, "stopped": stopped, **self.store.stats()}
        log.info("Run finished: %s", res)
        return res
