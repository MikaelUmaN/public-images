---
name: image-builds
description: Builds this repository's Docker images in dependency order, locally under a disk guard or on GitHub Actions, runs each image's smoke tests, diagnoses and retries failures, cleans up what it built, and asks the user when the recipe cannot be satisfied. Use when a Dockerfile changed, before publishing, or when asked to build, rebuild, test or verify an image.
user-invocable: true
argument-hint: "<image>... | all [--where local|github|auto] [--build-arg K=V]... [--expect TOOL=ver]... [--slow] [--no-downstream] [--publish] [--branch <name>]"
compatibility: docker with BuildKit, gh authenticated against the repository, tests/smoke/ in the checkout.
---

# Image builds

The skill builds and tests images. It edits no Dockerfile and no test, and commits nothing. It
returns evidence: log paths, quoted failure lines, smoke counts, disk before and after. A build
that cannot be made to pass returns a diagnosis and a question, never a weakened recipe. Scripts
live in `scripts/`; image facts in `references/images.md`.

## Parse

`$ARGUMENTS` names one or more images, or `all`, followed by flags:

| Flag | Meaning |
|---|---|
| `--where local\|github\|auto` | where to build; default `auto` |
| `--build-arg K=V` | trial value for an `ARG`, passed to `docker build`; the Dockerfile stays as it is |
| `--expect TOOL=ver` | asserted in the smoke run through `EXPECT_<TOOL>` |
| `--slow` | run the `SMOKE_SLOW` checks (datascience, quarto-datascience) |
| `--no-downstream` | build only the named images |
| `--publish` | allow the GitHub build to push to Docker Hub; without it CI runs with `push=false` |
| `--branch <name>` | branch for GitHub builds; default the current branch |
| `--start-script <path>` | a docker start script the built images have to stay compatible with; without it a standalone run asks once |

`all` is the chain plus `latex` and `pico`. A named chain member brings every image after it
unless `--no-downstream` is given.

## Images

`references/images.md` holds the chain, budgets, sizes and per-image test facts. Two rules
shape every run: the chain `datascience → rust-datascience → net-datascience → quarto-datascience`
builds in order, and on GitHub each link pulls its base `:latest` from Docker Hub, so a CI
chain is serial and a base has to be published before the next link is dispatched. `latex` and
`pico` stand alone.

## Disk first

Before anything else the skill runs and prints `df -h /` and `docker system df`. A build starts
only when free space minus 100 GB covers the image's published size; otherwise the cleanup below
runs first, and a shortfall that remains goes to the user with the numbers. The build cache is
never pruned wholesale: it holds the apt cache mounts.

Cleanup, in order and always reported:

- before a build, record the id its `:latest` tag will replace: `docker image inspect --format '{{.Id}}' mikaeluman/<img>:latest`
- between chain steps, `docker image prune -f` (dangling layers only)
- after an image's smoke run passes, `docker rmi <replaced id>` unless another tag or a container still holds it
- at the end, `docker rmi` every image pulled for verification
- free space printed again

## Choose where

`--where auto` picks local when free space covers the cold budget, no other `docker build` is
running (`docker ps --filter ancestor=moby/buildkit` and `pgrep -f 'docker build'`), and no
download stall has been seen in this session. It picks GitHub when any of those fails, when a
local build has hit a transient failure twice, or when the caller asks. A GitHub build needs
the tree committed and pushed on `--branch`; a dirty tree or an unpushed branch is refused
with the `git status --short` output, never dispatched around.

## Build locally

```
IMAGE_BUILDS_LOG_DIR=<scratch> scripts/guarded-build.sh <image> <n> [--build-arg K=V ...]
```

runs in the background, since a cold chain build exceeds the ten-minute foreground cap, and is
polled with `grep -E '^#[0-9]+ (DONE|ERROR)' <log> | tail`. `<n>` increments per attempt so
logs are kept. The trailer line `BUILD <image> rc=<n> elapsed=<m>min final_avail=<g>G` is the
build's verdict. Trial ARG values go in as `--build-arg`; whether to edit the Dockerfile
afterwards is the caller's decision, and a confirming cached build follows an edit.

## Build on GitHub

```
gh workflow run datascience.yml --ref <branch> -f image=<image> -f push=<true|false>
gh run list --workflow datascience.yml --branch <branch> --limit 1 --json databaseId --jq '.[0].databaseId'
scripts/gh-poll.sh <run-id>
```

`gh-poll.sh` waits for completion and prints the conclusion plus the image the run built, read
from the log's `--file <image>.docker` line (the log is not available before completion). A
failed run is read with `gh run view <run-id> --log-failed`. A run whose base is about to be
rebuilt is cancelled with `gh run cancel <run-id>` and dispatched again after the base is
published. `gh run watch` is not used: it exits on a network blip.

