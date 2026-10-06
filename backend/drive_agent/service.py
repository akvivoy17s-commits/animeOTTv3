"""Runs the Agent in one background thread and exposes live progress. No web-framework imports."""
from __future__ import annotations
import threading
import time
from collections import deque
from typing import Callable

from .agent import Agent
from .config import Config
from .log import setup_logging
from .state import StateStore


class Busy(Exception):
    pass


def _default_factory(cfg, on_event, should_stop):
    return Agent(cfg, on_event=on_event, should_stop=should_stop)


class RunManager:
    def __init__(self, agent_factory: Callable = _default_factory):
        self._factory = agent_factory
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._log: deque = deque(maxlen=150)
        self._info = self._blank()
        self._plan_info = {"state": "idle", "result": None, "error": "", "started": 0.0}

    @staticmethod
    def _blank() -> dict:
        return {"state": "idle", "folder": "", "started_at": None, "finished_at": None,
                "found": 0, "new": 0, "done": 0, "failed": 0, "current": "", "error": "", "failures": []}

    def _cfg(self, folder_url: str, category: str, user: dict) -> Config:
        return Config.load(validate=False, upload_mode="firestore", drive_folder_url=folder_url,
                           category=category, uploaded_by_email=user.get("email", ""),
                           uploaded_by_uid=user.get("uid", ""))

    # -- events from the Agent thread -------------------------------------------------------
    def _event(self, kind: str, d: dict) -> None:
        with self._lock:
            i = self._info
            line = None
            if kind == "scanning":
                i["state"], line = "scanning", "Scanning Drive folder..."
            elif kind == "scanned":
                i.update(state="running", found=d["found"], new=d["new"])
                line = f"Found {d['found']} video(s), {d['new']} new"
            elif kind == "start":
                i["current"] = d["name"]
            elif kind == "ok":
                i["done"] += 1
                line = f"OK   {d['title']} (S{d['season']} E{d['episode']})"
            elif kind == "fail":
                i["failed"] += 1
                i["failures"] = (i["failures"] + [{"name": d["name"], "error": d["error"]}])[-30:]
                line = f"FAIL {d['name']}: {d['error']}"
            elif kind == "aborted":
                i["error"], line = d["reason"], f"STOPPED: {d['reason']}"
            if line:
                self._log.append(f"{time.strftime('%H:%M:%S')} {line}")

    def _work(self, cfg: Config, retry_failed: bool, limit, overrides=None):
        try:
            cfg.validate()
            res = self._factory(cfg, self._event, self._stop.is_set).run(
                cfg.drive_folder_url, retry_failed=retry_failed, limit=limit, overrides=overrides)
            with self._lock:
                self._info["state"] = "stopped" if res.get("stopped") else ("error" if self._info["error"] else "finished")
        except Exception as e:
            with self._lock:
                self._info.update(state="error", error=str(e)[:300])
                self._log.append(f"{time.strftime('%H:%M:%S')} ERROR {str(e)[:300]}")
        finally:
            with self._lock:
                self._info.update(finished_at=time.time(), current="")

    # -- public API ------------------------------------------------------------------
    def start(self, folder_url: str, category: str, retry_failed: bool, limit, user: dict,
              overrides: dict | None = None) -> None:
        cfg = self._cfg(folder_url, category, user)
        setup_logging(cfg.log_dir, cfg.log_level)   # console + logs/agent.log
        with self._lock:
            if self._thread and self._thread.is_alive():
                raise Busy("A run is already in progress.")
            self._stop.clear()
            self._log.clear()
            self._info = self._blank()
            self._info.update(state="scanning", folder=folder_url, started_at=time.time())
            self._thread = threading.Thread(target=self._work, args=(cfg, retry_failed, limit, overrides), daemon=True)
            self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())

    def status(self) -> dict:
        with self._lock:
            out = dict(self._info, log=list(self._log))
        out["running"] = self.running()
        out["queue"] = self._queue_stats()
        return out

    @staticmethod
    def _queue_stats() -> dict:
        """Read-only GROUP BY; no schema work, no lock fights with the agent thread."""
        import sqlite3
        from .models import Status
        out = {s.value: 0 for s in Status}
        try:
            path = Config.load(validate=False).state_db
            con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)
            try:
                for st, c in con.execute("SELECT status, COUNT(*) FROM jobs GROUP BY status"):
                    out[st] = c
            finally:
                con.close()
        except Exception:
            pass
        out["total"] = sum(out.values())
        return out

    def plan(self, folder_url: str, category: str, user: dict, max_rows: int = 500) -> dict:
        cfg = self._cfg(folder_url, category, user)
        cfg.validate()
        agent = Agent(cfg, store=StateStore(cfg.state_db, recover=False))
        try:
            rows = agent.plan(folder_url)
        finally:
            agent.store.close()
        return {"total": len(rows), "new": sum(r[2] == "new" for r in rows),
                "items": [{"file_id": v.file_id, "name": v.name, "title": m.title, "season": m.season,
                           "episode": m.episode, "status": st, "folder": v.folder_path,
                           "series_name": m.extra.get("series_name", ""),
                           "description": m.extra.get("description", "") or "",
                           "video_url": m.extra.get("video_url") or v.web_view_link,
                           "thumbnail_url": m.extra["thumbnail_url"] if "thumbnail_url" in m.extra else v.web_view_link}
                          for v, m, st in rows[:max_rows]]}

    # -- preview as a background job (big folders outlive any HTTP timeout) ----------------
    def plan_start(self, folder_url: str, category: str, user: dict) -> None:
        cfg = self._cfg(folder_url, category, user)
        cfg.validate()
        with self._lock:
            p = self._plan_info
            if p["state"] == "running" and time.time() - p["started"] < 600:
                raise Busy("A preview is already in progress.")
            self._plan_info = {"state": "running", "result": None, "error": "", "started": time.time()}

        def work():
            try:
                res = self.plan(folder_url, category, user)
                with self._lock:
                    self._plan_info.update(state="done", result=res)
            except Exception as e:
                with self._lock:
                    self._plan_info.update(state="error", error=str(e)[:300])
        threading.Thread(target=work, daemon=True).start()

    def plan_result(self) -> dict:
        with self._lock:
            return dict(self._plan_info)

    def forget(self, doc_ids: list[str], urls: list[str]) -> int:
        store = StateStore(Config.load(validate=False).state_db, recover=False)
        try:
            return Agent(Config.load(validate=False), store=store).forget(doc_ids, urls)
        finally:
            store.close()

    def retry_failed(self) -> int:
        if self.running():
            raise Busy("A run is in progress.")
        store = StateStore(Config.load(validate=False).state_db, recover=False)
        try:
            return store.reset_failed()
        finally:
            store.close()


manager = RunManager()
