import os
from pathlib import Path
import subprocess
import tempfile
import unittest


IMAGE = os.environ.get("RUNTIME_TEST_IMAGE", "mikaeluman/datascience:latest")
ENTRYPOINT = os.environ.get("RUNTIME_TEST_ENTRYPOINT")


def run_container(command, *options):
    entrypoint_options = (
        ["--mount", f"type=bind,source={Path(ENTRYPOINT).resolve()},target=/usr/local/bin/entrypoint.sh,readonly",
         "--entrypoint", "/usr/local/bin/entrypoint.sh"]
        if ENTRYPOINT else []
    )
    return subprocess.run(
        [
            "docker", "run", "--rm", "--workdir", "/tmp",
            *entrypoint_options,
            *options, IMAGE, "bash", "-ec", command,
        ],
        capture_output=True, text=True, timeout=120,
    )


def account_options(name="analyst", uid=2001, gid=2002):
    return (
        "--user", "root", "--env", f"CONTAINER_USER={name}",
        "--env", f"CONTAINER_UID={uid}", "--env", f"CONTAINER_GID={gid}",
    )


class RuntimeUserTests(unittest.TestCase):
    def test_default_account_remains_ubuntu(self):
        result = run_container('printf "%s:%s:%s" "$(id -un)" "$(id -u)" "$HOME"')

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ubuntu:1000:/home/ubuntu")

    def test_runtime_identity_matches_account_and_home(self):
        for name, uid, gid in [("analyst", 1000, 1000), ("researcher", 2001, 2002)]:
            with self.subTest(name=name):
                result = run_container(
                    'printf "%s:%s:%s:%s:%s:%s" "$(id -un)" "$(id -u)" "$(id -g)" '
                    '"$HOME" "$USER" "$(getent passwd "$(id -u)" | cut -d: -f6)"; '
                    'touch "$HOME/writable"; sudo -n true',
                    *account_options(name, uid, gid),
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, f"{name}:{uid}:{gid}:/home/{name}:{name}:/home/{name}")

    def test_existing_identity_can_initialize_again(self):
        result = run_container(
            """sudo -E /usr/local/bin/entrypoint.sh bash -c 'printf "%s:%s" "$(id -un)" "$HOME"'""",
            *account_options(),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "analyst:/home/analyst")

    def test_mounted_files_keep_their_content_and_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            path.chmod(0o755)
            marker = path / "marker"
            marker.write_text("host content")
            original = (marker.stat().st_uid, marker.stat().st_gid, marker.stat().st_mode)

            result = run_container(
                'cat "$HOME/project [one]*?/marker"; test -w "$HOME"; '
                'test -f "$HOME/.bashrc"',
                *account_options(),
                "--mount", f"type=bind,source={path},target=/home/analyst/project [one]*?",
                "--mount", f"type=bind,source={marker},target=/home/analyst/.config/example/settings",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "host content")
            self.assertEqual(marker.read_text(), "host content")
            self.assertEqual((marker.stat().st_uid, marker.stat().st_gid, marker.stat().st_mode), original)

    def test_installed_commands_can_be_replaced_by_the_runtime_user(self):
        result = run_container(
            """sudo install -d -o root -g root /opt/devtools /opt/devtools/bin
printf '#!/bin/sh\\necho before\\n' | sudo tee /opt/devtools/bin/runtime-user-fixture >/dev/null
sudo chmod 755 /opt/devtools/bin/runtime-user-fixture
sudo -E /usr/local/bin/entrypoint.sh bash -ec '
  test "$(runtime-user-fixture)" = before
  printf "#!/bin/sh\\necho after\\n" > "$HOME/.local/bin/runtime-user-fixture.new"
  chmod 755 "$HOME/.local/bin/runtime-user-fixture.new"
  mv "$HOME/.local/bin/runtime-user-fixture.new" "$HOME/.local/bin/runtime-user-fixture"
  runtime-user-fixture
'""",
            *account_options(),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "after\n")

    def test_account_conflicts_fail_before_running_the_command(self):
        result = run_container('echo command-ran', *account_options("nobody"))

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("account conflict", result.stderr)
        self.assertNotIn("command-ran", result.stdout)

    def test_unprivileged_identity_change_fails_clearly(self):
        result = run_container('echo command-ran', "--env", "CONTAINER_USER=analyst")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires --user root", result.stderr)
        self.assertNotIn("command-ran", result.stdout)

    def test_invalid_home_is_rejected_before_account_changes(self):
        result = run_container(
            'echo command-ran', *account_options(),
            "--env", "CONTAINER_HOME=/home/analyst/../../etc",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("canonical path beneath /home", result.stderr)
        self.assertNotIn("command-ran", result.stdout)

    def test_whole_home_mount_is_rejected_without_changing_the_host(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            original = (path.stat().st_uid, path.stat().st_gid)

            result = run_container(
                'echo command-ran', *account_options(),
                "--mount", f"type=bind,source={path},target=/home/analyst",
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("mount individual home subdirectories", result.stderr)
            self.assertEqual((path.stat().st_uid, path.stat().st_gid), original)
            self.assertEqual(list(path.iterdir()), [])

    def test_exit_status_is_preserved(self):
        result = run_container('exit 37', *account_options())

        self.assertEqual(result.returncode, 37, result.stderr)

    def test_command_receives_termination_signal(self):
        result = run_container("test $$ = 1; trap 'exit 42' TERM; kill -TERM $$; exit 1", *account_options())

        self.assertEqual(result.returncode, 42, result.stderr)


if __name__ == "__main__":
    unittest.main()