## Test

```
scripts/smoke.sh <image> [--expect TOOL=ver]... [--slow] [--perf] [--sandbox] [--tag <tag>]
```

- plain: every check the script holds, versions confirmed to run
- `--expect` for every pin the caller moved, so the run proves the pin landed
- `--slow` once per chain for datascience and quarto-datascience
- `--perf` when the host has `/usr/local/bin/perf`
- `--sandbox` for datascience after a Codex or bubblewrap change

A published image is verified by `docker pull mikaeluman/<image>:latest`, the same forms, then
`docker rmi`. An ad hoc probe of a built image is `docker run --rm mikaeluman/<image>:latest <cmd>`;
`ldd`, `cargo tree` and `uv tree` run this way.

## Start script

Images are run through start scripts outside the repository (`~/run-science.sh` is one), and a
rebuilt image can break their assumptions. `--start-script <path>` names one. Without it a
standalone run asks once, header "Start script": "Is there a docker start script the rebuilt
images should be checked against?", offering every `~/run-*.sh` found on the host, "None", or a
path. The skill reads the script and checks it against every built image it can select:

| Check | How | Finding when it fails |
|---|---|---|
| image reference | the `--image` default and every literal `mikaeluman/<img>:<tag>` name an image and tag the build produced | the script targets an image or tag that does not exist |
| user | the `--user` uid:gid against `id ubuntu` inside the image | files created through mounts get another owner |
| mount sources | every host path the script mounts exists; a default derived from `$PWD` is flagged | docker creates a missing source as a root-owned directory |
| mount targets | `ls -A <target>` inside the image for every bind target; a non-empty target is shadowed by the mount, cache directories excepted | image-shipped config or tools vanish behind the mount |
| runtime requirements | the flags the image's tools need, from `references/images.md`: `--shm-size` for headed Chrome, `--security-opt seccomp=unconfined` for bubblewrap, the perf mount with its capabilities, the WSLg env and sockets | a tool warns or fails at run time |
| dry run | `script -qec "<script> -- --entrypoint /bin/true" /dev/null` (a pseudo-tty satisfies `-it`) | the script's own `docker run` fails before any command |

Credential directories the script mounts (`.ssh`, `.aws`, `.kube`, `.gnupg`) are never named in
a command the skill runs: the local secret-file guard blocks such commands, and no check needs
their contents. Findings go in the report; the skill edits no script, and a mismatch that
needs a script change is put to the user with the exact line.

## Diagnose

A failed build or smoke run is classified from its log before anything is retried:

| Class | Log signature | Action |
|---|---|---|
| transient network | `curl: (56) Recv failure`, `Connection timed out`, `Couldn't connect to server`, apt `Failed to fetch`, `Temporary failure resolving` | retry once; a second occurrence switches the run to GitHub |
| disk guard | `DISK GUARD:` in the build log | run the cleanup, report the numbers, no retry until space is freed |
| recipe | `404` on a release asset, `sha256sum: WARNING`, `checksum` or `signature` mismatch, `error: could not find`, `error: package … not found`, `rust-version`/MSRV errors, `E: Unable to locate package`, a `RUN … \| grep -F` assertion failing, `quarto check` failing | quote the line, name the Dockerfile site (`file:line`), return to the caller; standalone, ask |
| smoke | `FAIL <check>` lines | rerun the failing command by hand in the image to separate a check defect from an image defect; report which |

Known trap: a `RUN` that chains `a && b || { echo "mismatch"; exit 1; }` prints the `||`
message whenever any earlier command in the chain fails, so a "fingerprint mismatch" after a
failed `curl` is the curl failure, not the fingerprint.

## Ask the user

One AskUserQuestion, header "Recipe", when a recipe failure has no fix within the skill's
remit. The question quotes the log line and names the site. Options: "Retry on GitHub" (for a
failure that may be local), "Skip <image>, continue the rest", "Stop; the user investigates",
plus any concrete remedy the diagnosis found (a renamed asset, a package moved to another
repository). A disk shortfall the cleanup cannot cover asks with free space, the budget and
what could be removed.

## Report

```
## image-builds: <images>
Where: local | github (<branch>, push=<true|false>) · Disk: <free before> -> <free after>

| image | build | minutes | smoke | expects asserted | log |
|---|---|---|---|---|---|

### Failures
- <image>: <class> — "<quoted line>" (<file:line>) — <action taken>

### Cleanup
- removed <ids>; pulled and removed <images>; pruned <size>

### Start script: <path | none>
| check | result | evidence |
|---|---|---|

### Ask the user
```
