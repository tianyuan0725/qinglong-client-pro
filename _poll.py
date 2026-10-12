import json, time, urllib.request, urllib.error, sys

TOKEN = open('_token.txt').read().strip()
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
urllib.request.install_opener(opener)

def api(path):
    req = urllib.request.Request('https://api.github.com' + path, headers={
        'Authorization': 'Bearer ' + TOKEN,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'poll',
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {'error': e.code}

# 找到刚推送的 commit 对应的 run
run_id = None
for _ in range(10):
    runs = api('/repos/tianyuan0725/qinglong-client-pro/actions/runs?per_page=3')
    for r in runs.get('workflow_runs', []):
        if r.get('head_sha', '').startswith('e9427c7c'):
            run_id = r['id']
            break
    if run_id:
        break
    time.sleep(5)
if not run_id:
    print('RUN NOT FOUND for e5f5aa6a')
    sys.exit(1)
print('run_id', run_id)

deadline = time.time() + 1500
while time.time() < deadline:
    run = api('/repos/tianyuan0725/qinglong-client-pro/actions/runs/%s' % run_id)
    st, concl = run.get('status'), run.get('conclusion')
    print('poll:', st, concl, flush=True)
    if st == 'completed':
        print('FINAL:', concl)
        jobs = api('/repos/tianyuan0725/qinglong-client-pro/actions/runs/%s/jobs' % run_id)
        for j in jobs.get('jobs', []):
            print('job:', j.get('name'), j.get('conclusion'), 'started:', j.get('started_at'), 'completed:', j.get('completed_at'))
            for s in j.get('steps', []):
                print('   step:', s.get('name'), '->', s.get('conclusion'))
        rel = api('/repos/tianyuan0725/qinglong-client-pro/releases/tags/v2.0.5')
        if 'assets' in rel:
            for a in rel['assets']:
                print('asset:', a['name'], a['size'], a['browser_download_url'])
        else:
            print('release v2.0.5 not found:', rel)
        break
    time.sleep(20)
else:
    print('TIMEOUT waiting for run')
