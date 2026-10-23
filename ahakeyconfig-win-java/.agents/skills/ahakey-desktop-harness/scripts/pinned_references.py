"""Read explicitly reviewed historical references, never the latest firmware code."""
import os
import re
import subprocess

MANIFEST = '.agents/skills/ahakey-desktop-harness/scripts/pinned_reference_wd005.json'


def require(h, condition, message):
    if not condition:
        raise h.HarnessError('Pinned reference: ' + message)


def git_bytes(h, repository, arguments):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0',
               GIT_NO_REPLACE_OBJECTS='1', GIT_NO_LAZY_FETCH='1')
    try:
        result = subprocess.run(
            ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false',
             '-c', 'core.quotePath=false', '-C', str(repository)] + arguments,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise h.HarnessError('Pinned reference Git read failed: ' + str(error)) from error
    require(h, result.returncode == 0, 'Git object unavailable; no worktree fallback')
    return result.stdout


def commit_blob(h, repository, commit, path):
    require(h, isinstance(commit, str) and re.fullmatch('[0-9a-f]{40}', commit),
            'full immutable commit required')
    h.safe_rel(path)
    actual = git_bytes(h, repository, ['rev-parse', '--verify', commit + '^{commit}']).decode().strip()
    require(h, actual == commit, 'commit identity mismatch')
    # Literal pathspec avoids wildcard matching; only a regular blob is accepted.
    entries = git_bytes(h, repository, ['--literal-pathspecs', 'ls-tree', '-z', commit, '--', path])
    entries = [entry for entry in entries.split(b'\0') if entry]
    require(h, len(entries) == 1, 'missing or ambiguous path')
    meta, found_path = entries[0].split(b'\t', 1)
    mode, kind, oid = meta.decode('ascii').split()
    require(h, found_path.decode('utf-8') == path and kind == 'blob'
            and mode in ('100644', '100755'), 'non-regular Git reference')
    return oid, git_bytes(h, repository, ['cat-file', 'blob', oid])


def equivalent_text(h, approved, blob):
    if approved == blob:
        return
    # Some approved C sources contain legacy-encoded comments. Do not decode or
    # re-encode: both raw hashes are fixed, and only CRLF pairs may differ.
    require(h, b'\0' not in approved + blob
            and approved.replace(b'\r\n', b'\n') == blob.replace(b'\r\n', b'\n'),
            'content differs beyond explicitly pinned CRLF/LF bytes')


def resolved_ids(h, root, change, refs):
    if change['id'] != 'WD-005':
        return set()
    import guardrails
    guardrails.policy_ok(h, root)
    manifest = h.read_json(h.child(root, MANIFEST))
    require(h, manifest.get('schema_version') == 1 and manifest.get('change_id') == change['id'],
            'manifest schema or task mismatch')
    require(h, manifest['revision'] == change['revision'], 'contract revision changed; explicit reconciliation required')
    require(h, manifest['approval_sha256'] == h.digest(h.canonical(change.get('approval'))), 'approval changed')
    ref_file = h.cp(root, change['id'], 'REFERENCES.json')
    require(h, h.digest(ref_file.read_bytes()) == manifest['references_sha256'], 'approved references changed')
    require(h, h.ev_hash(root, manifest['owner_record']) == manifest['owner_sha256'], 'maintenance authorization changed')
    by_id = {ref['id']: ref for ref in refs}
    resolved = set()
    for pin in manifest['pins']:
        ref = by_id.get(pin['id'])
        require(h, ref is not None and ref == pin['reference'] and ref['workspace'] == 'firmware', 'reference mapping changed')
        require(h, pin['id'] not in resolved, 'duplicate mapping')
        approved = h.child(root, pin['approved_bytes']).read_bytes()
        require(h, h.digest(approved) == ref['sha256'], 'approved byte evidence changed')
        repository = h.external_root(root, ref['workspace'])
        oid, blob = commit_blob(h, repository, ref['revision_or_commit'], ref['path'])
        require(h, oid == pin['blob_oid'] and h.digest(blob) == pin['blob_sha256'], 'Git blob identity changed')
        equivalent_text(h, approved, blob)
        resolved.add(pin['id'])
    require(h, len(resolved) == 9, 'incomplete reviewed WD-005 mapping')
    return resolved
