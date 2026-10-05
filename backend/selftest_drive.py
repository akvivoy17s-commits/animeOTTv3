"""Offline check of the run manager (no Drive/Firebase/HTTP): python selftest_drive.py"""
import os, tempfile, time
os.environ.update(GOOGLE_API_KEY="x", STATE_DB=os.path.join(tempfile.mkdtemp(), "s.db"), DELAY_SECONDS="0")
from drive_agent.agent import Agent
from drive_agent.models import DriveVideo
from drive_agent.service import Busy, RunManager
from drive_agent.uploader import Uploader

class R:
    def read_folder(self, url=None):
        return [DriveVideo(file_id=f"f{i}", name=f"Show.S01E{i:02}.mp4", web_view_link=f"https://drive.google.com/file/d/f{i}/view") for i in range(1, 6)]
class U(Uploader):
    def upload(self, job): time.sleep(0.05); return "doc-" + job.file_id

m = RunManager(lambda cfg, ev, stop: Agent(cfg, R(), U(), on_event=ev, should_stop=stop))
user = {"uid": "u1", "email": "a@b.c"}
F = "https://drive.google.com/drive/folders/ABCDEFGHIJKLMNOP"
m.start(F, "series", False, None, user)
try: m.start(F, "series", False, None, user)
except Busy as e: print("2nd start ->", e)
while m.running(): time.sleep(0.05)
s = m.status(); print(s["state"], s["found"], s["done"], s["failed"], s["queue"]["done"]); print(*s["log"][:3], sep="\n")
m.start(F, "series", False, None, user); print("rerun new videos:", [x for x in [m.status()["new"]]]); 
while m.running(): time.sleep(0.05)
print("after rerun:", m.status()["queue"])
