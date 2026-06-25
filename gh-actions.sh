#!/bin/bash
for img in datascience rust-datascience net-datascience quarto-science; do
  echo "=== Building $img ==="
  gh workflow run datascience.yml --ref main -f image="$img"
  sleep 5
  id=$(gh run list --workflow=datascience.yml -L1 --json databaseId -q '.[0].databaseId')
  gh run watch "$id" --exit-status || { echo "FAILED: $img"; break; }
done