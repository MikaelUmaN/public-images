import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / 'scripts/run-science.sh'


def values(arguments, option):
    return [arguments[index + 1] for index, argument in enumerate(arguments[:-1]) if argument == option]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='.launcher-test-', dir=ROOT)
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.project = self.home / 'project with spaces'
        self.project.mkdir()
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.calls = self.home / 'docker-calls'
        docker = self.bin / 'docker'
        docker.write_text(
            f'#!{sys.executable}\n'
            'import json, os, pathlib, sys\n'
            'with pathlib.Path(os.environ["DOCKER_CALLS"]).open("a") as output:\n'
            '    output.write(json.dumps(sys.argv[1:]) + "\\n")\n'
            'if sys.argv[1] == "image": print(os.environ.get("RUNTIME_LABEL", "1"))\n'
            'else: print(json.dumps(sys.argv[1:]))\n'
        )
        docker.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if key not in {'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'DISPLAY', 'WAYLAND_DISPLAY'}}
        self.env.update(HOME=str(self.home), PATH=f'{self.bin}:{os.environ["PATH"]}',
                        DOCKER_CALLS=str(self.calls))

    def run_launcher(self, *arguments, dry=True, env=None):
        return subprocess.run(
            [str(LAUNCHER), *arguments, *(['--dry-run'] if dry else [])],
            cwd=self.project, env=self.env | (env or {}), capture_output=True, text=True, timeout=15,
        )

    def command(self, *arguments, **kwargs):
        result = self.run_launcher(*arguments, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        return shlex.split(result.stdout)

    def test_default_only_mounts_current_project(self):
        (self.home / '.codex').mkdir()
        (self.home / 'data').mkdir()

        command = self.command()

        self.assertEqual(values(command, '--mount'),
                         [f'type=bind,source={self.project},target={self.project}'])
        self.assertEqual(values(command, '--network'), ['bridge'])
        self.assertEqual(values(command, '--workdir'), [str(self.project)])
        self.assertEqual(command[-1], 'mikaeluman/rust-datascience:latest')
        self.assertNotIn('--tmpfs', command)
        self.assertNotIn('--shm-size=1g', command)
        self.assertIn('--rm', command)
        self.assertFalse(self.calls.exists())

    def test_preset_shares_available_resources_and_isolates_ai_state(self):
        for directory in ['dev', 'data', '.codex', '.claude', '.config/git', '.config/uv',
                          '.cargo/registry', '.cargo/git', '.bun/install/cache', '.nuget/packages']:
            (self.home / directory).mkdir(parents=True)

        command = self.command('--preset', 'defaults')

        mounts = values(command, '--mount')
        self.assertEqual(values(command, '--network'), ['host'])
        self.assertEqual(values(command, '--workdir'), [str(self.home / 'dev')])
        self.assertIn(f'type=bind,source={self.home}/data,target={self.home}/data', mounts)
        self.assertIn(f'type=bind,source={self.home}/.config/git,target={self.home}/.config/git', mounts)
        self.assertIn(f'type=bind,source={self.home}/.cargo/registry,target=/opt/devtools/cargo/registry', mounts)
        self.assertEqual(len(values(command, '--tmpfs')), 10)
        self.assertFalse((self.home / '.codex/packages').exists())
        self.assertFalse(self.calls.exists())

    def test_explicit_options_override_preset_in_either_order(self):
        (self.home / 'data').mkdir()
        (self.home / '.codex').mkdir()
        overrides = ['--project-dir', str(self.project), '--network', 'none', '--no-data',
                     '--no-share', 'ai', '--no-gui']

        first = self.command('--preset', 'defaults', *overrides)
        last = self.command(*overrides, '--preset', 'defaults')

        self.assertEqual(first, last)
        self.assertEqual(values(first, '--network'), ['none'])
        self.assertEqual(values(first, '--mount'),
                         [f'type=bind,source={self.project},target={self.project}'])
        self.assertNotIn('--tmpfs', first)

    def test_last_explicit_sharing_selection_wins(self):
        (self.home / '.codex').mkdir()

        command = self.command('--share', 'ai', '--no-share', 'ai', '--share', 'ai')

        self.assertIn(f'CODEX_HOME={self.home}/.codex', values(command, '--env'))
        self.assertEqual(len(values(command, '--tmpfs')), 7)

    def test_each_group_selects_only_its_resources(self):
        resources = {'ai': '.codex', 'git': '.config/git', 'cloud': '.kube',
                     'shell': '.config/uv', 'caches': '.nuget/packages'}
        for path in resources.values():
            (self.home / path).mkdir(parents=True)

        commands = {group: self.command('--share', group) for group in resources}

        for group, command in commands.items():
            with self.subTest(group=group):
                self.assertEqual(values(command, '--mount'), [
                    f'type=bind,source={self.project},target={self.project}',
                    f'type=bind,source={self.home}/{resources[group]},target={self.home}/{resources[group]}',
                ])

    def test_optional_missing_resources_are_skipped(self):
        (self.home / 'dev').mkdir()

        command = self.command('--preset', 'defaults')

        self.assertEqual(values(command, '--mount'),
                         [f'type=bind,source={self.home}/dev,target={self.home}/dev'])
        self.assertNotIn('--tmpfs', command)

    def test_explicit_missing_paths_fail_before_docker(self):
        for flag in ['--project-dir', '--data-dir', '--volume']:
            with self.subTest(flag=flag):
                missing = str(self.home / 'absent') + (':/data' if flag == '--volume' else '')

                result = self.run_launcher(flag, missing, dry=False)

                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.calls.exists())

    def test_nested_project_and_data_use_one_mount(self):
        child = self.project / 'nested'
        child.mkdir()

        commands = [self.command('--data-dir', str(child)),
                    self.command('--project-dir', str(child), '--data-dir', str(self.project))]

        for command in commands:
            self.assertEqual(values(command, '--mount'),
                             [f'type=bind,source={self.project},target={self.project}'])

    def test_whole_home_and_parent_mounts_are_rejected(self):
        for target in [self.home, self.home.parent, Path('/')]:
            with self.subTest(target=target):
                result = self.run_launcher('--volume', f'{self.project}:{target}', dry=False)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn('home or its parents', result.stderr)
                self.assertFalse(self.calls.exists())

    def test_duplicate_targets_are_rejected(self):
        result = self.run_launcher('--volume', f'{self.project}:{self.project}', dry=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Duplicate mount target', result.stderr)
        self.assertFalse(self.calls.exists())

    def test_custom_ai_directories_keep_host_paths(self):
        claude = self.home / 'claude config'
        codex = self.home / 'codex config'
        claude.mkdir()
        codex.mkdir()

        command = self.command('--share', 'ai', env={'CLAUDE_CONFIG_DIR': str(claude), 'CODEX_HOME': str(codex)})

        self.assertIn(f'type=bind,source={claude},target={claude}', values(command, '--mount'))
        self.assertIn(f'CLAUDE_CONFIG_DIR={claude}', values(command, '--env'))
        self.assertIn(f'CODEX_HOME={codex}', values(command, '--env'))
        self.assertTrue(any(value.startswith(f'{codex}/packages:') for value in values(command, '--tmpfs')))

    def test_legacy_claude_state_requires_explicit_migration(self):
        legacy = self.home / '.claude.json'
        legacy.write_text('{}')

        result = self.run_launcher('--share', 'ai', dry=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('migrate', result.stderr)
        self.assertEqual(legacy.read_text(), '{}')
        self.assertFalse(self.calls.exists())

    def test_runtime_state_is_created_only_after_image_validation(self):
        (self.home / '.codex').mkdir()

        result = self.run_launcher('--share', 'ai', dry=False, env={'RUNTIME_LABEL': '0'})

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((self.home / '.codex').iterdir()), [])
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)

    def test_launch_preserves_arguments_and_creates_user_owned_state(self):
        (self.home / '.codex').mkdir()

        result = self.run_launcher('--share', 'ai', '--name', 'test-launch', '--env', 'LABEL=two words', dry=False)

        self.assertEqual(result.returncode, 0, result.stderr)
        command = json.loads(result.stdout)
        self.assertEqual(values(command, '--name'), ['test-launch'])
        self.assertIn('LABEL=two words', values(command, '--env'))
        self.assertNotIn('--rm', command)
        state = self.home / '.codex/packages'
        self.assertEqual(state.stat().st_uid, os.getuid())
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)

    def test_invalid_options_fail_clearly(self):
        for arguments in [('--share', 'unknown'), ('--preset', 'unknown'), ('--unknown',), ('--image',)]:
            with self.subTest(arguments=arguments):
                result = self.run_launcher(*arguments, dry=False)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Error:', result.stderr)
                self.assertFalse(self.calls.exists())

    def test_requested_gui_requires_wslg(self):
        result = self.run_launcher('--gui', dry=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('WSLg', result.stderr)
        self.assertFalse(self.calls.exists())

    def test_perf_is_resolved_from_path(self):
        perf = self.bin / 'perf'
        perf.write_text('#!/bin/sh\nexit 0\n')
        perf.chmod(0o755)

        command = self.command('--perf', '--perfmon')

        self.assertIn(f'type=bind,source={perf},target=/usr/bin/perf,readonly', values(command, '--mount'))
        self.assertEqual(values(command, '--cap-add'), ['PERFMON'])

    def test_docker_escape_hatch_preserves_separate_arguments(self):
        result = self.run_launcher('--dry-run', '--', '--publish', '8888:8888',
                                   '--label', 'description=two words', dry=False)

        self.assertEqual(result.returncode, 0, result.stderr)
        command = shlex.split(result.stdout)
        self.assertEqual(command[-5:], ['--publish', '8888:8888', '--label',
                                        'description=two words', 'mikaeluman/rust-datascience:latest'])
        self.assertFalse(self.calls.exists())

    def test_runtime_state_symlinks_are_rejected(self):
        (self.home / '.codex').mkdir()
        (self.home / '.codex/packages').symlink_to(self.project)

        result = self.run_launcher('--share', 'ai', dry=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('symlink', result.stderr)
        self.assertFalse(self.calls.exists())


if __name__ == '__main__':
    unittest.main()
