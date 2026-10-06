"""Admin-only REST API:  /drive/plan  /drive/start  /drive/stop  /drive/status  /drive/retry-failed  /drive/forget"""
from typing import Literal, Optional
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from .auth import require_admin
from .service import Busy, manager

router = APIRouter(prefix="/drive", tags=["drive-agent"])


class FolderReq(BaseModel):
    folder_url: str = Field(min_length=10, max_length=500)
    category: Literal["series", "movies"] = "series"


class ItemEdit(BaseModel):
    """Admin edits for one collected video. Omitted fields keep the auto-parsed value."""
    title: Optional[str] = Field(default=None, max_length=300)
    season: Optional[int] = Field(default=None, ge=0, le=99)
    episode: Optional[int] = Field(default=None, ge=0, le=9999)
    series_name: Optional[str] = Field(default=None, max_length=300)
    description: Optional[str] = Field(default=None, max_length=5000)
    video_url: Optional[str] = Field(default=None, max_length=2000)
    thumbnail_url: Optional[str] = Field(default=None, max_length=2000)

    @field_validator("video_url", "thumbnail_url")
    @classmethod
    def _http(cls, v):
        if v and urlparse(v.strip()).scheme not in ("http", "https"):
            raise ValueError("URL must start with http:// or https://")
        return v

    @field_validator("video_url")
    @classmethod
    def _video_required(cls, v):
        if v is not None and not v.strip():
            raise ValueError("video URL cannot be empty")
        return v


class StartReq(FolderReq):
    retry_failed: bool = False
    limit: Optional[int] = Field(default=None, ge=1, le=5000)
    edits: dict[str, ItemEdit] = Field(default_factory=dict, max_length=5000)   # file_id -> edits


class ForgetReq(BaseModel):
    video_ids: list[str] = Field(default_factory=list, max_length=500)   # Firestore videos/{id}
    urls: list[str] = Field(default_factory=list, max_length=500)        # videoUrl / originalVideoUrl


def _bad(e: Exception):
    raise HTTPException(400, str(e)[:300])


@router.post("/plan")
def plan(req: FolderReq, user: dict = Depends(require_admin)):
    try:
        return manager.plan(req.folder_url, req.category, user)
    except (ValueError, RuntimeError) as e:
        _bad(e)


@router.post("/plan/start")
def plan_start(req: FolderReq, user: dict = Depends(require_admin)):
    try:
        manager.plan_start(req.folder_url, req.category, user)
    except Busy as e:
        raise HTTPException(409, str(e))
    except (ValueError, RuntimeError) as e:
        _bad(e)
    return {"ok": True}


@router.get("/plan/result")
def plan_result(_: dict = Depends(require_admin)):
    r = manager.plan_result()
    return {"state": r["state"], "error": r["error"], "result": r["result"] if r["state"] == "done" else None}


@router.post("/start")
def start(req: StartReq, user: dict = Depends(require_admin)):
    try:
        edits = {k: v.model_dump(exclude_none=True) for k, v in req.edits.items()}
        manager.start(req.folder_url, req.category, req.retry_failed, req.limit, user, edits)
    except Busy as e:
        raise HTTPException(409, str(e))
    except ValueError as e:
        _bad(e)
    return {"ok": True}


@router.post("/stop")
def stop(_: dict = Depends(require_admin)):
    manager.stop()
    return {"ok": True}


@router.get("/status")
def status(_: dict = Depends(require_admin)):
    return manager.status()


@router.post("/forget")
def forget(req: ForgetReq, _: dict = Depends(require_admin)):
    """Call after videos are deleted in the app: wipes their dedupe records so they show as new."""
    return {"forgotten": manager.forget(req.video_ids, req.urls)}


@router.post("/retry-failed")
def retry_failed(_: dict = Depends(require_admin)):
    try:
        return {"reset": manager.retry_failed()}
    except Busy as e:
        raise HTTPException(409, str(e))
