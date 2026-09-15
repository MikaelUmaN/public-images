---
name: lts-versions
description: Finds the canonical release source for one software package, lists its versions, applies the repository's long-term-stable rule to pick a candidate, and reports known compatibility issues against named peers as URLs and quoted lines; for a package whose support line is ending with nothing newer released, gathers why, what could replace it and where the images depend on it. Use when choosing a version to pin, checking whether a pin is stale, diagnosing a failed build after a version change, or deciding what to do with a package at end of life.
user-invocable: true
argument-hint: "<package> --current <version> --install <how> [--peers name=version,...] [--prefer patch|line] [--direction later|earlier] [--failure <quoted log line>] [--eol]"
compatibility: Linux with curl, jq and an authenticated gh. Network access to the endpoints in references/ecosystems.md.
---

# LTS versions

The skill returns evidence and one recommendation for a single package. It edits nothing and
builds nothing. Every claim carries a URL and, for a web page, a quoted line. Registry JSON is
read with `curl -fsSL … | jq`, GitHub with `gh api`, `gh release` and `gh issue list`, HTML pages
with WebFetch. An unreachable source is reported as unreachable, never guessed around.

## Parse

`$ARGUMENTS` holds the package name followed by flags:

| Flag | Meaning |
|---|---|
| `--current <version>` | the version pinned today; the floor for every recommendation |
| `--install <how>` | install form and location, e.g. `ARG DUCKDB_VERSION at datascience.docker:150` |
| `--peers name=version,...` | partners whose coupling rule the candidate must satisfy |
| `--prefer patch\|line` | which candidate to recommend when both pass; default `line` |
| `--direction later\|earlier` | `earlier` is honored only together with `--failure` |
| `--failure "<line>"` | the quoted build or smoke log line that triggered this call |
| `--eol` | runs the End-of-life investigation whatever the support window says |

`--direction earlier` without `--failure` is refused: the report states the refusal under
Recommendation and stops. With `--failure`, every candidate below `--current` is marked
"downgrade — requires user decision".

## Locate the source of truth

The row for the package or its ecosystem in `references/ecosystems.md` names the source, the
list command, the LTS notion and the coupling rule. A package absent from the table gets its
maintainer and canonical channel identified in this order: homepage, repository, registry. The
report then proposes a table row under Follow-ups.

## List versions

The row's command lists tag, publication date, prerelease flag and yanked or deprecated state,
plus whatever constraint the registry exposes: `rust_version` (crates.io), `engines` (npm),
`requires_python` and wheel filenames (PyPI), target frameworks (NuGet), `support-phase` (.NET).

## Apply the LTS rule

Where the project publishes support windows (an LTS flag, an end-of-life date, a support phase),
they decide, in this order:

- The candidate is the LTS line with the highest version number, at its highest patch.
- An LTS line is *expiring* when its end-of-life lies within six months. An expiring line is
  left as soon as any newer release line exists, LTS or not: the candidate becomes the highest
  patch of the newest line, marked `expiring LTS -> newer line`, with the next planned release
  from the project's calendar named beside it so the next run can return to an LTS.
- An expiring line with no newer release line anywhere (no later tag, no other channel, nothing
  on the release calendar) marks the package *end-of-life suspect*: the End-of-life
  investigation below runs, the report carries a warning the user has to act on, and no
  candidate is recommended.
- A coupling rule outranks the advance. When the newer line is blocked by a peer (kubectl by
  the cluster skew, a crate by `RUST_VERSION`), the report names the conflict and the caller
  puts it to the user.

Project-specific support windows (.NET, Python, kubectl, Quarto, DuckDB, Helm, Ubuntu) are the
LTS notion column of `references/ecosystems.md`.

Everywhere else the maturity gate decides. A candidate passes when all hold:

- a full release: no prerelease, RC, nightly, yanked or deprecated marker
- the first release of its minor line is at least 14 days old (7 days for AWS CLI and uv)
- it is the highest patch within its line, whatever its own age
- no open issue in the project's tracker is titled with the version or labelled regression and
  names a defect on Linux x86_64 in a code path the image exercises (the CLI as invoked, the
  library as linked); fast-moving CLIs such as bun and codex carry version-titled issues on
  every release, so those are listed with an "affects this image" verdict and the candidate
  passes when none does

For Nushell, uv and k9s a 0.x minor counts as a breaking line.

Two candidates are always computed: `patch`, the highest patch of the current minor, and `line`,
the highest minor or major that passes the gate. The recommendation is `line` unless
`--prefer patch` was given or a coupling rule forbids the move.

## Check peers

A version already installed in a built image has its coupling proven by that build: a crate at
its resolved version compiles under the current `RUST_VERSION`, so the MSRV fallback runs for
new candidates only. Peer registries may number the same release differently (crates.io
`libduckdb-sys` 1.4.x mirrors DuckDB 1.4.x while 1.105xx.0 mirrors 1.5.x); the table row names
the mapping.

