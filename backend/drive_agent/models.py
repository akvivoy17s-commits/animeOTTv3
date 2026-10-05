"""Plain data models shared by every module."""
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class Status(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    DONE = "done"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class DriveVideo:
    """Raw info from Drive (no parsing yet)."""
    file_id: str
    name: str
    mime_type: str = ""
    size: Optional[int] = None
    duration_ms: Optional[int] = None
    description: str = ""
    folder_path: str = ""          # e.g. "One Piece/Season 2"
    web_view_link: str = ""        # shareable URL
    created_time: str = ""
    modified_time: str = ""


@dataclass
class VideoMeta:
    """Parsed result, ready for upload. Mirrors the app's Firestore 'videos' doc."""
    title: str
    season: int = 0                # 0 => app omits the field
    episode: int = 0               # 0 => app omits the field
    category: str = "series"
    extra: dict = field(default_factory=dict)   # series name, quality, description...


@dataclass
class Job:
    """One unit of work tracked in the state DB."""
    file_id: str
    video: DriveVideo
    meta: Optional[VideoMeta] = None
    status: Status = Status.PENDING
    attempts: int = 0
    error: str = ""
    doc_id: str = ""               # Firestore doc id after upload
    override: dict = field(default_factory=dict)   # admin edits made before upload
