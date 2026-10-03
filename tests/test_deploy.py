import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / 'scripts/deploy.py'
spec = importlib.util.spec_from_file_location('deploy', MODULE_PATH)
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True, stderr=subprocess.DEVNULL).strip()


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.root = self.base / 'production'
        self.state = self.base / 'state'
        self.config = self.base / 'config'
        self.state.mkdir()
        self.config.mkdir()
        (self.repo / 'deploy/adapters').mkdir(parents=True)
        (self.repo / 'scripts').mkdir()
        (self.repo / 'scripts/deploy.py').write_text('driver')
        (self.repo / 'deploy/adapters/common.sh').write_text('common')
        self.apps = {'api': {'depends_on': []}, 'bridge': {'depends_on': ['api']}, 'other': {'depends_on': []}}
        (self.repo / 'apps.json').write_text(json.dumps(self.apps))
        for name in self.apps:
            source = self.repo / 'apps' / name
            source.mkdir(parents=True)
            git(source, 'init', '-b', 'main')
            git(source, 'config', 'user.name', 'Test')
            git(source, 'config', 'user.email', 'test@example.invalid')
            git(source, 'remote', 'add', 'origin', str(source))
            (source / 'file.txt').write_text('initial')
            git(source, 'add', '.')
            git(source, 'commit', '-m', 'initial')
            (self.repo / 'deploy/adapters' / f'{name}.sh').write_text(
                'set -eu\n'
                'if [ -f "$VPS_CONFIG_DIR/$APP_NAME.fail" ]; then exit 1; fi\n'
                'printf "%s\\n" "$APP_REVISION" >> "$APP_DIR/deployments.log"\n'
            )
            # Deployment artifacts and application runtime settings are untracked.
            (source / '.gitignore').write_text('deployments.log\n.env\n')
            git(source, 'add', '.gitignore')
            git(source, 'commit', '-m', 'ignore runtime files')

    def run_deploy(self, **kwargs):
        return deploy.deploy(self.repo, self.root, self.state, self.config, **kwargs)

    def count(self, name):
        path = self.root / name / 'deployments.log'
        return len(path.read_text().splitlines()) if path.exists() else 0

    def change_upstream(self, name):
        source = self.repo / 'apps' / name
        (source / 'file.txt').write_text('changed')
        git(source, 'add', 'file.txt')
        git(source, 'commit', '-m', 'change upstream')
        return git(source, 'rev-parse', 'HEAD')

    def test_updates_only_app_and_consumers_with_exact_revisions(self):
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual([self.count(x) for x in self.apps], [1, 1, 1])
        sha = self.change_upstream('api')
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual([self.count(x) for x in self.apps], [2, 2, 1])
        self.assertEqual(git(self.root / 'api', 'rev-parse', 'HEAD'), sha)
        self.assertTrue((self.root / 'api/.git').is_dir())

    def test_failure_retries_and_blocks_consumers_but_not_other_apps(self):
        marker = self.config / 'api.fail'
        marker.touch()
        self.assertEqual(self.run_deploy(), 1)
        recorded = json.loads((self.state / 'deployed.json').read_text())
        self.assertEqual(set(recorded), {'other'})
        marker.unlink()
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual([self.count(x) for x in self.apps], [1, 1, 1])

    def test_config_and_adapter_changes_redeploy_only_affected_app(self):
        self.assertEqual(self.run_deploy(), 0)
        (self.config / 'other.sh').write_text('PORT=42\n')
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual([self.count(x) for x in self.apps], [1, 1, 2])
        adapter = self.repo / 'deploy/adapters/bridge.sh'
        adapter.write_text(adapter.read_text() + '# changed setup\n')
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual([self.count(x) for x in self.apps], [1, 2, 2])

    def test_force_single_app_includes_consumers_without_forcing_prerequisites(self):
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual(self.run_deploy(selected='bridge', force=True), 0)
        self.assertEqual([self.count(x) for x in self.apps], [1, 2, 1])
        self.assertEqual(self.run_deploy(selected='api', force=True), 0)
        self.assertEqual([self.count(x) for x in self.apps], [2, 3, 1])

    def test_dry_run_does_not_create_deployments_or_state(self):
        self.assertEqual(self.run_deploy(dry_run=True), 0)
        self.assertFalse(self.root.exists())
        self.assertFalse((self.state / 'deployed.json').exists())

    def test_refuses_dirty_production_checkout_and_preserves_changes(self):
        self.assertEqual(self.run_deploy(), 0)
        file = self.root / 'api/file.txt'
        file.write_text('uncommitted wiki-style changes')
        self.change_upstream('api')
        self.assertEqual(self.run_deploy(), 1)
        self.assertEqual(file.read_text(), 'uncommitted wiki-style changes')
        self.assertEqual(self.count('api'), 1)

    def test_refuses_to_discard_local_commits(self):
        self.assertEqual(self.run_deploy(), 0)
        target = self.root / 'api'
        git(target, 'config', 'user.name', 'Test')
        git(target, 'config', 'user.email', 'test@example.invalid')
        (target / 'file.txt').write_text('local commit')
        git(target, 'add', 'file.txt')
        git(target, 'commit', '-m', 'unpublished local commit')
        head = git(target, 'rev-parse', 'HEAD')
        self.change_upstream('api')
        self.assertEqual(self.run_deploy(), 1)
        self.assertEqual(git(target, 'rev-parse', 'HEAD'), head)

    def test_missing_checkout_is_recreated_even_if_state_matches(self):
        self.assertEqual(self.run_deploy(), 0)
        import shutil
        shutil.rmtree(self.root / 'other')
        self.assertEqual(self.run_deploy(), 0)
        self.assertEqual(self.count('other'), 1)

    def test_registry_rejects_unknown_apps_and_invalid_dependency_order(self):
        with self.assertRaises(ValueError):
            self.run_deploy(selected='not-present')
        (self.repo / 'apps.json').write_text(json.dumps({'bridge': {'depends_on': ['api']}}))
        with self.assertRaises(ValueError):
            deploy.load_apps(self.repo)


class SubmoduleSyncTests(unittest.TestCase):
    def test_sync_records_changed_branch_head(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            upstream = base / 'upstream'
            parent = base / 'parent'
            upstream.mkdir()
            parent.mkdir()
            for path in [upstream, parent]:
                git(path, 'init', '-b', 'main')
                git(path, 'config', 'user.name', 'Test')
                git(path, 'config', 'user.email', 'test@example.invalid')
            (upstream / 'file').write_text('one')
            git(upstream, 'add', '.')
            git(upstream, 'commit', '-m', 'one')
            git(parent, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-b', 'main', str(upstream), 'apps/test')
            (parent / 'scripts').mkdir()
            script = Path(__file__).resolve().parents[1] / 'scripts/sync-submodules.sh'
            (parent / 'scripts/sync-submodules.sh').write_text(script.read_text())
            git(parent, 'add', '.')
            git(parent, 'commit', '-m', 'initial')
            (upstream / 'file').write_text('two')
            git(upstream, 'add', '.')
            git(upstream, 'commit', '-m', 'two')
            env = dict(os.environ, GIT_ALLOW_PROTOCOL='file')
            subprocess.run(['bash', str(parent / 'scripts/sync-submodules.sh')], env=env, check=True, stdout=subprocess.DEVNULL)
            expected = git(upstream, 'rev-parse', 'HEAD')
            self.assertEqual(git(parent / 'apps/test', 'rev-parse', 'HEAD'), expected)
            self.assertEqual(git(parent, 'rev-parse', ':apps/test'), expected)


if __name__ == '__main__':
    unittest.main()
