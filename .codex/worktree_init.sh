#!/usr/bin/env bash
set -eo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if ! command -v mise >/dev/null 2>&1; then
  echo "mise is required. Install it from https://mise.jdx.dev/getting-started.html" >&2
  exit 1
fi

cd "$repo_root"
mise trust

make setup
