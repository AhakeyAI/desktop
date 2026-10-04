"""Read-only Firmware -> Windows intake discovery for AhaKey Windows Harness v1.

This module never executes Firmware scripts, builds Firmware, writes Firmware, flashes a
device, or infers product approval. It reads the bound Firmware workspace and writes only
Windows-side intake/cursor records when explicitly requested by DLA commands.
"""
from __future__ import annotations
import hashlib, json, re
from datetime import datetime, timezone
from pathlib import Path

H = '.ahakey-desktop-harness'
SYNC = H + '/firmware-sync.json'
FORMAL_NAMES = {
    'gate-receipt.json', 'gate_receipt.json', 'formal_firmware_gate.json',
    'formal-gate.json', 'gate.json', 'gate-receipt.JSON'.lower()
}
SHA256_RE = re.compile(r'^[0-9a-fA-F]{64}$')
COMMIT_RE = re.compile(r'^[0-9a-fA-F]{40}$')
ISO_RE = re.compile(r'^\d{4}-\d{2}-\d{2}[T ]')


def _sha(p: Path) -> str:
    h = hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def _within(base: Path, p: Path) -> bool:
    try:
        p.resolve().relative_to(base.resolve())
        return True
    except Exception:
        return False


def _walk(v, prefix=''):
    if isinstance(v, dict):
        for k, x in v.items():
            key = f'{prefix}.{k}' if prefix else str(k)
            yield from _walk(x, key)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            yield from _walk(x, f'{prefix}[{i}]')
    else:
        yield prefix, v


def _gate_time(data, p: Path):
    preferred = ('generated_at','created_at','timestamp','at','time','updated_at')
    flat = list(_walk(data))
    for want in preferred:
        for k, v in flat:
            if k.lower().split('.')[-1] == want and isinstance(v, str) and (ISO_RE.match(v) or 'T' in v):
                return v
    return datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc).isoformat(timespec='seconds')


def _extract_gate(fw: Path, p: Path):
    try:
        data = json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e:
        return {'path': p.relative_to(fw).as_posix(), 'sha256': _sha(p), 'parse_error': str(e), 'sort_time': datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc).isoformat(timespec='seconds')}
    if not isinstance(data, dict):
        data = {'_value': data}
    flat = list(_walk(data))
    hexes, shas, commits, statuses, ids = [], [], [], [], []
    for k, v in flat:
        kl = k.lower()
        if isinstance(v, str):
            vs = v.strip()
            if vs.lower().endswith('.hex'):
                # Accept only paths that resolve inside the Firmware workspace.
                candidates = []
                q = Path(vs)
                if q.is_absolute(): candidates.append(q)
                else:
                    candidates += [p.parent / q, fw / q]
                for c in candidates:
                    try:
                        r = c.resolve()
                    except Exception:
                        continue
                    if r.is_file() and _within(fw, r):
                        rec = {'path': r.relative_to(fw).as_posix(), 'sha256': _sha(r)}
                        if rec not in hexes: hexes.append(rec)
                        break
            if SHA256_RE.fullmatch(vs) and ('sha' in kl or 'hash' in kl):
                shas.append({'field': k, 'value': vs.lower()})
            if COMMIT_RE.fullmatch(vs) and any(x in kl for x in ('commit','revision','git','head')):
                commits.append({'field': k, 'value': vs.lower()})
            if any(x in kl for x in ('status','decision','result','gate')) and len(vs) <= 120:
                statuses.append({'field': k, 'value': vs})
            if any(x in kl for x in ('checkpoint','gate_id','change_id','module','journey')) and len(vs) <= 160:
                ids.append({'field': k, 'value': vs})
    text = json.dumps(data, ensure_ascii=False).lower()
    formal_hint = any(x in text for x in ('"pass"','"passed"','regate_pass','formal')) or 'gate-receipt' in p.name.lower()
    return {
        'path': p.relative_to(fw).as_posix(),
        'sha256': _sha(p),
        'sort_time': _gate_time(data, p),
        'formal_hint': bool(formal_hint),
        'status_fields': statuses[:20],
        'identity_fields': ids[:20],
        'commit_fields': commits[:10],
        'sha_fields': shas[:20],
        'hex_artifacts': hexes[:20],
    }


