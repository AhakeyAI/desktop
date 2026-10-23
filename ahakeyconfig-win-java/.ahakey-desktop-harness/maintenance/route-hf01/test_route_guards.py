import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / '.agents/skills/ahakey-desktop-harness/scripts'))
import desktop as h

spec = importlib.util.spec_from_file_location('candidate_guardrails', HERE / 'guardrails.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=HERE, prefix='test-fixture-')
        assert Path(self.temp.name).resolve().is_relative_to(HERE)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.put('src/App.java', b'class App {}')
        self.state = self.put(h.H + '/STATE.json', b'{"active_change":"WD-002"}')
        self.manifest = json.loads((HERE / 'RECOVERY_EVIDENCE.json').read_text(encoding='utf-8'))
        owner = self.manifest['owner_record']
        self.put(owner['path'], b'owner authorization')
        owner['sha256'] = h.digest(b'owner authorization')
        for i, row in enumerate(self.manifest['files']):
            data = ('recovery content ' + str(i)).encode()
            self.put(row['path'], data)
            self.put(row['content_copy'], data)
            row['sha256'] = h.digest(data)
        self.save_manifest()
        self.entries = {'src/App.java': {'kind':'blob', 'mode':'100644', 'oid':'source'}}
        self.contents = {'source': b'class App {}'}

    def put(self, rel, data):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        return p

    def save_manifest(self):
        self.put(h.H + '/RECOVERY_EVIDENCE.json', json.dumps(self.manifest).encode())

    def check(self):
        with patch.object(g, 'repo_info', return_value=(self.root, '')), \
             patch.object(g, 'commit_id', return_value='1'*40), \
             patch.object(g, 'tree', return_value=self.entries), \
             patch.object(g, 'blobs', return_value=self.contents):
            return g.committed_inputs(h, self.root)

    def rejected(self):
        before = self.state.read_bytes()
        with self.assertRaises(h.HarnessError):
            self.check()
        self.assertEqual(before, self.state.read_bytes())

    def test_exact_recovery_and_committed_source(self):
        result = self.check()
        self.assertEqual(3, len(result['nonproduction_recovery_evidence']))

    def test_modified_source_rejected(self):
        self.put('src/App.java', b'changed')
        self.rejected()

    def test_new_source_rejected(self):
        self.put('src/New.java', b'new')
        self.rejected()

    def test_deleted_source_rejected(self):
        (self.root / 'src/App.java').unlink()
        self.rejected()

    def test_unknown_backup_rejected(self):
        self.put('.rollback-backups/other.java', b'not reviewed')
        self.rejected()

    def test_recovery_change_rejected(self):
        self.put(self.manifest['files'][0]['path'], b'changed')
        self.rejected()

    def test_copy_change_rejected(self):
        self.put(self.manifest['files'][0]['content_copy'], b'changed')
        self.rejected()

    def test_missing_copy_rejected(self):
        (self.root / self.manifest['files'][0]['content_copy']).unlink()
        self.rejected()

    def test_missing_original_rejected(self):
        (self.root / self.manifest['files'][0]['path']).unlink()
        self.rejected()

    def test_owner_change_rejected(self):
        self.put(self.manifest['owner_record']['path'], b'changed')
        self.rejected()

    def test_classified_source_rejected(self):
        self.manifest['files'][0]['path'] = 'src/App.java'
        self.save_manifest()
        self.rejected()

    def test_duplicate_classification_rejected(self):
        self.manifest['files'][0] = self.manifest['files'][1]
        self.save_manifest()
        self.rejected()

    def test_unknown_content_path_rejected(self):
        self.manifest['files'][0]['content_copy'] = 'src/App.java'
        self.save_manifest()
        self.rejected()

    def test_runtime_config_consistent(self):
        self.put('config_server.json', b'local config')
        self.entries['config_server.json'] = {'kind':'blob','mode':'100644','oid':'config'}
        self.contents['config'] = b'old config'
        self.assertNotIn('config_server.json', h.source_fingerprint(self.root)['files'])
        self.assertFalse(g.product_path(h, 'config_server.json'))
        self.check()

    def test_manifest_sealed_and_mutation_rejected(self):
        seal = {'files': g.governance_snapshot(h, self.root)}
        self.put(h.H + '/GUARD_POLICY_SEAL.json', json.dumps(seal).encode())
        self.assertIn(h.H + '/RECOVERY_EVIDENCE.json', seal['files'])
        g.policy_ok(h, self.root)
        self.manifest['classification'] = 'tampered'
        self.save_manifest()
        with self.assertRaises(h.HarnessError):
            g.policy_ok(h, self.root)

    def test_without_manifest_no_exemption(self):
        (self.root / h.H / 'RECOVERY_EVIDENCE.json').unlink()
        self.rejected()


if __name__ == '__main__':
    unittest.main(verbosity=2)
