#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# `mops sources` resolves dependencies from the current working directory.
# DFX already invokes this wrapper from the repository root, but we `cd`
# explicitly so the command also works when paths contain spaces.
exec mops sources
