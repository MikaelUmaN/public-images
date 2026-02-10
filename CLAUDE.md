# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** Read [.github/copilot-instructions.md](.github/copilot-instructions.md) for detailed architecture principles, conventions, and development workflow.

## Build Commands

```bash
# Base image (must be built first for dependent images)
docker build -f datascience.docker -t mikaeluman/datascience:latest .

# Language extension images (require base image)
docker build -f rust-datascience.docker -t mikaeluman/datascience:rust .
docker build -f net-datascience.docker -t mikaeluman/datascience:net .

# GPU-enabled PyTorch variant
docker build -f datascience.docker --build-arg USE_TORCH_GPU=true -t mikaeluman/datascience:gpu .

# Standalone LaTeX image
docker build -f latex.docker -t mikaeluman/latex:latest .
```

CI runs via manual workflow dispatch (`.github/workflows/datascience.yml`) - select image to build from dropdown.

## Focus

- Images are meant for data science and analytical, quantitative work.
  - Except the latex.docker which is for technical documentation.
- Main languages focused on are Python, Rust and F#.

## Performance Profiling
We are running on WSL. This means we do not have access to hardware counters etc. But we can still do CPU sampling and get good performance profiling diagnostics.

Our strategy to achieve this is to build `perf` locally for our current WSL linux kernel using the Microsoft github package for `perf`. Then we mount volumes when running the container like:

```bash
  echo "Mounting host perf from /usr/local/bin/perf"
  DOCKER_OPTS+=(-v "/usr/local/bin/perf:/usr/local/bin/perf:ro")
  DOCKER_OPTS+=(-v "/usr/local/bin/perf:/usr/bin/perf:ro")
```

When building the image, we need to test that this setup works and that we can run `perf` within the container.

To make this work, we need the `datascience` base image to contain shared libraries like `linux-tools-generic`.