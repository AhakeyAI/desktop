"""Isolated negative checks plus read-only validation of approved Git objects."""
import copy
from datetime import datetime, timezone
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0,str(ROOT/'.agents/skills/ahakey-desktop-harness/scripts'))
import desktop as old
import guardrails as g
sys.path.insert(0,str(HERE))
import pinned_references as p
import install_reviewed as installer
spec = importlib.util.spec_from_file_location('candidate_desktop', HERE/'desktop.py')
h = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = h
spec.loader.exec_module(h)


class ResolverChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=HERE)
        assert Path(self.tmp.name).resolve().is_relative_to(HERE.resolve())
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.manifest = json.loads((HERE/'pinned_reference_wd005.json').read_bytes())
        self.change = old.change(ROOT,'WD-005')
        self.refs = old.read_json(old.cp(ROOT,'WD-005','REFERENCES.json'))['sources']
        for rel in (p.MANIFEST,self.manifest['owner_record'],old.H+'/changes/WD-005/REFERENCES.json'):
            source = HERE/'pinned_reference_wd005.json' if rel == p.MANIFEST else ROOT/rel
            old.atomic(self.root/rel,source.read_bytes())
        for pin in self.manifest['pins']:
            old.atomic(self.root/pin['approved_bytes'],(ROOT/pin['approved_bytes']).read_bytes())
        self.blobs = {}
        for pin in self.manifest['pins']:
            approved = (ROOT/pin['approved_bytes']).read_bytes()
            self.blobs[pin['reference']['path']] = (pin['blob_oid'],approved.replace(b'\r\n',b'\n'))
        # Actual Git blobs may already contain mixed EOL. Use fixed read-only
        # objects, cached once, as immutable fixtures; never use a live socket.
        self.blobs = ACTUAL_BLOBS
        self.policy = patch.object(g,'policy_ok',return_value='test-policy').start()
        self.addCleanup(patch.stopall)
        patch.object(h,'external_root',return_value=self.root/'unread-worktree').start()
        patch.object(p,'commit_blob',side_effect=lambda _,repo,commit,path:self.blobs[path]).start()

    def write_manifest(self):
        old.write_json(self.root/p.MANIFEST,self.manifest)

    def run_resolver(self):
        return p.resolved_ids(h,self.root,self.change,self.refs)

    def test_exact_nine_without_worktree(self):
        self.assertEqual(9,len(self.run_resolver()))

    def test_unregistered_task_keeps_original_policy(self):
        self.change['id']='WD-004'
        self.assertEqual(set(),self.run_resolver())
        self.policy.assert_not_called()

    def test_missing_manifest_rejected(self):
        (self.root/p.MANIFEST).unlink()
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_revision_change_rejected(self):
        self.change['revision']+=1
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_approval_change_rejected(self):
        self.change['approval']['at']='changed'
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_reference_file_change_rejected(self):
        path=old.cp(self.root,'WD-005','REFERENCES.json')
        path.write_bytes(path.read_bytes()+b' ')
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_owner_record_change_rejected(self):
        (self.root/self.manifest['owner_record']).write_bytes(b'wrong')
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_content_copy_change_rejected(self):
        (self.root/self.manifest['pins'][0]['approved_bytes']).write_bytes(b'wrong')
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_blob_change_rejected(self):
        with patch.object(p,'commit_blob',return_value=('0'*40,b'wrong')):
            with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_missing_object_never_falls_back(self):
        with patch.object(p,'commit_blob',side_effect=h.HarnessError('missing')):
            with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_full_reference_mapping_required(self):
        self.manifest['pins'][0]['reference']['path']='APP/not-approved.c'
        self.write_manifest()
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_incomplete_mapping_rejected(self):
        self.manifest['pins'].pop()
        self.write_manifest()
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_duplicate_mapping_rejected(self):
        self.manifest['pins'][-1]=self.manifest['pins'][0]
        self.write_manifest()
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_policy_failure_propagates(self):
        self.policy.side_effect=h.HarnessError('seal changed')
        with self.assertRaises(h.HarnessError): self.run_resolver()

    def test_eol_only_byte_equivalence(self):
        p.equivalent_text(h,b'\xc2\xa1\r\nX\n',b'\xc2\xa1\nX\r\n')

    def test_content_difference_not_normalized(self):
        for left,right in [(b'a \n',b'a\n'),(b'a\r',b'a\n'),(b'a\0\r\n',b'a\0\n'),(b'\xc2\r\n',b'\xc3\n')]:
            with self.assertRaises(h.HarnessError): p.equivalent_text(h,left,right)

    def test_nonliteral_commit_rejected(self):
        # Unpatch the Git-object fixture to exercise the actual validation.
        with self.assertRaises(h.HarnessError): ORIGINAL_COMMIT_BLOB(h,self.root,'HEAD','file.c')

    def test_path_traversal_rejected(self):
        with self.assertRaises(h.HarnessError): ORIGINAL_COMMIT_BLOB(h,self.root,'0'*40,'../file.c')

    def test_nonregular_blob_rejected(self):
        with patch.object(p,'git_bytes',side_effect=[b'0'*40+b'\n',b'120000 blob '+b'1'*40+b'\tfile.c\0']):
            with self.assertRaises(h.HarnessError): ORIGINAL_COMMIT_BLOB(h,self.root,'0'*40,'file.c')

    def test_unmapped_gate_still_checks_exact_bytes(self):
        with patch.object(p,'resolved_ids',return_value={r['id'] for r in self.refs if r['kind'] in ('protocol','implementation')}):
            with self.assertRaisesRegex(h.HarnessError,'CP2-ARCH'):
                h.reference_inputs(self.root,self.change)


