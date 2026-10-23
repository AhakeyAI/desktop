#!/usr/bin/env python3
"""AhaKey Windows owner-driven workflow. Python 3.9+, no third-party dependencies.
Only writes Windows Harness records. Does not run builds/devices, edit production
sources, write reference workspaces, authenticate people or certify test truth.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile

H = '.ahakey-desktop-harness'
VERSION = '0.4.0-guarded-delivery'
CHECKS = ('machine', 'core_regression', 'special_regression', 'mock', 'real_device', 'owner_uat', 'review')
CID_RE = re.compile(r'WD-[0-9]{3,6}(?:-[a-z0-9]+)*\Z')
SKIP_DIRS = {'.git', '.agents', H, '.harness-setup', 'target', 'build', '.gradle', '.idea', '.vscode', 'node_modules', '__pycache__', 'out', 'dist'}
SIGNED_KEYS = ('id', 'title', 'revision', 'assignment', 'requirements', 'allowed_paths', 'approval_assets', 'preserved_behaviors', 'ui_mode', 'ui_note_ref', 'ui_current_refs', 'ui_preview_refs', 'mock_plan', 'checkpoints', 'delivery_scope')

class HarnessError(Exception):
    pass

def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')

def digest(data):
    return hashlib.sha256(data).hexdigest()

def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode('utf-8')

def linked(path):
    try:
        s = path.lstat()
    except FileNotFoundError:
        return False
    return path.is_symlink() or bool(getattr(s, 'st_file_attributes', 0) & 0x400)

def safe_rel(value):
    if not isinstance(value, str) or not value.strip():
        raise HarnessError('Expected nonempty relative path')
    value = value.replace('\\', '/')
    p = PurePosixPath(value)
    if p.is_absolute() or ':' in value or any(x in ('..', '.', '') for x in value.split('/')):
        raise HarnessError('Unsafe relative path: ' + value)
    return p

def child(root, rel):
    parts = safe_rel(str(rel)).parts
    cur = root
    for part in parts:
        cur = cur / part
        if linked(cur):
            raise HarnessError('Linked/reparse path refused: ' + str(cur))
    if not cur.resolve().is_relative_to(root.resolve()):
        raise HarnessError('Path escapes root: ' + str(cur))
    return cur

def read_json(path):
    try:
        v = json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError) as e:
        raise HarnessError('Cannot read JSON ' + str(path) + ': ' + str(e)) from e
    if not isinstance(v, dict):
        raise HarnessError('JSON must be an object: ' + str(path))
    return v

def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.tmp-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def write_json(path, obj):
    atomic(path, (json.dumps(obj, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))

@contextmanager
def lock(root):
    path = child(root, H + '/.write.lock')
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise HarnessError('Writer lock exists; stop writers and inspect before manually clearing a stale lock')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write('pid=%s utc=%s\n' % (os.getpid(), now()))
        yield
    finally:
        path.unlink(missing_ok=True)

def state(root):
    s = read_json(child(root, H + '/STATE.json'))
    if s.get('schema_version') != 4 or s.get('harness_version') != VERSION:
        raise HarnessError('Run the v0.4 upgrader; do not edit schema/version fields to bypass migration')
    if not isinstance(s.get('baseline'), dict):
        raise HarnessError('Missing preserved baseline object')
    return s

def save_state(root, s):
    s['revision'] = s.get('revision', 0) + 1
    s['updated_at'] = now()
    write_json(child(root, H + '/STATE.json'), s)

def wait_state(s):
    s.update(phase='CONTRACT', mode='WAIT_OWNER_TASK', status='awaiting_owner_task', active_change=None,
             current_assignment=None, next_actor='Owner', next_mode='ASSIGN_TASK', current_investigation=None)
    s['owner_action'] = {'required': False, 'action': '等待 Owner 按固件进度指派；不要求现在选择候选，不自动开工。'}
    s['test_action'] = {'required': False, 'reason': '没有当前测试任务；不运行构建或设备操作。'}

def require_id(cid):
    if not isinstance(cid, str) or not CID_RE.fullmatch(cid):
        raise HarnessError('ID must be WD-001 (3-6 digits, optional lowercase suffix)')
    return cid

def cp(root, cid, name):
    return child(root, H + '/changes/' + require_id(cid) + '/' + str(safe_rel(name)))

def change(root, cid, legacy=False):
    c = read_json(cp(root, cid, 'change.json'))
    if c.get('id') != cid or c.get('schema_version') not in ((1, 2) if legacy else (2,)):
        raise HarnessError('Legacy or malformed change; retain history and create an explicitly dispatched v0.3 task: ' + cid)
    return c

def save_change(root, c):
    write_json(cp(root, c['id'], 'change.json'), c)

def ev_hash(root, rel):
    p = child(root, rel)
    if not p.is_file() or p.stat().st_size == 0:
        raise HarnessError('Missing/empty evidence: ' + str(rel))
    return digest(p.read_bytes())

def git_info(root):
    if not shutil.which('git'):
        return {'available': False}
    result = {'available': True}
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    for k, args in [('root', ['rev-parse', '--show-toplevel']), ('head', ['rev-parse', 'HEAD']), ('dirty', ['status', '--short', '--untracked-files=normal'])]:
        try:
            p = subprocess.run(['git', '-c', 'core.fsmonitor=false', '--no-optional-locks', '-C', str(root)] + args,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace', env=env, timeout=10)
            result[k] = p.stdout.strip() if p.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            result[k] = None
    return result

def source_fingerprint(root):
    """All regular project files including resources; explicit exclusions below.
    Not a build reproducibility proof. Refuses symlink/reparse production paths.
    """
    files = {}
    for base, dirs, names in os.walk(root, followlinks=False):
        b = Path(base)
        keep = []
        for name in dirs:
            if name in SKIP_DIRS or name.startswith('AhaKey-Windows-Desktop-Harness-v'):
                continue
            p = b / name
            if linked(p):
                raise HarnessError('Production fingerprint refuses link: ' + str(p))
            keep.append(name)
        dirs[:] = keep
        for name in sorted(names):
            p = b / name
            if name in ('AGENTS.md', 'AGENTS.override.md', '.gitignore') or name.startswith('AhaKey-Windows-'):
                continue
            if linked(p):
                raise HarnessError('Production fingerprint refuses link: ' + str(p))
            if not p.is_file():
                continue
            h = hashlib.sha256()
            with p.open('rb') as f:
                for block in iter(lambda: f.read(1024 * 1024), b''):
                    h.update(block)
            files[p.relative_to(root).as_posix()] = h.hexdigest()
    return {'sha256': digest(canonical(files)), 'files': files,
            'coverage': 'Regular project files/resources; excludes Git, Harness/agents, IDE, build outputs, dependencies and named Harness distributions. Not a semantic or binary reproducibility proof.'}

def external_root(root, workspace):
    if workspace not in ('source', 'firmware'):
        raise HarnessError('Reference workspace must be source or firmware')
    local = read_json(child(root, H + '/local.json'))
    value = local.get(workspace + '_root')
    if not isinstance(value, str) or not value.strip():
        raise HarnessError('Reference not bound: ' + workspace)
    raw = Path(value).expanduser()
    if linked(raw):
        raise HarnessError('Reference root is a link/reparse point: ' + value)
    ref = raw.resolve()
    if not ref.is_dir() or ref.is_relative_to(root) or root.is_relative_to(ref):
        raise HarnessError('Reference missing or overlaps receiver: ' + value)
    return ref

def reference_inputs(root, c):
    r = read_json(cp(root, c['id'], 'REFERENCES.json'))
    refs = r.get('sources')
    if not isinstance(refs, list):
        raise HarnessError('REFERENCES.sources must be a list')
    ids = set()
    agreed_protocol = False
    for x in refs:
        if not isinstance(x, dict) or not all(x.get(k) for k in ('id', 'workspace', 'path', 'sha256', 'revision_or_commit', 'section', 'kind', 'maturity')):
            raise HarnessError('Incomplete reference; record version/HEAD AND observed file SHA-256')
        if x['id'] in ids:
            raise HarnessError('Duplicate reference id')
        ids.add(x['id'])
        if not re.fullmatch(r'[0-9a-f]{64}', x['sha256']):
            raise HarnessError('Invalid reference SHA-256')
        p = child(external_root(root, x['workspace']), x['path'])
        if not p.is_file() or digest(p.read_bytes()) != x['sha256']:
            raise HarnessError('Pinned reference changed/missing: ' + x['id'] + '; DLA reconcile before using old approval')
        if x['workspace'] == 'firmware' and x['kind'] == 'protocol' and x['maturity'] in ('agreed', 'implemented', 'verified', 'released'):
            agreed_protocol = True
    if c['requirements']['device_related'] and not agreed_protocol:
        raise HarnessError('Device task needs an agreed Firmware-side protocol reference, not only eternal constants/fixtures')
    return refs

def contract_inputs(root, c):
    req = c.get('requirements')
    keys = ('ui_entry_changed', 'device_related', 'real_device', 'owner_uat')
    if not isinstance(req, dict) or any(type(req.get(k)) is not bool for k in keys):
        raise HarnessError('Four explicit requirement booleans required')
    if req['device_related'] and (not req['real_device'] or not req['owner_uat']):
        raise HarnessError('Cross-device task closure requires real-device evidence and Owner UAT; mock only remains incomplete')
    if c.get('delivery_scope') != 'internal_integration':
        raise HarnessError('This version authorizes internal integration only; release/UI overhaul needs a separate Owner task/policy')
    assignment = c.get('assignment', {})
    if assignment.get('record_sha256') != ev_hash(root, assignment.get('owner_record')):
        raise HarnessError('Owner dispatch missing or changed')
    if type(c.get('revision')) is not int or c['revision'] < 1:
        raise HarnessError('Invalid Contract revision')
    if not isinstance(c.get('preserved_behaviors'), list) or not c['preserved_behaviors'] or any(not isinstance(x, str) or not x.strip() for x in c['preserved_behaviors']):
        raise HarnessError('List this task\'s protected existing behaviors; do not require full global baseline approval')
    paths = c.get('allowed_paths')
    if not isinstance(paths, list) or not paths:
        raise HarnessError('Concrete minimal implementation paths required')
    for rel in paths:
        p = safe_rel(rel)
        if p.parts[0] in (H, '.agents', '.git', '.harness-setup', 'AGENTS.md', 'AGENTS.override.md', '.gitignore') or p.parts[0].startswith('AhaKey-Windows-'):
            raise HarnessError('Implementation scope cannot grant governance, Git or installer writes')
        child(root, rel)
    assets = c.get('approval_assets')
    if not isinstance(assets, list) or not {'CONTRACT.md', 'REFERENCES.json'}.issubset(assets):
        raise HarnessError('Approval assets must include CONTRACT.md and REFERENCES.json')
    mode = c.get('ui_mode')
    if mode not in ('none', 'existing', 'minimal', 'formal'):
        raise HarnessError('ui_mode must be none/existing/minimal/formal')
    if req['ui_entry_changed'] != (mode in ('minimal', 'formal')):
        raise HarnessError('Visible entry changes must be declared minimal/formal, not hidden as unchanged')
    if mode in ('existing', 'minimal', 'formal') and c.get('ui_note_ref') not in assets:
        raise HarnessError('UI operation/location/feedback/basis note must be included in approved assets')
    if mode == 'formal':
        for key in ('ui_current_refs', 'ui_preview_refs'):
            if not c.get(key) or not set(c[key]).issubset(assets):
                raise HarnessError('Formal UI redesign requires current UI basis and layout preview in approval assets')
    hashes = {rel: digest(cp(root, c['id'], rel).read_bytes()) for rel in assets}
    if any(cp(root, c['id'], rel).stat().st_size == 0 for rel in assets):
        raise HarnessError('Empty Contract asset')
    refs = reference_inputs(root, c)
    return {'meta_sha256': digest(canonical({k: c.get(k) for k in SIGNED_KEYS})), 'assets': hashes, 'reference_sha256': digest(canonical(refs))}

def approval_ok(root, c):
    a = c.get('approval')
    if not isinstance(a, dict):
        raise HarnessError('No Owner-approved Contract: ' + c['id'])
    if a.get('inputs') != contract_inputs(root, c):
        raise HarnessError('Contract/scope/reference/dispatch changed; DLA reconcile and obtain needed approval')
    if a.get('owner_record_sha256') != ev_hash(root, a.get('owner_record')):
        raise HarnessError('Owner approval evidence changed')
    return digest(canonical(a))

def all_changes(root):
    base = child(root, H + '/changes')
    result = []
    if not base.exists():
        return result
    for p in sorted(base.iterdir()):
        if linked(p):
            raise HarnessError('Linked change folder refused')
        if p.is_dir() and (p / 'change.json').is_file():
            result.append(change(root, p.name, legacy=True))
    return result

def check_state(root, s, verify_approval=True):
    if s.get('phase') not in ('CONTRACT', 'BUILD_VERIFY', 'BASELINE_ADOPT'):
        raise HarnessError('Unsupported global phase')
    items = all_changes(root)
    active = [c for c in items if c.get('status') == 'ACTIVE']
    if len(active) > 1 or (active[0]['id'] if active else None) != s.get('active_change'):
        raise HarnessError('Single-active invariant violated; do not reset records')
    if active:
        c = change(root, active[0]['id'])
        if s['phase'] != 'BUILD_VERIFY' or c['phase'] != 'BUILD_VERIFY' or s.get('current_assignment') != c['id']:
            raise HarnessError('Active phase/assignment mismatch')
        if verify_approval:
            approval_ok(root, c)
    elif s.get('current_assignment'):
        c = change(root, s['current_assignment'])
        if c.get('status') != 'DRAFT':
            raise HarnessError('Idle assignment must be a dispatched DRAFT')
    elif s.get('mode') not in ('WAIT_OWNER_TASK', 'INVESTIGATE'):
        raise HarnessError('No assigned/active task: use WAIT_OWNER_TASK or explicitly authorized INVESTIGATE')
    if s.get('mode') == 'INVESTIGATE':
        i = s.get('current_investigation') or {}
        if i.get('record_sha256') != ev_hash(root, i.get('owner_record')):
            raise HarnessError('Read-only investigation requires an actual Owner instruction record')
    return items

def require_active(root, s, cid):
    check_state(root, s)
    if s.get('active_change') != cid:
        raise HarnessError('Not active: ' + cid)
    c = change(root, cid)
    approval_ok(root, c)
    return c

def scope_diff(root, c):
    start = read_json(cp(root, c['id'], 'start-fingerprint.json'))['files']
    current = source_fingerprint(root)
    changed = [x for x in sorted(set(start) | set(current['files'])) if start.get(x) != current['files'].get(x)]
    allowed = [str(safe_rel(x)).rstrip('/') for x in c['allowed_paths']]
    bad = [x for x in changed if not any(x == a or x.startswith(a + '/') for a in allowed)]
    if bad:
        raise HarnessError('Out-of-scope production changes since activation: ' + ', '.join(bad[:20]))
    return current

def submission_ok(root, c):
    sub = read_json(cp(root, c['id'], 'builder_submission.json'))
    current = scope_diff(root, c)
    if sub.get('build_round') != c['build_round'] or sub.get('code_fingerprint') != current['sha256'] or sub.get('approval_sha256') != approval_ok(root, c):
        raise HarnessError('Submission absent/stale for current code/round/Contract')
    if sub.get('report_sha256') != digest(cp(root, c['id'], 'EXECUTION_REPORT.md').read_bytes()):
        raise HarnessError('Execution report changed after submission')
    return sub

def packet_ok(root, c):
    packet = read_json(cp(root, c['id'], 'test_packet.json'))
    sub = submission_ok(root, c)
    if packet.get('code_fingerprint') != sub['code_fingerprint'] or packet.get('build_round') != c['build_round'] or packet.get('approval_sha256') != approval_ok(root, c):
        raise HarnessError('Test packet stale: code/round/approval changed')
    for k in ('windows_artifact', 'brief'):
        x = packet.get(k, {})
        if x.get('sha256') != ev_hash(root, x.get('path')):
            raise HarnessError('Test packet input changed: ' + k)
    if c['requirements']['device_related']:
        x = packet.get('firmware_identity', {})
        if x.get('sha256') != ev_hash(root, x.get('path')):
            raise HarnessError('Missing/changed Firmware identity record')
    return digest(canonical(packet))

def check_verification(root, c, name):
    v = read_json(cp(root, c['id'], 'verification.json'))
    rec = v.get('checks', {}).get(name, {})
    if rec.get('status') not in ('pass', 'not_applicable'):
        raise HarnessError('Pending/failed check: ' + name)
    required = name in ('machine', 'review') or (name == 'real_device' and c['requirements']['real_device']) or (name == 'owner_uat' and c['requirements']['owner_uat'])
    if required and rec['status'] != 'pass':
        raise HarnessError('Required check cannot be N/A: ' + name)
    if rec.get('code_fingerprint') != source_fingerprint(root)['sha256'] or rec.get('build_round') != c['build_round'] or rec.get('approval_sha256') != approval_ok(root, c):
        raise HarnessError('Stale verification: ' + name)
    if rec['status'] == 'pass':
        if not rec.get('evidence'):
            raise HarnessError('PASS requires evidence: ' + name)
        for rel, sha in rec['evidence'].items():
            if ev_hash(root, rel) != sha:
                raise HarnessError('Evidence modified: ' + rel)
    elif not rec.get('reason'):
        raise HarnessError('N/A requires reason')
    if name in ('real_device', 'owner_uat') and rec['status'] == 'pass':
        if rec.get('test_packet_sha256') != packet_ok(root, c):
            raise HarnessError('Real/Owner result does not match current test packet')
    return rec

def save_both(root, c, s):
    """Two-file rollback on write failure; lock prevents cooperating helper writers.
    Direct editor races are not fully preventable; stop other writers before changes.
    """
    p = cp(root, c['id'], 'change.json')
    old = p.read_bytes() if p.exists() else None
    try:
        save_change(root, c)
        save_state(root, s)
    except Exception:
        if old is None:
            p.unlink(missing_ok=True)
        else:
            atomic(p, old)
        raise

def status(root):
    s = state(root)
    print('AhaKey Windows / Desktop Harness ' + VERSION)
    print('Windows root:', root)
    print('Workflow: OWNER_DISPATCHED_INTEGRATION')
    print('Phase / Mode:', s['phase'], '/', s['mode'])
    print('Active change:', s.get('active_change') or 'NONE')
    print('Current assignment:', s.get('current_assignment') or 'NONE')
    print('Product baseline approved (historical; not global start gate):', s['baseline'].get('product_approved'))
    print('Next actor:', s.get('next_actor'))
    if s.get('active_change'):
        c = change(root, s['active_change'])
        p = cp(root, c['id'], 'builder_submission.json')
        if p.exists() and read_json(p).get('build_round') == c['build_round'] and s.get('next_actor') == 'DIB':
            print('Handoff: Builder submission present; DLA checks actual diff/evidence next.')
    print('Owner action:', s.get('owner_action'))
    print('Testing:', s.get('test_action'))
    localp = child(root, H + '/local.json')
    local = read_json(localp) if localp.exists() else {}
    for k in ('source', 'firmware'):
        print(k.capitalize() + ' read-only root:', local.get(k + '_root') or 'NOT_BOUND')
    print('No automatic queue, task selection, build, release or background process.')

def doctor(root):
    print('Python:', sys.version.split()[0], '|', sys.executable)
    print('Tools:', {n: shutil.which(n) for n in ('git', 'java', 'mvn')})
    print('JAVA_HOME:', os.environ.get('JAVA_HOME') or 'NOT_SET', '(not a Maven runtime verification)')
    print('Git (read only):', json.dumps(git_info(root), ensure_ascii=False))
    for name in ('ahakey-desktop-harness', 'ahakey-desktop-lead', 'ahakey-desktop-builder'):
        text = child(root, '.agents/skills/' + name + '/SKILL.md').read_text(encoding='utf-8-sig')
        if not text.startswith('---\n') or ('name: ' + name) not in text or 'description:' not in text:
            raise HarnessError('Invalid Skill metadata: ' + name)
    print('Skill metadata: PASS (does not prove this AI session loaded the files)')
    check_state(root, state(root), verify_approval=False)
    for k in ('source', 'firmware'):
        try:
            print(k + ':', external_root(root, k), '(read-only reference; no external script executed)')
        except HarnessError as e:
            print('WARNING:', str(e), '; irrelevant references do not block idle setup')
    if (root / 'AGENTS.override.md').exists():
        print('WARNING: inspect AGENTS.override.md / ancestor instructions; do not delete them')
    print('HARNESS STRUCTURE: PASS. Product/build/UI/device tests: NOT VERIFIED HERE.')

def legacy_parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', help='Default: installed script location, not terminal current directory')
    sub = p.add_subparsers(dest='cmd', required=True)
    for name in ('status', 'doctor', 'validate', 'fingerprint'):
        sub.add_parser(name)
    for name in ('bind-firmware', 'bind-source'):
        q = sub.add_parser(name); q.add_argument('--path', required=True)
    q = sub.add_parser('new', aliases=['intake']); q.add_argument('--id', required=True); q.add_argument('--title', required=True); q.add_argument('--owner-record', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('investigate'); q.add_argument('--topic', required=True); q.add_argument('--owner-record', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('wait'); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('pin-ref'); q.add_argument('--id', required=True); q.add_argument('--ref-id', required=True); q.add_argument('--workspace', choices=['source','firmware'], required=True); q.add_argument('--path', required=True); q.add_argument('--kind', choices=['protocol','implementation','decision','test'], required=True); q.add_argument('--maturity', choices=['observed','proposed','agreed','implemented','verified','released'], required=True); q.add_argument('--section', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    for name in ('approve', 'activate'):
        q = sub.add_parser(name); q.add_argument('--id', required=True); q.add_argument('--owner-record', required=True); q.add_argument('--isolation-record'); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('preflight'); q.add_argument('--id'); q.add_argument('--role', required=True, choices=['DLA','DIB'])
    q = sub.add_parser('submit'); q.add_argument('--id', required=True); q.add_argument('--role', required=True, choices=['DIB'])
    q = sub.add_parser('record-check'); q.add_argument('--id', required=True); q.add_argument('--check', required=True, choices=CHECKS); q.add_argument('--status', required=True, choices=['pass','fail','not_applicable','pending']); q.add_argument('--evidence', action='append', default=[]); q.add_argument('--reason'); q.add_argument('--role', required=True, choices=['DLA','DIB'])
    q = sub.add_parser('request-test'); q.add_argument('--id', required=True); q.add_argument('--artifact', required=True); q.add_argument('--firmware-record'); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('suspend'); q.add_argument('--id', required=True); q.add_argument('--note', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('park'); q.add_argument('--id', required=True); q.add_argument('--note', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('request-fix'); q.add_argument('--id', required=True); q.add_argument('--review-record', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('reopen-contract'); q.add_argument('--id', required=True); q.add_argument('--reason-record', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('close'); q.add_argument('--id', required=True); q.add_argument('--role', required=True, choices=['DLA'])
    q = sub.add_parser('prompt'); q.add_argument('--role', required=True, choices=['DLA','DIB']); q.add_argument('--id')
    return p

def legacy_main(argv=None):
    a = parser().parse_args(argv)
    root = Path(a.repo).expanduser().resolve() if a.repo else Path(__file__).resolve().parents[4]
    s = state(root)
    if a.cmd == 'status': status(root); return 0
    if a.cmd == 'doctor': doctor(root); return 0
    if a.cmd == 'validate':
        check_state(root, s, verify_approval=False); print('RECORD STRUCTURE: PASS; not identity authentication or test truth.'); return 0
    if a.cmd == 'fingerprint':
        print(json.dumps(source_fingerprint(root), ensure_ascii=False, indent=2)); return 0
    if a.cmd == 'preflight':
        check_state(root, s)
        if a.role == 'DIB':
            if not a.id: raise HarnessError('DIB needs active --id')
            c = require_active(root, s, a.id); scope_diff(root, c)
        print(a.role + ' PREFLIGHT: PASS; read actual assignment/scope and prior changes.'); return 0
    if a.cmd == 'prompt':
        if a.role == 'DIB':
            cid = a.id or s.get('active_change')
            if not cid: raise HarnessError('No active approved Owner task; wait for Owner, do not start M1a or a baseline gate')
            require_active(root, s, cid); filename = 'DIB_START.md'
        else:
            cid = s.get('active_change') or s.get('current_assignment') or 'NONE'
            filename = 'DLA_REVIEW.md' if s.get('active_change') else 'RESUME_DLA.md'
        text = child(root, H + '/prompts/' + filename).read_text(encoding='utf-8')
        print('Windows 工作目录：' + str(root) + '\n\n' + text.replace('{{ID}}', cid)); return 0
    with lock(root):
        s = state(root)
        if a.cmd in ('bind-source','bind-firmware'):
            raw = Path(a.path).expanduser()
            if linked(raw): raise HarnessError('Reference root is a link/reparse point')
            ref = raw.resolve()
            if not ref.is_dir() or ref.is_relative_to(root) or root.is_relative_to(ref):
                raise HarnessError('Reference missing or overlaps Windows root')
            lp = child(root, H + '/local.json'); local = read_json(lp) if lp.exists() else {}
            k = 'source' if a.cmd == 'bind-source' else 'firmware'
            old = local.get(k + '_root')
            if old and Path(old).expanduser().resolve() != ref:
                raise HarnessError('Existing binding differs; review and explicitly update local.json with Owner instruction, no silent rebind')
            local[k + '_root'] = str(ref); local[k + '_access'] = 'read_only_policy'
            write_json(lp, local); print('Bound read-only reference:', ref, '; no external writes.'); return 0
        if a.cmd == 'investigate':
            check_state(root, s)
            item = {'topic': a.topic, 'owner_record': a.owner_record, 'record_sha256': ev_hash(root,a.owner_record), 'at': now()}
            s['current_investigation'] = item
            if not s.get('active_change') and not s.get('current_assignment'):
                s.update(mode='INVESTIGATE', next_actor='DLA', next_mode='INVESTIGATE', status='owner_authorized_read_only_investigation')
            save_state(root, s); print('Investigation recorded; no feature auto-dispatch or implementation permission.'); return 0
        if a.cmd == 'wait':
            check_state(root, s)
            if s.get('active_change') or s.get('current_assignment'):
                raise HarnessError('Cannot erase assignment; suspend/park with evidence first')
            wait_state(s); save_state(root,s); print('WAIT_OWNER_TASK. No next item selected.'); return 0
        if a.cmd in ('new','intake'):
            check_state(root,s)
            if s.get('active_change') or s.get('current_assignment'):
                raise HarnessError('Existing assigned/active task; Owner must explicitly suspend/park before switching. Future analysis may be recorded separately.')
            require_id(a.id)
            if cp(root,a.id,'change.json').parent.exists(): raise HarnessError('Change directory already exists')
            osh = ev_hash(root,a.owner_record)
            if not a.title.strip(): raise HarnessError('Empty task title')
            c = {'schema_version':2,'id':a.id,'title':a.title,'revision':1,'phase':'CONTRACT','status':'DRAFT','build_round':0,
                 'assignment':{'owner_record':a.owner_record,'record_sha256':osh,'at':now()},
                 'delivery_scope':'internal_integration',
                 'requirements':{'ui_entry_changed':False,'device_related':True,'real_device':True,'owner_uat':True},
                 'allowed_paths':[],'preserved_behaviors':[],'approval_assets':['CONTRACT.md','REFERENCES.json'],
                 'ui_mode':'existing','ui_note_ref':'CONTRACT.md','ui_current_refs':[],'ui_preview_refs':[],
                 'mock_plan':None,'checkpoints':[],'approval':None}
            d = cp(root,a.id,'change.json').parent
            d.mkdir(parents=True)
            try:
                for name in ('CONTRACT.md','EXECUTION_REPORT.md','REVIEW.md','OWNER_TEST.md'):
                    text = child(root,H+'/templates/'+name).read_text(encoding='utf-8')
                    atomic(cp(root,a.id,name),text.replace('{{ID}}',a.id).replace('{{TITLE}}',a.title).encode('utf-8'))
                write_json(cp(root,a.id,'REFERENCES.json'),{'sources':[]})
                write_json(cp(root,a.id,'verification.json'),{'change_id':a.id,'checks':{k:{'status':'pending'} for k in CHECKS}})
                s.update(current_assignment=a.id,phase='CONTRACT',mode='SCOPE',status='owner_task_received',next_actor='DLA',next_mode='SCOPE',current_investigation=None)
                s['owner_action']={'required':False,'action':'DLA 定向核验；只问未决问题，或一次提交明确范围供确认。'}
                s['test_action']={'required':False,'reason':'尚未授权实现；不自动运行产品或设备。'}
                save_both(root,c,s)
            except Exception:
                shutil.rmtree(d)
                raise
            print('Owner task recorded:',a.id,'; DRAFT only, not implementation permission.'); return 0
        if a.cmd == 'pin-ref':
            c=change(root,a.id)
            if c['status']!='DRAFT' or c.get('approval'): raise HarnessError('Pin references only in unapproved DRAFT')
            ref=external_root(root,a.workspace); file=child(ref,a.path)
            if not file.is_file(): raise HarnessError('Reference file missing')
            r=read_json(cp(root,a.id,'REFERENCES.json'))
            if any(x.get('id')==a.ref_id for x in r['sources']): raise HarnessError('Duplicate reference id; reconcile explicit record instead')
            r['sources'].append({'id':a.ref_id,'workspace':a.workspace,'path':str(safe_rel(a.path)),
                'revision_or_commit':git_info(ref).get('head') or 'NO_GIT_HEAD; file SHA pins observed snapshot',
                'sha256':digest(file.read_bytes()),'section':a.section,'kind':a.kind,'maturity':a.maturity,'observed_at':now()})
            write_json(cp(root,a.id,'REFERENCES.json'),r)
            print('Pinned observed file; maturity is a supplied claim, not proof of implementation/device behavior.'); return 0
        if a.cmd in ('approve','activate'):
            check_state(root,s)
            if s.get('active_change'): raise HarnessError('Only one active implementation allowed')
            c=change(root,a.id)
            if a.cmd=='approve':
                if c['status']!='DRAFT' or s.get('current_assignment')!=a.id: raise HarnessError('Only current Owner-dispatched DRAFT can be approved')
                c['approval']={'at':now(),'owner_record':a.owner_record,'owner_record_sha256':ev_hash(root,a.owner_record),'inputs':contract_inputs(root,c)}
            else:
                if c['status']!='PAUSED' or s.get('current_assignment'): raise HarnessError('activate is explicit resume of PAUSED work only')
                approval_ok(root,c)
                c['resume']={'owner_record':a.owner_record,'sha256':ev_hash(root,a.owner_record),'at':now()}
            paused=[x for x in all_changes(root) if x.get('status')=='PAUSED']
            if paused:
                if not a.isolation_record: raise HarnessError('Paused work exists; --isolation-record required; tool never stashes/checks out')
                ev_hash(root,a.isolation_record)
            fp=source_fingerprint(root)
            # Reopening a Contract retains the original diff baseline, so earlier edits cannot disappear from review.
            if not cp(root,a.id,'start-fingerprint.json').exists():
                write_json(cp(root,a.id,'start-fingerprint.json'),fp)
            c.update(status='ACTIVE',phase='BUILD_VERIFY',build_round=c.get('build_round',0)+1,activated_at=now(),isolation_record=a.isolation_record)
            s.update(current_assignment=a.id,active_change=a.id,phase='BUILD_VERIFY',mode='IMPLEMENT',status='active',next_actor='DIB',next_mode='IMPLEMENT')
            s['owner_action']={'required':False,'action':'DIB 连续完成已批准增量；仅边界变化/阻塞才交回。'}
            s['test_action']={'required':False,'reason':'DIB 先完成机器检查，DLA 随后给 Owner 测试包。'}
            save_both(root,c,s)
            print('Contract approval recorded and task ACTIVE:',a.id,'; no separate global baseline approval required.'); return 0
        if a.cmd=='submit':
            c=require_active(root,s,a.id); fp=scope_diff(root,c)
            for name in ('machine','core_regression','special_regression','mock'): check_verification(root,c,name)
            report=digest(cp(root,a.id,'EXECUTION_REPORT.md').read_bytes())
            rec={'at':now(),'build_round':c['build_round'],'approval_sha256':approval_ok(root,c),'report_sha256':report,'code_fingerprint':fp['sha256']}
            write_json(cp(root,a.id,'builder_submission.json'),rec)
            print('Builder submitted for DLA review; not UAT/closure. Global DLA state not modified.'); return 0
        if a.cmd=='record-check':
            c=require_active(root,s,a.id)
            if a.role=='DIB' and a.check in ('review','real_device','owner_uat'):
                raise HarnessError('DIB cannot record DLA review or Owner real-device/UAT results')
            if a.status in ('pass','fail') and not a.evidence: raise HarnessError('PASS/FAIL requires actual evidence files')
            if a.status=='not_applicable' and not a.reason: raise HarnessError('N/A needs a scoped reason')
            if a.status=='not_applicable' and (a.check in ('machine','review') or (a.check in ('real_device','owner_uat') and c['requirements'][a.check])):
                raise HarnessError('Required check cannot be waived')
            rec={'status':a.status,'reason':a.reason,'evidence':{r:ev_hash(root,r) for r in a.evidence},'role':a.role,'at':now(),
                 'code_fingerprint':scope_diff(root,c)['sha256'],'build_round':c['build_round'],'approval_sha256':approval_ok(root,c)}
            if a.check=='review' and a.status=='pass': submission_ok(root,c)
            if a.check in ('real_device','owner_uat') and a.status in ('pass','fail'):
                rec['test_packet_sha256']=packet_ok(root,c)
            v=read_json(cp(root,a.id,'verification.json')); v['checks'][a.check]=rec
            write_json(cp(root,a.id,'verification.json'),v)
            print('Recorded',a.check,a.status,'; evidence hashes do not authenticate the tester or prove results.'); return 0
        if a.cmd=='request-test':
            c=require_active(root,s,a.id); subrec=submission_ok(root,c)
            for name in ('machine','core_regression','special_regression','mock','review'): check_verification(root,c,name)
            artifact={'path':a.artifact,'sha256':ev_hash(root,a.artifact)}
            firmware=None
            if c['requirements']['device_related']:
                if not a.firmware_record: raise HarnessError('Need Firmware identity record: model/version/checkpoint/actual HEX identity and provenance; no guessed HEX')
                firmware={'path':a.firmware_record,'sha256':ev_hash(root,a.firmware_record)}
            brief=H+'/changes/'+a.id+'/OWNER_TEST.md'
            packet={'id':a.id,'at':now(),'build_round':c['build_round'],'code_fingerprint':subrec['code_fingerprint'],'approval_sha256':approval_ok(root,c),
                    'windows_artifact':artifact,'firmware_identity':firmware,'brief':{'path':brief,'sha256':ev_hash(root,brief)}}
            write_json(cp(root,a.id,'test_packet.json'),packet)
            s.update(mode='OWNER_TEST',status='awaiting_owner_test',next_actor='Owner',next_mode='REAL_TEST')
            s['owner_action']={'required':True,'action':'按 '+brief+' 测试并返回实际结果；不自动烧录。'}
            s['test_action']={'required':True,'brief':brief,'packet':H+'/changes/'+a.id+'/test_packet.json'}
            save_state(root,s); print('Owner test packet recorded; not a passing result.'); return 0
        if a.cmd in ('suspend','park'):
            c=change(root,a.id)
            if a.cmd=='suspend':
                c=require_active(root,s,a.id); c['status']='PAUSED'
            elif c['status']!='DRAFT' or s.get('current_assignment')!=a.id:
                raise HarnessError('park applies to current DRAFT only')
            else:
                c['status']='PARKED'
            c['pause']={'at':now(),'note':a.note,'sha256':ev_hash(root,a.note),'code_fingerprint':source_fingerprint(root)['sha256'],'git':git_info(root)}
            wait_state(s); save_both(root,c,s)
            print(c['status'],'; preserved work, no Git operations, no next candidate selected.'); return 0
        if a.cmd=='request-fix':
            c=require_active(root,s,a.id)
            c['fix_request']={'at':now(),'record':a.review_record,'sha256':ev_hash(root,a.review_record)}
            c['build_round']+=1
            s.update(mode='FIX',status='implementation_fix_requested',next_actor='DIB',next_mode='FIX')
            s['owner_action']={'required':False,'action':'DIB 在原 Contract 内修复，不自动扩大范围。'}
            s['test_action']={'required':False,'reason':'修复后重新提交适用证据和测试包。'}
            save_both(root,c,s); print('Implementation defect loop; old check rounds no longer qualify.'); return 0
        if a.cmd=='reopen-contract':
            c=change(root,a.id)
            if c['status'] not in ('ACTIVE','DRAFT'): raise HarnessError('Only current active/draft can reopen; other work needs explicit Owner dispatch')
            if a.id not in (s.get('active_change'),s.get('current_assignment')): raise HarnessError('Not current assignment')
            note={'path':a.reason_record,'sha256':ev_hash(root,a.reason_record),'at':now()}
            if c.get('approval'):
                write_json(cp(root,a.id,'approval-history/'+str(c['revision'])+'-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')+'.json'),c['approval'])
            c.update(status='DRAFT',phase='CONTRACT',approval=None,revision=c['revision']+1,reopen_reason=note)
            s.update(active_change=None,current_assignment=a.id,phase='CONTRACT',mode='RECONCILE',status='contract_revision_required',next_actor='DLA',next_mode='RECONCILE')
            s['owner_action']={'required':False,'action':'DLA 先核对受影响边界；必要时只重新确认变化部分。'}
            s['test_action']={'required':False,'reason':'约定修订中，旧证据保留但不自动有效。'}
            save_both(root,c,s); print('Affected Contract reopened; existing code/history retained, not rolled back.'); return 0
        if a.cmd=='close':
            c=require_active(root,s,a.id); submission_ok(root,c)
            for name in CHECKS: check_verification(root,c,name)
            c.update(status='CLOSED',closed_at=now(),closure_scope='internal_integration_only_not_release')
            wait_state(s); save_both(root,c,s)
            print('CLOSED according to supplied scoped records. WAIT_OWNER_TASK; not release-ready and no automatic next task.'); return 0
    raise HarnessError('Unknown command')

# Local, standard-library guard extension. Not a security sandbox.
import guardrails

def parser():
    return guardrails.make_parser(sys.modules[__name__])

def main(argv=None):
    return guardrails.run(sys.modules[__name__], argv)

if __name__=='__main__':
    try:
        if sys.version_info<(3,9): raise HarnessError('Python 3.9+ required')
        raise SystemExit(main())
    except (HarnessError,OSError,ValueError,TypeError,KeyError) as e:
        print('HARNESS STOP:',str(e),file=sys.stderr)
        raise SystemExit(2)
