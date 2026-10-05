# """Uploader layer. Firestore mode writes the exact document the app's Upload-by-URL page writes."""
# from __future__ import annotations
# import re
# from abc import ABC, abstractmethod
# from urllib.parse import parse_qs, urlparse

# from .config import Config
# from .log import get
# from .models import Job

# log = get("upload")


# class UploadError(Exception):
#     pass


# # ---- ports of the Dart helpers in lib/pages/upload_vidurl.dart --------------------------
# def extract_drive_id(url: str) -> str | None:
#     u = urlparse(url.strip())
#     if "drive.google.com" not in u.netloc.lower():
#         return None
#     m = re.search(r"/file/d/([^/?#]+)", u.path)
#     if m:
#         return m.group(1).strip()
#     q = parse_qs(u.query).get("id")
#     return q[0].strip() if q and q[0].strip() else None


# def _is_http(url: str) -> bool:
#     return urlparse(url).scheme in ("http", "https")


# def convert_video_url(url: str) -> str | None:
#     url = url.strip()
#     fid = extract_drive_id(url)
#     if fid:
#         return f"https://drive.google.com/uc?export=download&id={fid}"
#     return url if _is_http(url) else None


# def convert_thumbnail_url(url: str) -> str | None:
#     url = url.strip()
#     if not url:
#         return ""
#     fid = extract_drive_id(url)
#     if fid:
#         return f"https://drive.google.com/thumbnail?id={fid}&sz=w800"
#     return url if _is_http(url) else None


# def doc_id_for(file_id: str) -> str:
#     """Deterministic id => a crash+resume can never create a duplicate document."""
#     return f"drive_{file_id}"


# def build_payload(job: Job, cfg: Config) -> dict:
#     """Same fields as the app. SERVER_TIMESTAMP is added by the uploader."""
#     meta, video = job.meta, job.video
#     if meta is None or not meta.title.strip():
#         raise UploadError("missing title/metadata")
#     x = meta.extra
#     original = x.get("video_url") or video.web_view_link          # Drive URL unless the admin edited it
#     original_thumb = x["thumbnail_url"] if "thumbnail_url" in x else video.web_view_link
#     video_url = convert_video_url(original)
#     thumb_url = convert_thumbnail_url(original_thumb)
#     if not video_url:
#         raise UploadError(f"invalid video URL: {original}")
#     if thumb_url is None:
#         raise UploadError(f"invalid thumbnail URL: {original_thumb}")
#     data = {
#         "title": meta.title.strip(), "category": meta.category,
#         "videoUrl": video_url, "thumbnailUrl": thumb_url,
#         "originalVideoUrl": original, "originalThumbnailUrl": original_thumb,
#         "uploadType": "url", "uploadedBy": cfg.uploaded_by_email, "uploadedByUid": cfg.uploaded_by_uid,
#     }
#     if meta.episode > 0:
#         data["episodes"] = meta.episode               # app omits when 0
#     if meta.season > 0:
#         data["season"] = meta.season
#     desc = x["description"] if "description" in x else video.description
#     if desc.strip():
#         data["description"] = desc.strip()                # app reads this field on some pages
#     if x.get("series_edited") and x.get("series_name", "").strip():
#         data["seriesName"] = x["series_name"].strip()
#     return data


# class Uploader(ABC):
#     @abstractmethod
#     def upload(self, job: Job) -> str:
#         """Upload one job, return an id/reference. Raise UploadError on failure."""

#     def close(self) -> None:
#         pass

#     def __enter__(self): return self
#     def __exit__(self, *a): self.close()


# class FirestoreUploader(Uploader):
#     def __init__(self, cfg: Config):
#         import firebase_admin
#         from firebase_admin import credentials, firestore
#         self._fs = firestore
#         self.cfg = cfg
#         if not firebase_admin._apps:
#             firebase_admin.initialize_app(credentials.Certificate(cfg.firebase_sa_file))
#         self.col = firestore.client().collection("videos")

#     def upload(self, job: Job) -> str:
#         from google.api_core.exceptions import AlreadyExists, GoogleAPICallError
#         data = build_payload(job, self.cfg)
#         data["createdAt"] = self._fs.SERVER_TIMESTAMP
#         data["updatedAt"] = self._fs.SERVER_TIMESTAMP
#         ref = self.col.document(doc_id_for(job.file_id))
#         try:
#             ref.create(data)                             # fails if it already exists -> no overwrite
#         except AlreadyExists:
#             log.info("Already in Firestore, treating as done: %s", ref.id)
#         except GoogleAPICallError as e:
#             raise UploadError(f"Firestore error: {e}") from e
#         return ref.id


# def make_uploader(cfg: Config) -> Uploader:
#     if cfg.upload_mode == "firestore":
#         return FirestoreUploader(cfg)
#     try:
#         from .browser import BrowserUploader          # Phase 6
#     except ImportError as e:
#         raise UploadError("browser mode not installed yet (Phase 6)") from e
#     return BrowserUploader(cfg)












