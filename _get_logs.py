import json, urllib.request, gzip

TOKEN = open('_token.txt').read().strip()

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect, urllib.request.ProxyHandler({}))

def get(url, auth=True):
    headers = {'User-Agent': 'monitor'}
    if auth:
        headers['Authorization'] = 'Bearer ' + TOKEN
    req = urllib.request.Request(url, headers=headers)
    try:
        resp = opener.open(req, timeout=120)
        return resp.read(), resp.headers
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            loc = e.headers.get('Location')
            return get(loc, auth=False)
        raise

raw, headers = get('https://api.github.com/repos/tianyuan0725/qinglong-client-pro/actions/jobs/114713716441/logs')
try:
    text = gzip.decompress(raw).decode('utf-8', errors='replace')
except Exception:
    text = raw.decode('utf-8', errors='replace')
open('_ci_log.txt', 'w', encoding='utf-8').write(text)
print('saved lines:', text.count(chr(10)))