def gates(h, root: Path):
    fw = h.external_root(root, 'firmware')
    evidence = fw / '.ahakey-harness' / 'evidence'
    roots = [evidence / 'checkpoints', evidence]
    found = {}
    for base in roots:
        if not base.is_dir() or not _within(fw, base):
            continue
        for p in base.rglob('*.json'):
            if not p.is_file() or p.is_symlink() or not _within(fw, p):
                continue
            low = p.name.lower()
            rel = p.relative_to(fw).as_posix()
            if low in FORMAL_NAMES or 'gate-receipt' in low or 'formal_firmware_gate' in low:
                found[rel] = _extract_gate(fw, p)
    return fw, sorted(found.values(), key=lambda x: (x.get('sort_time',''), x['path']))


def _sync(h, root):
    p = h.child(root, SYNC)
    if not p.exists():
        return {'schema_version':1,'status':'uninitialized','last_consumed':None,'history':[]}
    x = h.read_json(p)
    if x.get('schema_version') != 1:
        raise h.HarnessError('Invalid firmware-sync schema; use reviewed Harness package')
    x.setdefault('history', [])
    return x


def status(h, root):
    fw = h.external_root(root, 'firmware')
    x = _sync(h, root)
    print('Firmware root:', fw)
    print('Firmware sync status:', x.get('status'))
    last = x.get('last_consumed')
    if last:
        print('Last consumed Windows change:', last.get('windows_change'))
        print('Last consumed gate:', last.get('gate',{}).get('path'))
        print('Last consumed gate SHA256:', last.get('gate',{}).get('sha256'))
    else:
        print('Last consumed gate: UNINITIALIZED — DLA must reconcile from existing Windows/Firmware evidence; Owner does not manually transcribe gate facts.')


def discover(h, root, limit=20, json_output=False):
    fw, rows = gates(h, root)
    sync = _sync(h, root)
    last = (sync.get('last_consumed') or {}).get('gate') or {}
    last_sha = last.get('sha256')
    seen = False if last_sha else None
    new = []
    for r in rows:
        if last_sha and r.get('sha256') == last_sha:
            seen = True
            continue
        if seen is True:
            new.append(r)
    result = {
        'firmware_root': str(fw),
        'sync_status': sync.get('status'),
        'last_consumed': sync.get('last_consumed'),
        'formal_gate_count': len(rows),
        'candidate_mode': 'after_cursor' if last_sha and seen else ('cursor_not_found' if last_sha else 'cursor_uninitialized'),
        'new_candidates': new[-limit:] if seen is True else [],
        'recent_gates': rows[-limit:],
        'meaning': 'Read-only discovery. Paths/hashes are observed evidence, not Windows approval or Firmware test truth.'
    }
    if json_output:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    print('Firmware-driven discovery: READ ONLY')
    print('Root:', fw)
    print('Cursor:', result['candidate_mode'], '| gates:', len(rows), '| new after cursor:', len(result['new_candidates']))
    chosen = result['new_candidates'] if result['candidate_mode']=='after_cursor' else result['recent_gates']
    if not chosen:
        print('No automatically selectable new formal gate. DLA should reconcile existing evidence or report a Firmware-side evidence gap; do not ask Owner to copy HEX/SHA/protocol facts already present in the repo.')
    for i, r in enumerate(chosen, 1):
        print(f'[{i}] {r["path"]}')
        print('    gate_sha256:', r['sha256'])
        print('    sort_time:', r.get('sort_time'), '| formal_hint:', r.get('formal_hint'))
        if r.get('hex_artifacts'):
            for hx in r['hex_artifacts'][:3]: print('    HEX:', hx['path'], hx['sha256'])
        if r.get('commit_fields'):
            print('    commit:', r['commit_fields'][0]['value'])
        if r.get('status_fields'):
            print('    status:', r['status_fields'][0]['value'])
    print('Owner should only be asked to choose priority when multiple equally valid candidates remain, or to decide product behavior not determined by Firmware evidence.')


def _resolve_gate(h, root, gate):
    fw = h.external_root(root, 'firmware')
    q = Path(gate).expanduser()
    p = q.resolve() if q.is_absolute() else (fw / q).resolve()
    if not p.is_file() or not _within(fw, p):
        raise h.HarnessError('Firmware gate path missing or outside bound read-only Firmware root')
    return fw, p, _extract_gate(fw, p)


