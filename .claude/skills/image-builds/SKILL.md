---
name: image-builds
description: Builds this repository's Docker images in dependency order and only the images a change touches, locally under a disk guard or on GitHub Actions; runs the smoke tests at the level the change deserves; diagnoses and retries failures; leaves nothing behind and proves it; asks the user when the recipe cannot be satisfied. Use when a Dockerfile changed, before publishing, or when asked to build, rebuild, test or verify an image.
user-invocable: true
argument-hint: "<image>... | all [--scope auto|named|downstream] [--test auto|none|smoke|full] [--since <ref>] [--where local|github|auto] [--build-arg K=V]... [--expect TOOL=ver]... [--publish] [--branch <name>] [--start-script <path>]"
compatibility: docker with BuildKit, gh authenticated against the repository, tests/smoke/ in the checkout.
---

# Image builds

The skill builds and tests images. It edits no Dockerfile, no test and no start script, and
commits nothing. It returns evidence: log paths, quoted failure lines, smoke counts, disk before
and after, and a Left-behind line that reads `nothing` or names every object it could not
remove. A build that cannot be made to pass returns a diagnosis, never a weakened recipe.
Scripts live in `scripts/`, image facts in `references/images.md`.

## Parse

| Flag | Meaning |
|---|---|
| `--scope auto\|named\|downstream` | images built beyond the named ones: `named` none; `downstream` every chain image after a built one; `auto` a downstream image whose Dockerfile names a moved ARG, and every downstream image under `--publish`; default `auto` |
| `--test auto\|none\|smoke\|full` | test level for every image in the run; `auto` follows the change kind; default `auto` |
| `--since <ref>` | git reference for the change set; default per image the newest commit not after its local `:latest` was created |
| `--where local\|github\|auto` | default `auto` |
| `--build-arg K=V` | trial value for an ARG; counts as a `pins` change to the named image; the Dockerfile stays as it is |
| `--expect TOOL=ver` | asserted through `EXPECT_<TOOL>`; a moved `ARG <X>_VERSION` whose smoke script has `version_check <x>` is asserted without being named |
| `--publish` | the GitHub build pushes (`push=true`); without it `push=false` |
| `--branch <name>` | branch for GitHub builds; default the current branch |
| `--start-script <path>` | a docker start script the built images have to satisfy; without it a standalone run asks once |

`all` names the six images.

## Scope

`scripts/scope.sh [--since <ref>] [--build-arg K=V]... [image...]` prints one line per image:
state (`unbuilt`, `unchanged`, `tests-only`, `changed`, `downstream-of:<base>`), kind, base,
changed files and moved ARGs. A named image builds when `unbuilt` or `changed`; `tests-only`
runs the smoke on the existing image; `unchanged` runs nothing unless `--test` is given.

A base build's id decides downstream. Equal to the previous `:latest` id, every downstream layer
is still valid and nothing downstream builds. A new id invalidates every downstream layer, so a
downstream rebuild is cold apart from the cache mounts (budgets in `references/images.md`);
`--scope` decides which build now, the rest go under Not rebuilt with their cold budget. An
image id that already passed a smoke run in the session is not tested again.

| Kind | Changed lines are | `--test auto` | Downstream under `--scope auto` |
|---|---|---|---|
| tests | under `tests/` | smoke on the existing image, no build | none |
| comment | comments only | smoke; the build is cached | none: the id is unchanged |
| pins | `ARG <NAME>_VERSION=`, a version `LABEL`, or `--build-arg` | smoke with `--expect` for every moved ARG | images whose Dockerfile names a moved ARG; the rest deferred |
| install | an apt list, `cargo install`, `uv tool install`, `bun install -g`, `dotnet tool install`, a `COPY` source | smoke | deferred |
| python-deps | `pyproject.toml`, `pytorch*.toml`, `uv python install` | full | deferred; quarto-datascience takes `full` when it builds |
| runtime | `FROM`, `ENV`, `USER`, `WORKDIR`, `ENTRYPOINT`, `CMD`, a non-version `ARG` | full | build and smoke: they inherit the surface |

`full` is smoke plus the image's flags from `references/images.md`. A mixed change takes the
highest row. A downstream image whose own inputs did not change takes `smoke`.

## Disk

`df -h /` and `docker system df` come first. A build starts only when free space minus 100 GB
covers the image's published size; otherwise the cleanup below runs, and a shortfall that
remains goes to the user with the numbers. `scripts/guarded-build.sh` kills a build under
100 GB free (`DISK GUARD:` in its log).

## Cleanup

`scripts/leftovers.sh begin <dir>` runs before the first docker command and
`scripts/leftovers.sh end <dir>` after the last, on failure too. The report's Left behind
section is its verdict: `nothing`, or one line per object with kind, owner and removal command.

| Resource | Rule |
|---|---|
| containers | every `docker run` carries `--rm`; a container present at `end` and absent at `begin` is removed and listed |
| built images | `guarded-build.sh` tags `mikaeluman/<img>:build-<n>`; a passing smoke promotes it with `docker tag` to `:latest`; `end` removes every `:build-*` tag, and the prune removes the id `:latest` held before |
| dangling layers | `docker image prune --force` at `end`, and when the disk check asks |
| build cache | never pruned wholesale: it holds the apt and cargo cache mounts, which `docker build --no-cache` also destroys. A shortfall prunes `docker buildx prune --force --filter type=regular --filter until=168h` and reports the size |
| published images | proven by the workflow's smoke step; the report quotes its `<image>: <n> ok, <m> failed` line. Never pulled: a pull moves the local `:latest` tag |
| logs | `IMAGE_BUILDS_LOG_DIR` in the session scratchpad; the report names each path |
| host paths | the bind rule below |

