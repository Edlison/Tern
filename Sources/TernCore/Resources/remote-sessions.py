# Read-only probe. Run through SSH stdin; nothing is installed on the host.
import os, json, time, pathlib, base64
previous = json.loads(base64.b64decode('__PREVIOUS__'))
now = time.time()
files, errors, bridges = [], [], {}
claude_root = pathlib.Path(os.environ.get('CLAUDE_CONFIG_DIR', pathlib.Path.home()/'.claude'))
for path in (claude_root/'sessions').glob('*.json'):
    try:
        if path.stat().st_size > 65536: continue
        row = json.loads(path.read_bytes())
        if isinstance(row.get('sessionId'),str) and isinstance(row.get('bridgeSessionId'),str):
            bridges[row['sessionId']] = row['bridgeSessionId']
    except (OSError,ValueError): pass
def text_content(value):
    if isinstance(value, str): return value[:16000]
    if not isinstance(value, list): return []
    return [{k: b[k] for k in ('type','text') if k in b} for b in value if isinstance(b,dict) and b.get('type') in ('text','input_text','output_text','tool_result')][:24]
def slim(r, agent):
    kind = r.get('type')
    if agent == 'codex':
        p = r.get('payload') or {}
        if kind not in ('session_meta','turn_context','event_msg','response_item'): return None
        if kind == 'event_msg' and p.get('type') not in ('task_started','turn_started','task_complete','task_completed','task_aborted','turn_aborted','task_failed','turn_failed','user_message','agent_message'): return None
        if kind == 'response_item' and (p.get('type') != 'message' or p.get('role') not in ('user','assistant')): return None
        keys = ('type','id','session_id','cwd','turn_id','last_agent_message','message','role','content','text')
        out = {k: p[k] for k in keys if k in p}
        if 'content' in out: out['content'] = text_content(out['content'])
        for k in ('last_agent_message','message','text'):
            if isinstance(out.get(k),str): out[k] = out[k][:16000]
        return {'type':kind,'timestamp':r.get('timestamp'),'payload':out}
    if r.get('isSidechain') or kind not in ('user','assistant','system','custom-title','last-prompt'): return None
    if kind == 'system' and r.get('subtype') not in ('turn_duration',): return None
    out = {k:r[k] for k in ('type','subtype','sessionId','cwd','timestamp','uuid','customTitle','lastPrompt') if k in r}
    if isinstance(r.get('message'),dict):
        m = r['message']; out['message'] = {k:m[k] for k in ('id','stop_reason') if k in m}
        out['message']['content'] = text_content(m.get('content'))
    return out
for agent, root in [('codex', pathlib.Path(os.environ.get('CODEX_HOME',pathlib.Path.home()/'.codex'))/'sessions'), ('claude', pathlib.Path(os.environ.get('CLAUDE_CONFIG_DIR',pathlib.Path.home()/'.claude'))/'projects')]:
    candidates = []
    if not root.is_dir(): errors.append(agent + ':missing'); continue
    for folder, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d != 'subagents' and not d.startswith('.')]
        for name in names:
            if not name.endswith('.jsonl'): continue
            path = pathlib.Path(folder)/name
            try:
                st = path.stat()
                if st.st_mtime >= now - 7*86400: candidates.append((st.st_mtime,path,st))
            except OSError: pass
    for _,path,st in sorted(candidates,reverse=True)[:100]:
        key = str(path); version = str(st.st_ino)+':'+str(st.st_size)+':'+str(st.st_mtime_ns)
        entry = {'agent':agent,'path':key,'version':version}
        if previous.get(key) != version:
            try:
                with path.open('rb') as f:
                    if st.st_size > 4*1024*1024:
                        head = f.read(65536).split(b'\n')[:-1]
                        f.seek(-4*1024*1024,2); raw = head+f.read().split(b'\n')[1:-1]
                    else: raw = f.read(4*1024*1024).split(b'\n')[:-1]
                rows = []
                for line in raw:
                    if len(line) > 2*1024*1024: continue
                    try:
                        value = slim(json.loads(line),agent)
                        if value: rows.append(value)
                    except (ValueError,TypeError,AttributeError): pass
                # Keep metadata, first prompt, and enough recent explicit state transitions.
                if len(rows) > 103:
                    selected = set(range(3)) | set(range(len(rows)-100,len(rows)))
                    if agent == 'codex':
                        transitions = [i for i,r in enumerate(rows) if r.get('type')=='event_msg' and r.get('payload',{}).get('type') in ('task_started','turn_started','task_complete','task_completed','task_aborted','turn_aborted','task_failed','turn_failed')]
                        if transitions: selected.add(transitions[-1])
                    entry['lines'] = [rows[i] for i in sorted(selected)]
                else: entry['lines'] = rows
            except OSError: entry['error'] = 'unreadable'
        files.append(entry)
print(json.dumps({'files':files,'errors':errors,'bridges':bridges},ensure_ascii=False))