def intake(h, root, cid, gate, role, title=None):
    if role != 'DLA': raise h.HarnessError('Firmware intake is DLA-only')
    h.require_id(cid)
    fw, p, rec = _resolve_gate(h, root, gate)
    s = h.state(root)
    out = h.child(root, H + '/v1/planned-changes/' + cid + '-firmware-evidence.json')
    body = {
        'schema_version':1, 'id':cid, 'status':'PLANNED_FIRMWARE_EVIDENCE', 'created_at':h.now(),
        'title': title or '', 'firmware_root':str(fw), 'gate':rec,
        'windows_state_at_intake': {'phase':s.get('phase'),'mode':s.get('mode'),'active_change':s.get('active_change'),'current_assignment':s.get('current_assignment')},
        'meaning':'Evidence binding only. Does not create changes/'+cid+', approve a Contract, activate DIB, transfer old PASS, or modify Firmware.',
        'owner_burden':'Owner is not required to transcribe local gate/HEX/SHA/protocol facts. DLA reads Firmware evidence; Owner resolves priority/product ambiguity only.'
    }
    if out.exists():
        old = h.read_json(out)
        if old.get('gate',{}).get('sha256') == rec.get('sha256'):
            print('FIRMWARE INTAKE ALREADY RECORDED:', out)
            return
        raise h.HarnessError('Planned Firmware evidence already exists with a different gate; preserve history and use a new reviewed revision file')
    h.write_json(out, body)
    print('FIRMWARE INTAKE RECORDED:', out)
    print('Gate:', rec['path'], rec['sha256'])
    if rec.get('hex_artifacts'):
        for hx in rec['hex_artifacts']: print('HEX:', hx['path'], hx['sha256'])
    print('No changes/'+cid+' task created; no DIB activation/build/test/Git/Firmware write.')


def baseline(h, root, gate, windows_change, evidence_record, role):
    if role != 'DLA': raise h.HarnessError('Firmware sync baseline is DLA-only')
    h.require_id(windows_change)
    fw, p, rec = _resolve_gate(h, root, gate)
    ev = {'path': h.safe_rel(evidence_record).as_posix(), 'sha256': h.ev_hash(root, evidence_record)}
    sync = _sync(h, root)
    if sync.get('last_consumed'):
        old = sync['last_consumed']
        if old.get('gate',{}).get('sha256') == rec['sha256'] and old.get('windows_change') == windows_change:
            print('FIRMWARE SYNC BASELINE ALREADY MATCHES.'); return
        raise h.HarnessError('Firmware sync baseline already initialized; do not rewrite history. Use mark-consumed after a closed Windows change.')
    entry={'at':h.now(),'kind':'historical_reconcile','windows_change':windows_change,'gate':rec,'evidence_record':ev}
    sync.update(status='initialized', firmware_root=str(fw), last_consumed=entry)
    sync.setdefault('history',[]).append(entry)
    h.write_json(h.child(root,SYNC),sync)
    print('FIRMWARE SYNC BASELINE INITIALIZED:', rec['path'])
    print('This records a Windows-side cursor only; it does not alter Firmware or claim new product PASS.')


def mark_consumed(h, root, gate, windows_change, evidence_record, role):
    if role != 'DLA': raise h.HarnessError('Firmware mark-consumed is DLA-only')
    c = h.change(root, windows_change)
    if c.get('status') != 'CLOSED':
        raise h.HarnessError('Firmware cursor advances only after the linked Windows change is CLOSED at its declared test scope')
    fw, p, rec = _resolve_gate(h, root, gate)
    ev={'path':h.safe_rel(evidence_record).as_posix(),'sha256':h.ev_hash(root,evidence_record)}
    sync=_sync(h,root)
    entry={'at':h.now(),'kind':'closed_windows_change','windows_change':windows_change,'gate':rec,'evidence_record':ev}
    sync.update(status='initialized', firmware_root=str(fw), last_consumed=entry)
    sync.setdefault('history',[]).append(entry)
    h.write_json(h.child(root,SYNC),sync)
    print('FIRMWARE CURSOR ADVANCED:', windows_change, '->', rec['path'])
    print('No Firmware write, build, flash, or automatic next task was performed.')