Bind sources. Docker creates a missing bind source as a root-owned directory, so dockerd never
sees a source the skill has not verified: the skill's own `docker run` mounts only paths it has
checked; a start script goes through `scripts/dry-run.sh`, which captures the script's
`docker run` argv through a shim, prints every source with its owner, refuses the real run on a
missing source (exit 2), and re-checks owners and containers afterwards. The skill creates no
directory and passes no directory flag; a start script runs from `$HOME`. A root-owned leftover
is a Left-behind line with its removal command, never omitted.

## Choose where

`--where auto` picks local when free space covers the cold budget, no other `docker build` runs
(`docker ps --filter ancestor=moby/buildkit`, `pgrep -f 'docker build'`) and no download stall
was seen in this session; GitHub when any of those fails, when a local build hit a transient
failure twice, or when the caller asks. A GitHub build needs the tree committed and pushed on
`--branch`; a dirty tree or an unpushed branch is refused with `git status --short`.

## Build locally

```
IMAGE_BUILDS_LOG_DIR=<scratch> scripts/guarded-build.sh <image> <n> [--build-arg K=V ...]
```

runs in the background (a cold chain build exceeds the ten-minute foreground cap), polled with
`grep -E '^#[0-9]+ (DONE|ERROR)' <log> | tail`. The trailer
`BUILD <image> rc=<n> elapsed=<m>min id=<sha> final_avail=<g>G` is the verdict; `<n>` increments
per attempt so logs are kept. The script's own exit status carries the same verdict, so it is
never piped into another command: a pipeline reports the last command's status and a failed
build then reads as a pass. `:latest` moves by
`docker tag mikaeluman/<img>:build-<n> mikaeluman/<img>:latest` after the smoke passes.

## Build on GitHub

```
gh workflow run datascience.yml --ref <branch> -f image=<image> -f push=<true|false>
gh run list --workflow datascience.yml --branch <branch> --limit 1 --json databaseId --jq '.[0].databaseId'
scripts/gh-poll.sh <run-id>
```

The run name is `<image> push=<bool>`. `gh-poll.sh` waits for completion and prints the
conclusion; a failed run is read with `gh run view <run-id> --log-failed`. Each chain link pulls
its base `:latest` from Docker Hub, so a CI chain is serial: the base run must have pushed before
the next is dispatched, and a run whose base is about to be rebuilt is cancelled
(`gh run cancel`) and dispatched again. `gh run watch` is not used: it exits on a network blip.

## Test

```
scripts/smoke.sh <image> [--tag build-<n>] [--expect TOOL=ver]... [--slow] [--perf] [--sandbox]
```

`smoke` is the plain form plus `--expect`; `full` adds the image's flags from
`references/images.md`. An ad hoc probe of a built image is
`docker run --rm mikaeluman/<image>:<tag> <cmd>` (`ldd`, `cargo tree`, `uv tree`).

## Start script

`--start-script <path>` names a docker start script the built images have to satisfy; without
it a standalone run asks once, header "Start script", offering every `~/run-*.sh` on the host,
"None", or a path. Checks against every built image the script can select:

| Check | How | Finding |
|---|---|---|
| image reference | the `--image` default and every literal `mikaeluman/<img>:<tag>` name an existing image and tag | the script targets an image or tag the build did not produce |
| user | the `--user` uid:gid against `id ubuntu` in the image | files created through mounts get another owner |
| mounts and dry run | `scripts/dry-run.sh <script>`: every bind source with existence and owner, the real run only when all exist, owners and containers re-checked after | a missing source (docker would create it root-owned) or the script's own `docker run` failing |
| mount targets | `ls -A <target>` in the image for every bind target; a non-empty target is shadowed, cache directories excepted | image-shipped config or tools vanish behind the mount |
| runtime requirements | the Runtime requirements table in `AGENTS.md` against the script's flags | a tool warns or fails at run time |

Credential directories a script mounts (`.ssh`, `.aws`, `.kube`, `.gnupg`) are never named in a
command the skill runs: the local secret-file guard blocks such commands and no check needs
their contents. A finding that needs a script change is put to the user with the exact line.

## Diagnose

| Class | Log signature | Action |
|---|---|---|
| transient network | `curl: (56) Recv failure`, `Connection timed out`, `Couldn't connect to server`, apt `Failed to fetch`, `Temporary failure resolving` | retry once; a second occurrence switches the run to GitHub |
| disk guard | `DISK GUARD:` | run the cleanup, report the numbers, no retry until space is freed |
| recipe | `404` on a release asset, `sha256sum: WARNING`, checksum or signature mismatch, `error: could not find`, `error: package … not found`, MSRV errors, `E: Unable to locate package`, a `RUN … \| grep -F` assertion, `quarto check` | quote the line, name the Dockerfile site, return to the caller; standalone, one AskUserQuestion, header "Recipe": the remedy found, "Retry on GitHub", "Skip <image>, continue", "Stop; the user investigates" |
| smoke | `FAIL <check>` | rerun the failing command by hand in the image to separate a check defect from an image defect; report which |

A `RUN … || { echo mismatch; exit 1; }` prints its message for any earlier failure in the
chain; the cause is the first failing command.

## Report

```
## image-builds: <images>
Where: local | github (<branch>, push=<true|false>) · Scope: <built> · Test: <level> · Disk: <before> -> <after>

| image | build | minutes | id | smoke | smoke min | expects asserted | log |
|---|---|---|---|---|---|---|---|

### Not rebuilt
- <image>: deferred, cold budget <min> | unchanged | id unchanged
### Failures
- <image>: <class> — "<quoted line>" (<file:line>) — <action taken>
### Start script: <path | none>
| check | result | evidence |
|---|---|---|
### Left behind
nothing | - <kind> <ref> <owner> — created by <command | script:line> — `<removal command>`
```
