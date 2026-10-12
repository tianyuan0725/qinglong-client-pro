# -*- coding: utf-8 -*-
"""Download CI job logs (manual redirect, no auth header on redirect target)."""
import json, urllib.request, gzip, sys

TOKEN = open("C:/Users/W10LL/WorkBuddy/2026-10-12-10-08-13/QinglongClientPro/_token.txt").read().strip()
RUN_ID = sys.argv[1] if len(sys.argv) > 1 else "38227103061"
HDRS = {"Authorization": "Bearer " + TOKEN, "Accept": "application/vnd.github+json", "User-Agent": "monitor"}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect)

def get(url, auth=True):
    h = dict(HDRS) if auth else {"User-Agent": "monitor"}
    req = urllib.request.Request(url, headers=h)
    resp = opener.open(req, timeout=180)
    return resp.read()

# find job id
data = get("https://api.github.com/repos/tianyuan0725/qinglong-client-pro/actions/runs/%s/jobs" % RUN_ID)
jobs = json.loads(data.decode())
job_id = None
for j in jobs.get("jobs", []):
    print("job", j["id"], j["name"], j["conclusion"])
    job_id = j["id"]

try:
    raw = get("https://api.github.com/repos/tianyuan0725/qinglong-client-pro/actions/jobs/%s/logs" % job_id)
except urllib.error.HTTPError as e:
    loc = e.headers.get("Location")
    print("redirect ->", (loc or "")[:80], "...")
    if not loc:
        raise
    raw = get(loc, auth=False)

try:
    text = gzip.decompress(raw).decode("utf-8", errors="replace")
except Exception:
    text = raw.decode("utf-8", errors="replace")
open("C:/Users/W10LL/WorkBuddy/2026-10-12-10-08-13/QinglongClientPro/_ci_log.txt", "w", encoding="utf-8").write(text)
print("log lines:", text.count("\n"))