class InstallerChecks(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir=HERE)
        assert Path(self.tmp.name).resolve().is_relative_to(HERE.resolve())
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.here=self.root/old.H/'maintenance/pinned-reference-hf01'
        self.here.mkdir(parents=True)
        self.dest={name:'.agents/skills/ahakey-desktop-harness/scripts/'+name for name in ('desktop.py','pinned_references.py','pinned_reference_wd005.json')}
        old.atomic(self.root/self.dest['desktop.py'],b'old helper')
        old.atomic(self.root/old.H/'STATE.json',b'unchanged state')
        owner=old.H+'/owner.md'
        old.atomic(self.root/owner,b'owner authorized')
        old.write_json(self.root/g.POLICY_FILE,{'files':g.governance_snapshot(old,self.root)})
        self.oldseal=(self.root/g.POLICY_FILE).read_bytes()
        baseline={'runtime_destinations':self.dest,'old_desktop_sha256':old.digest(b'old helper'),
                  'old_seal_sha256':old.digest(self.oldseal),'owner_record':owner,'owner_sha256':old.digest(b'owner authorized'),
                  'source_fingerprint':old.source_fingerprint(self.root)['sha256'],
                  'protected':{old.H+'/STATE.json':old.digest(b'unchanged state')}}
        old.write_json(self.here/'BASELINE.json',baseline)
        self.data={'BASELINE.json':(self.here/'BASELINE.json').read_bytes(), **{name:b'new '+name.encode() for name in self.dest}}
        old.write_json(self.here/'REVIEW.json',{'result':'PASS','independent_agent':'isolated-test-only','files':{n:old.digest(b) for n,b in self.data.items()}})
        patch.object(installer,'HERE',self.here).start()
        patch.object(installer,'ROOT',self.root).start()
        patch.object(installer,'artifacts',return_value=self.data).start()
        self.addCleanup(patch.stopall)

    def test_dry_run_does_not_install(self):
        installer.install(False)
        self.assertEqual(b'old helper',(self.root/self.dest['desktop.py']).read_bytes())
        self.assertFalse((self.here/'installed-backup').exists())

    def test_reviewed_install_preserves_state(self):
        installer.install(True)
        self.assertEqual(b'unchanged state',(self.root/old.H/'STATE.json').read_bytes())
        g.policy_ok(old,self.root)
        self.assertEqual('APPLIED',old.read_json(self.here/'INSTALL_RECEIPT.json')['status'])

    def test_wrong_artifact_blocks_before_write(self):
        self.data['desktop.py']=b'tampered'
        with self.assertRaises(old.HarnessError): installer.install(True)
        self.assertEqual(self.oldseal,(self.root/g.POLICY_FILE).read_bytes())

    def test_missing_review_blocks_before_write(self):
        (self.here/'REVIEW.json').unlink()
        with self.assertRaises(FileNotFoundError): installer.install(True)
        self.assertEqual(self.oldseal,(self.root/g.POLICY_FILE).read_bytes())

    def test_failure_rolls_back_helper_and_seal(self):
        original=installer.protected_ok
        count=[0]
        def fail_after_install(value):
            count[0]+=1
            if count[0]==3: raise h.HarnessError('injected post-install failure')
            return original(value)
        with patch.object(installer,'protected_ok',side_effect=fail_after_install):
            with self.assertRaises(h.HarnessError): installer.install(True)
        self.assertEqual(b'old helper',(self.root/self.dest['desktop.py']).read_bytes())
        self.assertEqual(self.oldseal,(self.root/g.POLICY_FILE).read_bytes())
        self.assertFalse((self.root/self.dest['pinned_references.py']).exists())
        self.assertEqual('ROLLED_BACK',old.read_json(self.here/'INSTALL_FAILED.json')['status'])


ORIGINAL_COMMIT_BLOB=p.commit_blob
ACTUAL_BLOBS={}
if __name__ == '__main__':
    for pin in json.loads((HERE/'pinned_reference_wd005.json').read_bytes())['pins']:
        ref=pin['reference']
        ACTUAL_BLOBS[ref['path']]=p.commit_blob(old,old.external_root(ROOT,'firmware'),ref['revision_or_commit'],ref['path'])
    output=io.StringIO()
    result=unittest.TextTestRunner(stream=output,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    log=output.getvalue()
    print(log)
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    for name in ('TEST_RESULTS.log','TEST_RESULTS.json'):
        path=HERE/name
        if path.exists(): old.atomic(HERE/'test-history'/stamp/name,path.read_bytes())
    old.atomic(HERE/'TEST_RESULTS.log',log.encode('utf-8'))
    old.write_json(HERE/'TEST_RESULTS.json',{'at':old.now(),'tests':result.testsRun,'passed':result.wasSuccessful(),
                  'failures':len(result.failures),'errors':len(result.errors),
                  'log_sha256':old.digest(log.encode('utf-8')),'scope':'isolated Harness checks + read-only pinned Git blobs; no product tests/device/Git writes'})
    raise SystemExit(0 if result.wasSuccessful() else 1)
