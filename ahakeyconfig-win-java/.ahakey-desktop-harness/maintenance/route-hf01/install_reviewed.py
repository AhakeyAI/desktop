"""Install the independently reviewed route-hf01 maintenance artifact, never route tasks."""
import argparse
import json
from pathlib import Path
import sys
import types

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCRIPTS = ROOT / '.agents/skills/ahakey-desktop-harness/scripts'
sys.path.insert(0, str(SCRIPTS))
import desktop as h
import guardrails as old

GUARD = '.agents/skills/ahakey-desktop-harness/scripts/guardrails.py'
CLASSIFICATION = h.H + '/RECOVERY_EVIDENCE.json'
OLD_GUARD = '1845cd850e5ef33e62250ec6d60fef558a16a638175098fc0c578013748126ed'
OLD_SEAL = 'aa40e210a4fc6e76d64838675b33fc79b7de7d5c6ca0ae476d272b225f7079b9'
OWNER = h.H + '/evidence/20261015-wd005-route-maintenance-owner-authorization.md'
OWNER_HASH = '9d225bd4fa28b894a231f445d2585e8d0a060b1b507660dd2e57fef90fb7a59b'


def require(ok, message):
    if not ok:
        raise h.HarnessError(message)


def install(apply=False):
    review_path = HERE / 'REVIEW.json'
    review_bytes = review_path.read_bytes()
    review = json.loads(review_bytes)
    require(review.get('result') == 'PASS' and bool(review.get('independent_agent')), 'Independent review required')
    artifacts = {name:(HERE/name).read_bytes() for name in
                 ('guardrails.py', 'RECOVERY_EVIDENCE.json', 'install_reviewed.py', 'test_route_guards.py')}
    for name, data in artifacts.items():
        require(review['files'].get(name) == h.digest(data), 'Reviewed artifact changed: '+name)
    require(h.ev_hash(ROOT, OWNER) == OWNER_HASH, 'Owner authorization changed')
    require(h.ev_hash(ROOT, GUARD) == OLD_GUARD, 'Installed guard changed; no blind overwrite')
    require(h.ev_hash(ROOT, old.POLICY_FILE) == OLD_SEAL, 'Installed policy changed')
    require(not h.child(ROOT, CLASSIFICATION).exists(), 'Classification already exists; inspect receipt, no overwrite')
    old.policy_ok(h, ROOT)
    protected = {h.H+'/STATE.json': h.ev_hash(ROOT, h.H+'/STATE.json')}
    for task in ('WD-001','WD-002','WD-003','WD-004'):
        directory = ROOT/h.H/'changes'/task
        for name in ('change.json','CONTRACT.md','REFERENCES.json','start-fingerprint.json','guard-origin.json'):
            file = directory/name
            if file.is_file():
                rel = file.relative_to(ROOT).as_posix()
                protected[rel] = h.ev_hash(ROOT, rel)
    config_hash = h.ev_hash(ROOT, 'config_server.json')
    source = h.source_fingerprint(ROOT)
    new = types.ModuleType('reviewed_route_guard')
    exec(compile(artifacts['guardrails.py'], str(HERE/'guardrails.py'), 'exec'), new.__dict__)
    if not apply:
        print('Reviewed installer preflight passed; no runtime or task changed.')
        return
    with h.lock(ROOT):
        # Repeat mutable preconditions under the same writer lock as the official helper.
        require(h.ev_hash(ROOT, GUARD) == OLD_GUARD, 'Guard changed before lock')
        require(h.ev_hash(ROOT, old.POLICY_FILE) == OLD_SEAL, 'Policy changed before lock')
        require(h.ev_hash(ROOT, OWNER) == OWNER_HASH, 'Owner record changed before lock')
        require(review_path.read_bytes() == review_bytes, 'Review changed before lock')
        require(h.source_fingerprint(ROOT) == source, 'Source changed before lock')
        require(all(h.ev_hash(ROOT,p)==v for p,v in protected.items()), 'Task record changed before lock')
        old.policy_ok(h, ROOT)
        backup = HERE/'installed-backup'
        require(not backup.exists(), 'Installation attempt exists; inspect recovery before retry')
        backup.mkdir()
        before = {GUARD:h.child(ROOT,GUARD).read_bytes(),
                  old.POLICY_FILE:h.child(ROOT,old.POLICY_FILE).read_bytes()}
        for rel, data in before.items():
            h.atomic(backup/Path(rel).name, data)
        h.write_json(backup/'MANIFEST.json', {'files':{p:h.digest(b) for p,b in before.items()},
                     'protected':protected,'source_fingerprint':source['sha256'],'config_sha256':config_hash})
        try:
            h.atomic(h.child(ROOT, GUARD), artifacts['guardrails.py'])
            h.atomic(h.child(ROOT, CLASSIFICATION), artifacts['RECOVERY_EVIDENCE.json'])
            new.recovery_evidence(h, ROOT)
            current = new.governance_snapshot(h, ROOT)
            prior = json.loads(before[old.POLICY_FILE])['files']
            delta = {p for p in set(prior)|set(current) if prior.get(p) != current.get(p)}
            require(delta == {GUARD, CLASSIFICATION}, 'Unexpected governance change')
            seal = json.loads(before[old.POLICY_FILE])
            seal['files'] = current
            seal['reviewed_upgrade'] = {'id':'route-hf01', 'at':h.now(),
                'owner_record':OWNER,'owner_sha256':OWNER_HASH,
                'review':review_path.relative_to(ROOT).as_posix(),
                'review_sha256':h.digest(review_bytes)}
            h.write_json(h.child(ROOT, old.POLICY_FILE), seal)
            new.policy_ok(h, ROOT)
            anchor = new.committed_inputs(h, ROOT)
            require(h.source_fingerprint(ROOT) == source, 'Source changed during maintenance')
            require(h.ev_hash(ROOT, 'config_server.json') == config_hash, 'Local config changed')
            require(all(h.ev_hash(ROOT,p)==v for p,v in protected.items()), 'Protected task record changed')
            h.write_json(HERE/'INSTALL_RECEIPT.json', {'status':'APPLIED','at':h.now(),
                'review_sha256':h.digest(review_bytes),'changed_paths':sorted(delta|{old.POLICY_FILE}),
                'recoverable_inputs':anchor,'protected_unchanged':protected,'production_unchanged':True,
                'meaning':'Reviewed maintenance installed; no task route, approval, test PASS or product changed.'})
        except Exception:
            for rel, data in before.items():
                h.atomic(h.child(ROOT, rel), data)
            target = h.child(ROOT, CLASSIFICATION)
            if target.exists():
                target.unlink()
            h.write_json(HERE/'INSTALL_FAILED.json', {'status':'ROLLED_BACK','at':h.now()})
            raise
    print('Reviewed route-hf01 installed; old tasks/STATE/product unchanged. Use official suspend next.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        install(args.apply)
    except Exception as error:
        print('MAINTENANCE STOP:', str(error), file=sys.stderr)
        raise SystemExit(1)
