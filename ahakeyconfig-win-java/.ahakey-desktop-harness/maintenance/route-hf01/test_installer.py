import builtins
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT/'.agents/skills/ahakey-desktop-harness/scripts'))
import desktop as h
import guardrails as old
spec = importlib.util.spec_from_file_location('route_installer', HERE/'install_reviewed.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=HERE, prefix='installer-fixture-')
        self.root = Path(self.temp.name).resolve()
        assert self.root.is_relative_to(HERE)
        self.addCleanup(self.temp.cleanup)
        self.package = self.root/h.H/'maintenance/route-hf01'
        self.package.mkdir(parents=True)
        self.put('src/App.java', b'class App {}')
        self.put('config_server.json', b'{"fixture":true}')
        self.put(h.H+'/STATE.json', b'{"active_change":"WD-002"}')
        self.original = (ROOT/installer.GUARD).read_bytes()
        self.put(installer.GUARD, self.original)
        self.put(installer.OWNER, (ROOT/installer.OWNER).read_bytes())
        manifest = json.loads((HERE/'RECOVERY_EVIDENCE.json').read_bytes())
        for row in manifest['files']:
            self.put(row['path'], (ROOT/row['path']).read_bytes())
            self.put(row['content_copy'], (ROOT/row['content_copy']).read_bytes())
        files = {}
        for name in ('guardrails.py','RECOVERY_EVIDENCE.json','install_reviewed.py','test_route_guards.py'):
            data = (HERE/name).read_bytes()
            (self.package/name).write_bytes(data)
            files[name] = h.digest(data)
        (self.package/'REVIEW.json').write_text(json.dumps(
            {'result':'PASS','independent_agent':'unit-test-fixture-only','files':files}), encoding='utf-8')
        self.seal = json.dumps({'files':old.governance_snapshot(h,self.root)}).encode()
        self.put(old.POLICY_FILE, self.seal)

    def put(self, rel, data):
        p = self.root/rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def run_installer(self, inject_failure=False):
        def fixture_exec(code, namespace):
            builtins.exec(code, namespace)
            def inputs(*args):
                if inject_failure:
                    raise h.HarnessError('injected Git verification failure')
                return {'commit':'fixture-only','nonproduction_recovery_evidence':{}}
            namespace['committed_inputs'] = inputs
        with patch.object(installer,'ROOT',self.root), patch.object(installer,'HERE',self.package), \
             patch.object(installer,'OLD_GUARD',h.digest(self.original)), \
             patch.object(installer,'OLD_SEAL',h.digest(self.seal)), \
             patch.object(installer,'exec',fixture_exec,create=True):
            installer.install(True)

    def test_success_never_routes_or_changes_product(self):
        before = h.source_fingerprint(self.root)
        self.run_installer()
        self.assertEqual(before,h.source_fingerprint(self.root))
        self.assertEqual(b'{"active_change":"WD-002"}',(self.root/h.H/'STATE.json').read_bytes())
        self.assertTrue((self.package/'INSTALL_RECEIPT.json').exists())
        self.assertEqual((HERE/'guardrails.py').read_bytes(),(self.root/installer.GUARD).read_bytes())
        newseal = json.loads((self.root/old.POLICY_FILE).read_bytes())
        self.assertIn(installer.CLASSIFICATION,newseal['files'])

    def test_failure_restores_original_guard_and_seal(self):
        with self.assertRaises(h.HarnessError):
            self.run_installer(True)
        self.assertEqual(self.original,(self.root/installer.GUARD).read_bytes())
        self.assertEqual(self.seal,(self.root/old.POLICY_FILE).read_bytes())
        self.assertFalse((self.root/installer.CLASSIFICATION).exists())
        self.assertEqual(b'{"active_change":"WD-002"}',(self.root/h.H/'STATE.json').read_bytes())
        self.assertTrue((self.package/'INSTALL_FAILED.json').exists())

    def test_changed_reviewed_artifact_rejected_before_write(self):
        (self.package/'guardrails.py').write_bytes(b'changed')
        with self.assertRaises(h.HarnessError):
            self.run_installer()
        self.assertEqual(self.original,(self.root/installer.GUARD).read_bytes())
        self.assertFalse((self.package/'installed-backup').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
