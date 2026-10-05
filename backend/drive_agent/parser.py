"""Metadata parser: DriveVideo -> VideoMeta. Pure functions, no I/O, no dependencies."""
from __future__ import annotations
import re

from .models import DriveVideo, VideoMeta

_EXT = re.compile(r"\.(mp4|mkv|avi|mov|webm|m4v|flv|wmv|ts|3gp)$", re.I)
_NOISE = re.compile(
    r"[\[\(]?\b(?:\d{3,4}p|4k|uhd|hdr10?|hevc|[xh]\.?26[45]|av1|web-?dl|web-?rip|blu-?ray|"
    r"bdrip|brrip|hdrip|dvdrip|hdtv|aac(?:\d\.\d)?|ac3|dd5\.?1|ddp\d?\.?\d?|atmos|10bit|8bit|"
    r"amzn|nf|esubs?|msubs?)\b[\]\)]?", re.I)
_SE_COMBO = re.compile(r"\bS(\d{1,2})[\s._-]*E(?:P)?[\s._-]*(\d{1,4})\b", re.I)
_X_COMBO = re.compile(r"\b(\d{1,2})x(\d{1,3})\b", re.I)
_SEASON_EP = re.compile(r"\b(?:Season|Series)[\s._-]*(\d{1,2})\b.{0,15}?\b(?:Episode|Ep)\.?[\s._-]*(\d{1,4})\b", re.I)
_EP_ONLY = re.compile(r"\b(?:Episode|Ep|E)\.?[\s._-]*(\d{1,4})\b", re.I)
_SEASON_ONLY = re.compile(r"\b(?:Season|Series|S)[\s._-]*(\d{1,2})\b", re.I)
_LEAD_NUM = re.compile(r"^\s*(\d{1,4})\s*[-._)\]]")
_TRAIL_NUM = re.compile(r"[\s._-](\d{1,4})$")
_YEAR = re.compile(r"\b(19\d{2}|20\d{2})\b")
_QUALITY = re.compile(r"\b(\d{3,4}p|4k)\b", re.I)


def _clean(text: str) -> str:
    text = _EXT.sub("", text)
    text = _NOISE.sub(" ", text)
    text = re.sub(r"[\[\(]\s*[\]\)]", " ", text)       # empty brackets
    text = re.sub(r"[._]+", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip(" -_[](){}")


def _find_se(stem: str):
    """Return (season|None, episode|None, marker_start|None)."""
    for rx in (_SE_COMBO, _X_COMBO, _SEASON_EP):
        m = rx.search(stem)
        if m:
            return int(m.group(1)), int(m.group(2)), m.start()
    s = e = start = None
    m = _EP_ONLY.search(stem)
    if m:
        e, start = int(m.group(1)), m.start()
    m = _SEASON_ONLY.search(stem)
    if m:
        s = int(m.group(1))
        start = m.start() if start is None else min(start, m.start())
    return s, e, start


def _folder_season(path: str):
    for seg in reversed([p for p in path.split("/") if p]):
        m = _SEASON_ONLY.fullmatch(seg.strip()) or re.search(r"\b(?:Season|Series)[\s._-]*(\d{1,2})\b", seg, re.I)
        if m:
            return int(m.group(1))
    return None


def _folder_series(path: str) -> str:
    for seg in [p for p in path.split("/") if p]:
        if not _SEASON_ONLY.fullmatch(seg.strip()) and not re.search(r"\b(?:Season|Series)[\s._-]*\d+\b", seg, re.I):
            return _clean(seg)
    return ""


def parse(video: DriveVideo, category: str = "series", default_season: int = 1) -> VideoMeta:
    stem = _EXT.sub("", video.name)
    season, episode, start = _find_se(stem)

    if category == "series" and episode is None:           # weak fallbacks, series only
        flat = _clean(stem)
        m = _LEAD_NUM.match(stem) or _TRAIL_NUM.search(flat)
        if m and not _YEAR.fullmatch(m.group(1)):
            episode = int(m.group(1))   # series name then falls back to the folder name
    if season is None:
        season = _folder_season(video.folder_path)

    cleaned = _clean(stem)
    series_name = _clean(stem[:start]) if start else ""
    if not series_name:
        series_name = _folder_series(video.folder_path)
    if series_name.lower() == cleaned.lower() or not re.search(r"[A-Za-z]", series_name):
        series_name = series_name if re.search(r"[A-Za-z]", series_name) else ""

    # Title: cleaned filename; if file has no series text (e.g. "Episode 5") prefix folder series.
    title = cleaned or _clean(video.name) or video.name
    if category == "series" and start is not None and not _clean(stem[:start]) and series_name:
        title = f"{series_name} {title}"

    if category == "movies":
        season, episode = 0, 0
    else:
        if episode is not None and season is None:
            season = default_season                          # inferred
        season, episode = season or 0, episode or 0

    year = _YEAR.search(stem)
    quality = _QUALITY.search(stem)
    confidence = "high" if (season and episode) else "medium" if episode else "low"
    return VideoMeta(
        title=title, season=season, episode=episode, category=category,
        extra={
            "series_name": series_name, "year": year.group(1) if year else "",
            "quality": quality.group(1).lower() if quality else "",
            "description": video.description, "folder": video.folder_path,
            "duration_ms": video.duration_ms, "size": video.size,
            "file_id": video.file_id, "original_name": video.name, "confidence": confidence,
        })


# keys the admin may edit before upload
EDITABLE = ("title", "season", "episode", "series_name", "description", "video_url", "thumbnail_url")


def apply_override(meta: VideoMeta, ov: dict) -> VideoMeta:
    """Overlay admin edits on the parsed metadata. Missing keys keep the parsed value."""
    if not ov:
        return meta
    if str(ov.get("title") or "").strip():
        meta.title = str(ov["title"]).strip()
    if meta.category == "series":                       # movies never carry season/episode
        for k in ("season", "episode"):
            if ov.get(k) is not None:
                setattr(meta, k, max(0, int(ov[k])))
    for k in ("series_name", "description", "video_url", "thumbnail_url"):
        if ov.get(k) is not None:                       # "" is valid (e.g. clear the thumbnail)
            meta.extra[k] = str(ov[k]).strip()
    if ov.get("series_name") is not None:
        meta.extra["series_edited"] = True              # only edited series names go to Firestore
    return meta
