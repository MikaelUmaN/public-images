#!/bin/bash
set -e

# Sync dependencies from pyproject.toml on first run
echo "Syncing dependencies..."
uv sync

# Start Jupyter Lab
echo "Starting Jupyter Lab..."
exec uv run --with jupyter --with plotly jupyter lab