Each `--peers` entry is checked with the coupling rule from the table: identity (Nushell plugin,
DuckDB library, Pico SDK and picotool), MSRV against `rust`, wheel existence against `python`,
target framework against the .NET SDKs, `engines` against `bun`, version skew against a cluster
minor. The evidence line is quoted with its URL.

## Search known issues

```
gh issue list -R <owner/repo> --state open --search "<version> in:title" --limit 20
gh issue list -R <owner/repo> --state open --label regression --limit 20
```

plus the release notes of the recommended version, read for "known issues" and "breaking". With
`--failure`, the quoted line is searched as well:

```
gh issue list -R <owner/repo> --state all --search "<distinctive fragment of the line>" --limit 10
```

## Check new requirements

A newer version can need what the current one did not. For the recommended candidate the skill
reads the release notes of every release between `--current` and the candidate and the
project's install or platform documentation at the candidate's tag, looking for a new or raised
requirement in four kinds:

- a system package or shared library (`apt`, `ldd`), such as bubblewrap for Codex's sandbox
- a kernel or container feature (user namespaces, seccomp, cgroups, a device), which an image
  cannot ship and a `docker run` flag must grant
- a minimum peer version (Node, Python, glibc, a companion tool)
- a configuration or environment variable the new version expects at startup

Each finding is checked against the image: the package's presence in the Dockerfile's apt list
or in `dpkg -l` of a built image, the feature by a probe (`unshare --user true`), the peer by
its pinned version. Findings fill the New requirements section of the report; `remedy` is the apt package name,
the `docker run` flag, the peer bump, or the config line. A requirement the container cannot
satisfy is reported as a runtime fact, never hidden.

## Investigate end of life

Runs for an end-of-life suspect and on `--eol`. Three questions, each answered with evidence:

- **Reason.** `gh api repos/<o>/<r> --jq '{archived, pushed_at, open_issues_count}'`; the date
  of the last release and of the last commit on the default branch; README and release notes
  read for "maintenance", "deprecated", "archived", "successor";
  `gh issue list -R <o/r> --state all --search "maintained OR deprecated OR successor OR archive in:title" --limit 10`;
  the registry's own deprecation text (npm `deprecated`, PyPI yanked reasons, crates.io yanked,
  NuGet `deprecation`). The finding is one of: archived, dormant since `<date>`, maintainers
  announced end of life at `<url>`, or active with no successor line planned.
- **Forks and replacements.**
  `gh api "repos/<o>/<r>/forks?sort=stargazers&per_page=10" --jq '.[] | "\(.full_name)\t\(.stargazers_count)\t\(.pushed_at)"'`,
  keeping forks pushed within six months; projects named as successors in the README, the
  archive notice or the issues; registry packages offering the same interface. Each row names
  the project, its URL, last release, licence, and what it drops or adds against the package.
- **Dependencies in the images.** Every site in the repository that names the package or its
  artefacts: `grep -n` over `*.docker`, `pyproject.toml`, `init.evcxr` and `tests/`, plus the
  `FROM` chain that inherits the install. Each row: image, `file:line`, kind (install, ENV,
  LABEL, library consumer, smoke check). Consumers inside a built image are the caller's to
  verify; the skill reads the repository, not the images.

The findings fill the End-of-life warning section of the report.

## Recommend

One version, what moves with it, and any question the caller has to put to the user. When the
latest release is younger than the gate allows, the recommendation is the highest patch of the
current minor and the report names the younger line with its date, so the next run picks it up.

## Report

```
## lts-versions: <package>
Source of truth: <url> — maintainer <org>
Current: <version> via <install method> (<file:line>)
Latest release: <ver> (<date>) · latest in current minor: <ver> (<date>)
Support schedule: <one line> — <url>

### Candidates
| candidate | version | published | age (days) | gate | reason |
|---|---|---|---|---|---|
| patch | | | | pass/fail | |
| line | | | | pass/fail | |

### Peers
| peer | current | coupling rule | evidence (url — "quoted line") | verdict |
|---|---|---|---|---|

### Known issues in <recommended version>
- <url> — "<quoted title>" (open|closed; affects this image: yes|no|unknown)

### New requirements for <recommended version>
| requirement | kind | since | present in image | source (url — "quoted line") | remedy |
|---|---|---|---|---|---|

### End-of-life warning: <package>   (present only when raised)
Line <x.y> ends <date>; newest release <ver> (<date>) is on that line; calendar: <none | url>.
Reason: <archived | dormant since <date> | announced at <url>> — "<quoted line>"
| replacement | url | last release | licence | delta against <package> |
|---|---|---|---|---|
| image | file:line | kind |
|---|---|---|
Options for the user: replace with <name> | keep <ver> pinned, review by <date> | remove

### Recommendation
<version> — <one sentence>. Moves with it: <peer -> version, ...>.
Direction: later | earlier (downgrade — requires user decision)
Ask the user: none | "<question>"

### Follow-ups
```
