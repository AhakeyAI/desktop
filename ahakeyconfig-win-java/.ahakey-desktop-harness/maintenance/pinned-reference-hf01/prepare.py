"""Prepare immutable maintenance artifacts; never install or edit firmware."""
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCRIPTS = ROOT / '.agents/skills/ahakey-desktop-harness/scripts'
sys.path.insert(0, str(SCRIPTS))
import desktop as h
import guardrails as g
sys.path.insert(0, str(HERE))
from pinned_references import commit_blob, equivalent_text

OWNER = h.H + '/evidence/20261021-wd005-pinned-reference-maintenance-owner-authorization.md'


def main():
    g.policy_ok(h, ROOT)
    if (HERE/'BASELINE.json').exists():
        raise h.HarnessError('Prepared package already exists; no overwrite')
    c = h.change(ROOT, 'WD-005')
    reference_file = h.cp(ROOT, c['id'], 'REFERENCES.json')
    refs = h.read_json(reference_file)['sources']
    manifest = {'schema_version': 1, 'change_id': c['id'], 'revision': c['revision'],
                'approval_sha256': h.digest(h.canonical(c['approval'])),
                'references_sha256': h.digest(reference_file.read_bytes()),
                'owner_record': OWNER, 'owner_sha256': h.ev_hash(ROOT, OWNER), 'pins': []}
    repository = h.external_root(ROOT, 'firmware')
    pending = {}
    for ref in refs:
        if ref['kind'] not in ('protocol', 'implementation'):
            continue
        oid, blob = commit_blob(h, repository, ref['revision_or_commit'], ref['path'])
        current = h.child(repository, ref['path']).read_bytes()
        choices = [(blob, 'raw Git blob'), (current, 'current bytes matching original approved SHA'),
                   (blob.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'), 'Git content reconstructed with CRLF')]
        if ref['id'] == 'CP2-COMMAND-HEADER':
            removed = (b'uint8_t command_external_flash_busy(void);', b'void command_storage_tick(void);')
            restored = b''.join(line for line in current.splitlines(keepends=True) if line.rstrip(b'\r\n') not in removed)
            choices.append((restored, 'Reconstructed mixed-EOL bytes, NOT a historical backup; SHA exactly equals original approval'))
        selected = next(((data, origin) for data, origin in choices if h.digest(data) == ref['sha256']), None)
        if selected is None:
            raise h.HarnessError('Cannot prove original approved bytes: ' + ref['id'])
        approved, origin = selected
        equivalent_text(h, approved, blob)
        name = 'approved-bytes/' + ref['id'] + '.bin'
        pending[name] = approved
        manifest['pins'].append({'id': ref['id'], 'reference': ref, 'blob_oid': oid,
                                 'blob_sha256': h.digest(blob),
                                 'approved_bytes': (HERE/name).relative_to(ROOT).as_posix(),
                                 'byte_origin': origin})
    if len(manifest['pins']) != 9:
        raise h.HarnessError('Expected exact nine original code references')
    old = (SCRIPTS/'desktop.py').read_bytes()
    text = old.decode('utf-8')
    newline = '\r\n' if '\r\n' in text else '\n'
    old_section = "    ids = set()" + newline + "    agreed_protocol = False"
    new_section = ("    from pinned_references import resolved_ids" + newline
                   + "    pinned_ids = resolved_ids(sys.modules[__name__], root, c, refs)" + newline + old_section)
    old_check = "        if not p.is_file() or digest(p.read_bytes()) != x['sha256']:"
    new_check = "        if x['id'] not in pinned_ids and (not p.is_file() or digest(p.read_bytes()) != x['sha256']):"
    if text.count(old_section) != 1 or text.count(old_check) != 1:
        raise h.HarnessError('Unexpected helper shape')
    pending['desktop.py'] = text.replace(old_section, new_section).replace(old_check, new_check).encode('utf-8')
    pending['pinned_reference_wd005.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode('utf-8')
    protected = {h.H+'/STATE.json': h.ev_hash(ROOT,h.H+'/STATE.json'),
                 h.H+'/local.json': h.ev_hash(ROOT,h.H+'/local.json')}
    for path in (ROOT/h.H/'changes'/'WD-005').rglob('*'):
        if path.is_file():
            rel = path.relative_to(ROOT).as_posix()
            protected[rel] = h.ev_hash(ROOT, rel) if path.stat().st_size else h.digest(b'')
    baseline = {'old_desktop_sha256': h.digest(old), 'old_seal_sha256': h.ev_hash(ROOT,g.POLICY_FILE),
                'owner_record': OWNER, 'owner_sha256': manifest['owner_sha256'],
                'source_fingerprint': h.source_fingerprint(ROOT)['sha256'], 'protected': protected,
                'runtime_destinations': {name: '.agents/skills/ahakey-desktop-harness/scripts/'+name
                                         for name in ('desktop.py','pinned_references.py','pinned_reference_wd005.json')}}
    for name, data in pending.items():
        h.atomic(HERE/name, data)
    h.write_json(HERE/'BASELINE.json', baseline)
    print(json.dumps({'prepared_pins':len(manifest['pins']), 'protected_files':len(protected),
                      'source_fingerprint':baseline['source_fingerprint'], 'installed':False}))


if __name__ == '__main__':
    main()