"""Uploader layer. Firestore mode writes the exact document the app's Upload-by-URL page writes."""
from __future__ import annotations
import re
from abc import ABC, abstractmethod
from urllib.parse import parse_qs, urlparse

from .config import Config
from .log import get
from .models import Job

log = get("upload")


class UploadError(Exception):
    pass


# ---- ports of the Dart helpers in lib/pages/upload_vidurl.dart --------------------------
def extract_drive_id(url: str) -> str | None:
    u = urlparse(url.strip())
    if "drive.google.com" not in u.netloc.lower():
        return None
    m = re.search(r"/file/d/([^/?#]+)", u.path)
    if m:
        return m.group(1).strip()
    q = parse_qs(u.query).get("id")
    return q[0].strip() if q and q[0].strip() else None


def _is_http(url: str) -> bool:
    return urlparse(url).scheme in ("http", "https")


def convert_video_url(url: str) -> str | None:
    url = url.strip()
    fid = extract_drive_id(url)
    if fid:
        return f"https://drive.google.com/uc?export=download&id={fid}"
    return url if _is_http(url) else None


def convert_thumbnail_url(url: str) -> str | None:
    url = url.strip()
    if not url:
        return ""
    fid = extract_drive_id(url)
    if fid:
        return f"https://drive.google.com/thumbnail?id={fid}&sz=w800"
    return url if _is_http(url) else None


def doc_id_for(file_id: str) -> str:
    """Deterministic id => a crash+resume can never create a duplicate document."""
    return f"drive_{file_id}"


def build_payload(job: Job, cfg: Config) -> dict:
    """Same fields as the app. SERVER_TIMESTAMP is added by the uploader."""
    meta, video = job.meta, job.video
    if meta is None or not meta.title.strip():
        raise UploadError("missing title/metadata")
    x = meta.extra
    original = x.get("video_url") or video.web_view_link          # Drive URL unless the admin edited it
    original_thumb = x["thumbnail_url"] if "thumbnail_url" in x else video.web_view_link
    video_url = convert_video_url(original)
    thumb_url = convert_thumbnail_url(original_thumb)
    if not video_url:
        raise UploadError(f"invalid video URL: {original}")
    if thumb_url is None:
        raise UploadError(f"invalid thumbnail URL: {original_thumb}")
    data = {
        "title": meta.title.strip(), "category": meta.category,
        "videoUrl": video_url, "thumbnailUrl": thumb_url,
        "originalVideoUrl": original, "originalThumbnailUrl": original_thumb,
        "uploadType": "url", "uploadedBy": cfg.uploaded_by_email, "uploadedByUid": cfg.uploaded_by_uid,
    }
    if meta.episode > 0:
        data["episodes"] = meta.episode               # app omits when 0
    if meta.season > 0:
        data["season"] = meta.season
    desc = x["description"] if "description" in x else video.description
    if desc.strip():
        data["description"] = desc.strip()                # app reads this field on some pages
    if x.get("series_edited") and x.get("series_name", "").strip():
        data["seriesName"] = x["series_name"].strip()
    return data


class Uploader(ABC):
    @abstractmethod
    def upload(self, job: Job) -> str:
        """Upload one job, return an id/reference. Raise UploadError on failure."""

    def close(self) -> None:
        pass

    def __enter__(self): return self
    def __exit__(self, *a): self.close()


class FirestoreUploader(Uploader):
    def __init__(self, cfg: Config):
        import firebase_admin
        from firebase_admin import firestore
        from .auth import load_credentials
        self._fs = firestore
        self.cfg = cfg
        if not firebase_admin._apps:
            firebase_admin.initialize_app(load_credentials())
        self.col = firestore.client().collection("videos")

    def upload(self, job: Job) -> str:
        from google.api_core.exceptions import AlreadyExists, GoogleAPICallError
        data = build_payload(job, self.cfg)
        data["createdAt"] = self._fs.SERVER_TIMESTAMP
        data["updatedAt"] = self._fs.SERVER_TIMESTAMP
        ref = self.col.document(doc_id_for(job.file_id))
        try:
            ref.create(data)                             # fails if it already exists -> no overwrite
        except AlreadyExists:
            log.info("Already in Firestore, treating as done: %s", ref.id)
        except GoogleAPICallError as e:
            raise UploadError(f"Firestore error: {e}") from e
        return ref.id


def make_uploader(cfg: Config) -> Uploader:
    if cfg.upload_mode == "firestore":
        return FirestoreUploader(cfg)
    try:
        from .browser import BrowserUploader          # Phase 6
    except ImportError as e:
        raise UploadError("browser mode not installed yet (Phase 6)") from e
    return BrowserUploader(cfg)













