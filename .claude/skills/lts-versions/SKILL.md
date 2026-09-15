---
name: lts-versions
description: Finds the canonical release source for one software package, lists its versions, applies the repository's long-term-stable rule to pick a candidate, and reports known compatibility issues against named peers as URLs and quoted lines. Use when choosing a version to pin, checking whether a pin is stale, or diagnosing a failed build after a version change.
user-invocable: true
argument-hint: "<package> --current <version> --install <how> [--peers name=version,...] [--prefer patch|line] [--direction later|earlier] [--failure <quoted log line>]"
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

Where a real support window exists, it decides:

- .NET: `release-type: lts` and `support-phase: active`.
- Python: the minor with at least twelve months to end-of-life and `cp313`-class wheels for
  torch, numba and pymc.
- kubectl: the highest patch within the current minor; a minor move needs `cluster-minor` from
  the caller.
- Quarto: the stable channel only.
- DuckDB: the line marked `lts` in `duckdb-releases.csv`, highest patch. When that line's
  `end_of_life` lies within 30 days and the CSV lists no successor LTS line, the report asks the
  user whether to take the last LTS patch, the current non-LTS line, or to wait.
- Helm: 3.x and 4.x are maintained in parallel; the recommendation stays inside the current
  major and names the other major's candidate for the user.
- Ubuntu: fixed at 24.04.

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

### Recommendation
<version> — <one sentence>. Moves with it: <peer -> version, ...>.
Direction: later | earlier (downgrade — requires user decision)
Ask the user: none | "<question>"

### Follow-ups
```
