"""Browser fallback: drives the Flutter-web 'Upload Using URL' page with Playwright.

Flutter web draws on a canvas, so we first switch on its accessibility (semantics) tree;
after that, fields/buttons are real DOM nodes Playwright can find. All UI text lives in the
SELECTORS dict below, so if you rename a label in the app you only change it here.
"""
from __future__ import annotations
import re
from pathlib import Path

from .config import Config
from .log import get
from .models import Job
from .uploader import UploadError, Uploader

log = get("browser")

SELECTORS = {
    "email_label": r"email", "password_label": r"password", "login_btn": r"^login$",
    "nav_profile": r"^profile$", "open_upload": r"upload video", "open_url_method": r"upload using url",
    "title": r"video title", "episode": r"episode", "season": r"season",
    "video_url": r"video url", "thumb_url": r"thumbnail url",
    "cat_series": r"^series$", "cat_movies": r"^movies$", "save_btn": r"save video",
    "ok_text": r"video saved successfully", "fail_text": r"failed to save video|only admin|please enter|is required",
}
# Position of inputs on the form (fallback when labels are not exposed): title, episode, season, video, thumb
FORM_ORDER = ("title", "episode", "season", "video_url", "thumb_url")


class BrowserUploader(Uploader):
    def __init__(self, cfg: Config, dry_run: bool = False):
        from playwright.sync_api import sync_playwright
        self.cfg, self.dry_run = cfg, dry_run
        self._pw = sync_playwright().start()
        self.browser = self._pw.chromium.launch(headless=cfg.headless)
        self.page = self.browser.new_context(viewport={"width": 1280, "height": 900}).new_page()
        self.page.set_default_timeout(15000)
        self.shots = Path(cfg.log_dir) / "shots"
        self.shots.mkdir(parents=True, exist_ok=True)
        self._ready = False

    # -- helpers ---------------------------------------------------------------
    def _rx(self, key: str) -> re.Pattern:
        return re.compile(SELECTORS[key], re.I)

    def _enable_semantics(self) -> None:
        try:
            self.page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
        except Exception:
            pass
        self.page.wait_for_timeout(800)

    def _click(self, key: str) -> None:
        rx = self._rx(key)
        for loc in (self.page.get_by_role("button", name=rx), self.page.get_by_role("link", name=rx),
                    self.page.get_by_text(rx)):
            if loc.count():
                loc.first.click()
                self.page.wait_for_timeout(600)
                return
        raise UploadError(f"UI element not found: {SELECTORS[key]!r}")

    def _inputs(self):
        return self.page.locator("input:visible, textarea:visible")

    def _type(self, label_key: str, index: int, value: str) -> None:
        loc = self.page.get_by_label(self._rx(label_key))
        loc = loc.first if loc.count() else self._inputs().nth(index)
        loc.click()
        self.page.keyboard.press("Control+A")
        self.page.keyboard.type(value, delay=4)

    def _shot(self, name: str) -> None:
        try:
            self.page.screenshot(path=str(self.shots / f"{re.sub(r'[^A-Za-z0-9_-]', '_', name)}.png"))
        except Exception:
            pass

    # -- navigation --------------------------------------------------------------
    def _login_and_open_form(self) -> None:
        c = self.cfg
        self.page.goto(c.app_url, wait_until="load")
        self.page.wait_for_timeout(3000)
        self._enable_semantics()
        if self.page.get_by_text(self._rx("login_btn")).count() or self.page.get_by_role("button", name=self._rx("login_btn")).count():
            log.info("Logging in as %s", c.app_email)
            self._type("email_label", 0, c.app_email)
            self._type("password_label", 1, c.app_password)
            self._click("login_btn")
            self.page.wait_for_timeout(4000)
            self._enable_semantics()
        self._click("nav_profile")
        self._click("open_upload")
        self._click("open_url_method")
        self.page.get_by_text(self._rx("save_btn")).first.wait_for()
        self._ready = True
        log.info("Upload-by-URL form is open")

    def _ensure_form(self) -> None:
        if self._ready and self.page.get_by_text(self._rx("save_btn")).count():
            return
        self._ready = False
        self._login_and_open_form()

    # -- main --------------------------------------------------------------------
    def upload(self, job: Job) -> str:
        m, v = job.meta, job.video
        if m is None or not m.title.strip():
            raise UploadError("missing title/metadata")
        try:
            self._ensure_form()
            self._type("title", 0, m.title)
            self._type("episode", 1, str(m.episode))       # form requires a number; 0 => app omits it
            self._type("season", 2, str(m.season))
            self._type("video_url", 3, v.web_view_link)
            self._type("thumb_url", 4, v.web_view_link)     # same Drive URL, as requested
            self._click("cat_movies" if m.category == "movies" else "cat_series")
            if self.dry_run:
                self._shot(f"dryrun_{job.file_id}")
                log.info("DRY RUN: form filled, not saved (screenshot in %s)", self.shots)
                return f"dryrun:{job.file_id}"
            self._click("save_btn")
            ok, bad = self._rx("ok_text"), self._rx("fail_text")
            for _ in range(40):                              # ~20s
                if self.page.get_by_text(ok).count():
                    self.page.wait_for_timeout(500)
                    return f"browser:{job.file_id}"
                if self.page.get_by_text(bad).count():
                    raise UploadError(self.page.get_by_text(bad).first.inner_text()[:200])
                self.page.wait_for_timeout(500)
            raise UploadError("no success message after save")
        except Exception as e:
            self._shot(f"fail_{job.file_id}")
            self._ready = False                              # force re-navigation next time
            if isinstance(e, UploadError):
                raise
            raise UploadError(f"browser error: {e}") from e

    def close(self) -> None:
        try:
            self.browser.close()
            self._pw.stop()
        except Exception:
            pass
