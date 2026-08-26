# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** Read [.github/copilot-instructions.md](.github/copilot-instructions.md) for detailed architecture principles, conventions, and development workflow.

## Build Commands

Each stage builds `FROM` the previous, so they build in order:
`datascience` -> `rust-datascience` -> `net-datascience` -> `quarto-datascience`.
`latex.docker` and `pico.docker` are standalone.

```bash
docker build -f datascience.docker -t mikaeluman/datascience:latest .
```

Add `--build-arg USE_TORCH_GPU=true` for the GPU PyTorch variant. CI is manual workflow
dispatch (`.github/workflows/datascience.yml`) with the image picked from a dropdown.

## Pinned versions

Every toolchain and tool version is pinned exactly - `RUST_VERSION`, `NUSHELL_VERSION`,
`DUCKDB_VERSION`, `PICO_SDK_VERSION` and kin - never `stable` or `latest`. An unpinned toolchain
turns an untouched Dockerfile into a failing build weeks later, so do not widen a pin to get past
a broken build; fix the pinned combination instead.

Pins do go stale. When working on an image, check whether its pins have newer releases and propose
the bump, naming what moves with it: `NUSHELL_VERSION` has to change in `datascience.docker` and
`rust-datascience.docker` together, and `RUST_VERSION` has to satisfy the crates the `--locked`
installs resolve to.

## apt caching

Every apt layer uses BuildKit cache mounts on `/var/cache/apt` and `/var/lib/apt/lists`, so
rebuilds skip re-downloading packages. This requires deleting `/etc/apt/apt.conf.d/docker-clean`
(the base image ships it, and it wipes downloaded .debs) - done once in each standalone image.
Do not add `apt-get clean` or `rm -rf /var/lib/apt/lists/*` back: those paths are cache mounts,
never committed to a layer, so the cleanup only destroys the cache.

Note `docker build --no-cache` wipes cache mounts. The benefit is local only - GitHub runners
are ephemeral and the workflow exports no cache.

## Raspberry Pi Pico

`pico.docker` bakes in the Pico SDK at `/opt/pico-sdk` (`PICO_SDK_PATH` preset), plus `picotool`
and `pioasm` in `/usr/local`. `PICO_SDK_VERSION` and `PICOTOOL_VERSION` must be kept equal - the
SDK does `find_package(picotool ${version} REQUIRED)`. Arm only; the RP2350 RISC-V cores would
need a separate `riscv32` toolchain.

## Rust TUI (ratatui)

ratatui, crossterm and `tui-logger` write ANSI directly and need no system libraries, so they are
project dependencies, never image content. The images contribute `TERM=xterm-256color`,
`COLORTERM=truecolor` and `ncurses-term` for a forwarded host `TERM` (base), plus
`cargo-generate` and the xcb headers `arboard` links against for clipboard access (rust).

`docker run -t` is required - without a tty the alternate screen and key events do not work.

## Performance Profiling

WSL exposes no hardware counters, but CPU sampling works. Build `perf` for the running WSL kernel
from the Microsoft package (`~/scripts/install-wsl2-perf.sh`) and mount the host binary over both
`/usr/local/bin/perf` and `/usr/bin/perf` — `~/run-science.sh --perf` does this. The base image
carries `linux-tools-generic` for the shared libraries that binary links against.

## GUI / Chrome (WSLg)

The base image ships `google-chrome-stable` and the GL/dbus/font libraries for headed rendering.
The display is a runtime fact of the host, never baked into the image. Headless needs no mounts:

```bash
docker run --rm mikaeluman/datascience:latest google-chrome-stable --headless=new \
  --no-sandbox --screenshot=/tmp/out.png "file:///abs/path.html"
```

Headed forwards a real window to Windows. `~/run-science.sh` adds the flags whenever `$DISPLAY`
and `/mnt/wslg` exist, `--no-gui` opts out: `--shm-size=1g` (Chrome tabs crash on Docker's 64 MB
`/dev/shm`), `-e DISPLAY -e WAYLAND_DISPLAY -e PULSE_SERVER`,
`-e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir` (the host's own value does not exist in the
container), `-v /tmp/.X11-unix:/tmp/.X11-unix -v /mnt/wslg:/mnt/wslg`. Run from the WSL host,
not from inside another container.

Every Chrome invocation needs `--no-sandbox` (non-root uid without `SYS_ADMIN`). Playwright is
the bun/node package, not Python; `channel: 'chrome'` selects the system binary.

Hardware GL takes `--device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl
-e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e GALLIUM_DRIVER=d3d12`. `GALLIUM_DRIVER` is required:
with no `/dev/dri` to enumerate, mesa settles on llvmpipe. Chrome needs
`--use-gl=angle --use-angle=gl` on top, or ANGLE stays on bundled SwiftShader.
