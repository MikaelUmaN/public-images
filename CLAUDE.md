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
