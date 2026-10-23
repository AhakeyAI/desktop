"""Install only independently reviewed fixed-reference artifacts, with rollback."""
import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCRIPTS = ROOT / '.agents/skills/ahakey-desktop-harness/scripts'
sys.path.insert(0, str(SCRIPTS))
import desktop as h
import guardrails as g


def require(ok, message):
    if not ok:
        raise h.HarnessError(message)


def protected_ok(baseline):
    require(h.source_fingerprint(ROOT)['sha256'] == baseline['source_fingerprint'], 'Product source changed')
    for rel, expected in baseline['protected'].items():
        require(h.digest(h.child(ROOT, rel).read_bytes()) == expected, 'Protected history changed: '+rel)


def artifacts():
    names = ['desktop.py', 'pinned_references.py', 'pinned_reference_wd005.json',
             'BASELINE.json', 'PLAN.md', 'prepare.py', 'install_reviewed.py', 'test_pinned_references.py',
             'TEST_RESULTS.json', 'TEST_RESULTS.log']
    names += sorted(path.relative_to(HERE).as_posix() for path in (HERE/'approved-bytes').glob('*.bin'))
    return {name: (HERE/name).read_bytes() for name in names}


def install(apply=False):
    baseline_bytes = (HERE/'BASELINE.json').read_bytes()
    baseline = json.loads(baseline_bytes)
    review_bytes = (HERE/'REVIEW.json').read_bytes()
    review = json.loads(review_bytes)
    data = artifacts()
    require(review.get('result') == 'PASS' and bool(review.get('independent_agent')), 'Independent review required')
    require(review.get('files') == {name:h.digest(value) for name,value in data.items()}, 'Reviewed artifacts changed')
    require(h.ev_hash(ROOT,baseline['owner_record']) == baseline['owner_sha256'], 'Owner authorization changed')
    desktop_path = baseline['runtime_destinations']['desktop.py']
    require(h.ev_hash(ROOT,desktop_path) == baseline['old_desktop_sha256'], 'Installed helper changed')
    require(h.ev_hash(ROOT,g.POLICY_FILE) == baseline['old_seal_sha256'], 'Installed policy changed')
    for name, rel in baseline['runtime_destinations'].items():
        require(rel == '.agents/skills/ahakey-desktop-harness/scripts/'+name, 'Unexpected destination')
        require(name == 'desktop.py' or not h.child(ROOT,rel).exists(), 'New helper path already exists')
    require(set(baseline['runtime_destinations']) == {'desktop.py','pinned_references.py','pinned_reference_wd005.json'},
            'Unexpected install set')
    g.policy_ok(h,ROOT)
    protected_ok(baseline)
    if not apply:
        print('Reviewed installer preflight passed; nothing installed.')
        return
    with h.lock(ROOT):
        require(artifacts() == data and (HERE/'REVIEW.json').read_bytes() == review_bytes, 'Artifacts changed before lock')
        require(h.ev_hash(ROOT,baseline['owner_record']) == baseline['owner_sha256'], 'Authorization changed before lock')
        require(h.ev_hash(ROOT,desktop_path) == baseline['old_desktop_sha256'], 'Helper changed before lock')
        require(h.ev_hash(ROOT,g.POLICY_FILE) == baseline['old_seal_sha256'], 'Policy changed before lock')
        g.policy_ok(h,ROOT)
        protected_ok(baseline)
        backup = HERE/'installed-backup'
        require(not backup.exists(), 'Prior installation attempt exists; inspect before retry')
        backup.mkdir()
        before = {desktop_path:h.child(ROOT,desktop_path).read_bytes(), g.POLICY_FILE:h.child(ROOT,g.POLICY_FILE).read_bytes()}
        new_paths = [rel for name,rel in baseline['runtime_destinations'].items() if name != 'desktop.py']
        for rel in new_paths:
            require(not h.child(ROOT,rel).exists(), 'Destination appeared before install')
        for rel,value in before.items():
            h.atomic(backup/Path(rel).name,value)
        h.write_json(backup/'MANIFEST.json', {'original_files':{rel:h.digest(value) for rel,value in before.items()},
                                          'baseline_sha256':h.digest(baseline_bytes), 'review_sha256':h.digest(review_bytes)})
        try:
            for name,rel in baseline['runtime_destinations'].items():
                h.atomic(h.child(ROOT,rel),data[name])
            snapshot = g.governance_snapshot(h,ROOT)
            seal = json.loads(before[g.POLICY_FILE])
            delta = {rel for rel in set(seal['files'])|set(snapshot) if seal['files'].get(rel) != snapshot.get(rel)}
            require(delta == set(baseline['runtime_destinations'].values()), 'Unexpected governance delta')
            seal['files'] = snapshot
            seal['reviewed_upgrade'] = {'id':'pinned-reference-hf01', 'at':h.now(),
                'owner_record':baseline['owner_record'], 'owner_sha256':baseline['owner_sha256'],
                'review':(HERE/'REVIEW.json').relative_to(ROOT).as_posix(), 'review_sha256':h.digest(review_bytes)}
            h.write_json(h.child(ROOT,g.POLICY_FILE),seal)
            g.policy_ok(h,ROOT)
            protected_ok(baseline)
            h.write_json(HERE/'INSTALL_RECEIPT.json', {'status':'APPLIED', 'at':h.now(),
                'review_sha256':h.digest(review_bytes), 'baseline_sha256':h.digest(baseline_bytes),
                'changed_paths':sorted(delta|{g.POLICY_FILE}), 'source_fingerprint':baseline['source_fingerprint'],
                'protected_file_count':len(baseline['protected']), 'task_history_unchanged':True,
                'meaning':'Reviewed reference resolver installed. No product PASS, task routing, Git or firmware writes.'})
        except BaseException:
            for rel,value in before.items():
                h.atomic(h.child(ROOT,rel),value)
            for rel in new_paths:
                h.child(ROOT,rel).unlink(missing_ok=True)
            h.write_json(HERE/'INSTALL_FAILED.json', {'status':'ROLLED_BACK', 'at':h.now()})
            raise
    print('Reviewed fixed-reference maintenance installed; task/product history unchanged.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply',action='store_true')
    try:
        install(parser.parse_args().apply)
    except Exception as error:
        print('MAINTENANCE STOP:',str(error),file=sys.stderr)
        raise SystemExit(1)
