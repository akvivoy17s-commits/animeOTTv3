"""Google Drive reader: folder URL -> list[DriveVideo]. Metadata only, never downloads."""
from __future__ import annotations
import re
import time
from typing import Iterator

from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from .config import Config
from .log import get
from .models import DriveVideo

log = get("drive")

FOLDER_MIME = "application/vnd.google-apps.folder"
VIDEO_EXT = (".mp4", ".mkv", ".avi", ".mov", ".webm", ".m4v", ".flv", ".wmv", ".ts", ".3gp")
FIELDS = ("nextPageToken, files(id,name,mimeType,size,description,createdTime,"
          "modifiedTime,videoMediaMetadata(durationMillis))")
_ID_PATTERNS = (r"/folders/([\w-]{10,})", r"[?&]id=([\w-]{10,})", r"^([\w-]{20,})$")


def extract_folder_id(url: str) -> str:
    url = url.strip()
    for p in _ID_PATTERNS:
        m = re.search(p, url)
        if m:
            return m.group(1)
    raise ValueError(f"Cannot find a Drive folder id in: {url}")


def file_url(file_id: str) -> str:
    return f"https://drive.google.com/file/d/{file_id}/view"


def is_video(f: dict) -> bool:
    return f.get("mimeType", "").startswith("video/") or f.get("name", "").lower().endswith(VIDEO_EXT)


class DriveReader:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        if cfg.google_sa_file:
            from google.oauth2 import service_account
            creds = service_account.Credentials.from_service_account_file(
                cfg.google_sa_file, scopes=["https://www.googleapis.com/auth/drive.readonly"])
            self.svc = build("drive", "v3", credentials=creds, cache_discovery=False)
        else:
            self.svc = build("drive", "v3", developerKey=cfg.google_api_key, cache_discovery=False)

    # -- low level ---------------------------------------------------------
    def _execute(self, req):
        for attempt in range(1, self.cfg.max_retries + 1):
            try:
                return req.execute()
            except HttpError as e:
                code = e.resp.status
                if code in (429, 500, 502, 503, 504) and attempt < self.cfg.max_retries:
                    wait = 2 ** attempt
                    log.warning("Drive HTTP %s, retry %d in %ss", code, attempt, wait)
                    time.sleep(wait)
                    continue
                if code in (403, 404):
                    raise RuntimeError(
                        f"Drive HTTP {code}: folder not accessible. Make it 'Anyone with the link' "
                        f"(API key) or share it with the service-account email.") from e
                raise

    def _list(self, folder_id: str) -> Iterator[dict]:
        token = None
        while True:
            req = self.svc.files().list(
                q=f"'{folder_id}' in parents and trashed=false",
                fields=FIELDS, pageSize=1000, pageToken=token,
                supportsAllDrives=True, includeItemsFromAllDrives=True)
            data = self._execute(req)
            yield from data.get("files", [])
            token = data.get("nextPageToken")
            if not token:
                break

    # -- public ------------------------------------------------------------
    def read_folder(self, folder_url: str | None = None) -> list[DriveVideo]:
        root = extract_folder_id(folder_url or self.cfg.drive_folder_url)
        videos: list[DriveVideo] = []
        stack = [(root, "")]
        while stack:
            fid, path = stack.pop()
            for f in self._list(fid):
                if f["mimeType"] == FOLDER_MIME:
                    if self.cfg.recursive:
                        stack.append((f["id"], f"{path}/{f['name']}".strip("/")))
                elif is_video(f):
                    videos.append(DriveVideo(
                        file_id=f["id"], name=f["name"], mime_type=f.get("mimeType", ""),
                        size=int(f["size"]) if f.get("size") else None,
                        duration_ms=int(f.get("videoMediaMetadata", {}).get("durationMillis", 0)) or None,
                        description=f.get("description", ""), folder_path=path,
                        web_view_link=file_url(f["id"]),
                        created_time=f.get("createdTime", ""), modified_time=f.get("modifiedTime", "")))
            log.debug("scanned folder %s (%s) total videos=%d", fid, path or "root", len(videos))
        videos.sort(key=lambda v: _natural_key(f"{v.folder_path}/{v.name}"))
        log.info("Found %d video(s)", len(videos))
        return videos


def _natural_key(s: str):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]
