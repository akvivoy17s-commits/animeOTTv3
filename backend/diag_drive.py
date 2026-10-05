import sys, os, re, time, json, urllib.request, urllib.error, urllib.parse
from pathlib import Path


def load_env():
    p = Path(".env")
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def http_get(url, timeout=15):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def step(n, name, fn):
    t = time.time()
    try:
        msg, status = fn(), "OK  "
    except Exception as e:
        msg, status = f"{type(e).__name__}: {e}", "FAIL"
    print(f"[{status} {time.time()-t:5.1f}s] {n} {name} -> {msg}", flush=True)


def internet():
    code, _ = http_get("https://www.googleapis.com/generate_204")
    return f"HTTP {code}"


def certs():
    code, body = http_get(
        "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com")
    if code != 200:
        raise RuntimeError(f"HTTP {code}")
    return f"{len(json.loads(body))} certs"


def firestore():
    import firebase_admin
    from firebase_admin import credentials, firestore as fs
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "serviceAccount.json")
    if not Path(cred_path).exists():
        raise FileNotFoundError(f"{cred_path} not found")
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(cred_path))
    docs = list(fs.client().collection("users").limit(1).stream(timeout=15))
    return f"read ok ({len(docs)} doc)"


def drive(folder_url):
    ids = re.findall(r"folders/([A-Za-z0-9_-]+)", folder_url)
    if not ids:
        raise ValueError("no folder id in URL")
    key = next((os.environ[k] for k in
                ("GOOGLE_API_KEY", "DRIVE_API_KEY", "GOOGLE_DRIVE_API_KEY", "API_KEY")
                if os.environ.get(k)), None)
    if not key:
        raise RuntimeError("no API key found in .env (GOOGLE_API_KEY / DRIVE_API_KEY)")
    q = urllib.parse.quote(f"'{ids[-1]}' in parents and trashed=false")
    url = ("https://www.googleapis.com/drive/v3/files?q=" + q +
           "&fields=files(id,name,mimeType)&pageSize=1000&key=" + key)
    code, body = http_get(url)
    data = json.loads(body)
    if code != 200:
        err = data.get("error", {})
        raise RuntimeError(f"HTTP {code} {err.get('status','')} {err.get('message','')[:120]}")
    vids = [f for f in data["files"] if f["mimeType"].startswith("video/")]
    first = vids[0]["name"] if vids else "-"
    return f"files: {len(data['files'])}, videos: {len(vids)}; first: {first}"


if __name__ == "__main__":
    load_env()
    folder = sys.argv[1] if len(sys.argv) > 1 else ""
    step(1, "internet -> googleapis.com", internet)
    step(2, "Firebase token certs fetch", certs)
    step(3, "Firestore read (users)", firestore)
    step(4, "Drive folder read", lambda: drive(folder))