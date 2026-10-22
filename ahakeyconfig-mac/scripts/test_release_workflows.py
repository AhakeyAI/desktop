"""Execute the actual YAML guard scripts against isolated, offline API fixtures."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


class ReleaseWorkflowTests(unittest.TestCase):
    def workflow(self, name):
        path = pathlib.Path(__file__).resolve().parents[2] / ".github/workflows" / name
        return json.loads(subprocess.check_output(["ruby", "-rjson", "-ryaml", "-e",
            "puts JSON.generate(YAML.load_file(ARGV[0]))", str(path)]))

    def testStableAndPrereleaseUseTheSameNumericBundleAndCatalogVersion(self):
        build = self.workflow("release.yml")
        build_script = next(step["run"] for step in build["jobs"]["build-and-release"]["steps"] if step.get("id") == "version")
        promotion = self.workflow("promote-verified-release.yml")
        guard = next(step["with"]["script"] for step in promotion["jobs"]["verify-and-draft"]["steps"] if step.get("id") == "provenance")
        for tag in ["v0.2.3", "v0.2.3-beta1", "v0.2.3-rc.2"]:
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory) / "output"
                env = dict(os.environ, GITHUB_REF_NAME=tag, GITHUB_OUTPUT=str(output))
                subprocess.run(["bash", "-euo", "pipefail", "-c", build_script], env=env, check=True, capture_output=True)
                self.assertEqual(output.read_text(), "version=0.2.3\n")
                response = self.run_provenance(guard, tag)
                self.assertEqual(response.returncode, 0, response.stderr)
                self.assertEqual(json.loads(response.stdout)["version"], "0.2.3")

    def run_provenance(self, script, tag="v0.2.3", bad=False):
        harness = """
        const outputs = {};
        const sha = 'a'.repeat(40);
        const context = {repo: {owner: 'AhakeyAI', repo: 'desktop'}};
        const core = {setOutput: (k, v) => outputs[k] = v};
        const github = {rest: {
          actions: {
            getWorkflowRun: async () => ({data: {status: 'completed', conclusion: 'success', event: 'push',
              head_repository: {full_name: 'AhakeyAI/desktop'}, head_sha: sha}}),
            getArtifact: async () => ({data: {expired: false, workflow_run: {id: 123,
              head_sha: process.env.BAD_ARTIFACT === '1' ? 'b'.repeat(40) : sha}}})
          }, repos: {getCommit: async () => ({data: {sha}})}
        }};
        const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
        new AsyncFunction('github', 'context', 'core', process.env.GUARD_SCRIPT)(github, context, core)
          .then(() => process.stdout.write(JSON.stringify(outputs)))
          .catch(error => {process.stderr.write(error.message); process.exitCode = 1;});
        """
        return subprocess.run(["node", "-e", harness], env=dict(os.environ,
            RELEASE_TAG=tag, SOURCE_RUN_ID="123", SOURCE_ARTIFACT_ID="456",
            GUARD_SCRIPT=script, BAD_ARTIFACT="1" if bad else "0"), capture_output=True, text=True)

    def testDifferentArtifactSourceAndUnsafeTagCannotPassActualGuard(self):
        workflow = self.workflow("promote-verified-release.yml")
        guard = next(step["with"]["script"] for step in workflow["jobs"]["verify-and-draft"]["steps"] if step.get("id") == "provenance")
        self.assertNotEqual(self.run_provenance(guard, bad=True).returncode, 0)
        self.assertNotEqual(self.run_provenance(guard, tag="v0.2.3;echo injected").returncode, 0)

    def testTagBuildCannotPublishAndPromotionOnlyCreatesDraft(self):
        build = self.workflow("release.yml")
        self.assertEqual(build["permissions"]["contents"], "read")
        self.assertFalse(any("action-gh-release" in step.get("uses", "") for step in build["jobs"]["build-and-release"]["steps"]))
        promotion = self.workflow("promote-verified-release.yml")
        job = promotion["jobs"]["verify-and-draft"]
        self.assertEqual(job["environment"], "ws5-release")
        publish = job["steps"][-1]["run"]
        self.assertIn("--draft", publish)
        self.assertIn('"$VERIFIED_INSTALLER"', publish)


if __name__ == "__main__":
    unittest.main()
