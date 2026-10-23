#!/bin/sh
# Install the Pi/OMP renderer at the user level without changing Claude Code.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
agent_dir="${PI_CODING_AGENT_DIR:-${HOME:?}/.omp/agent}"
mkdir -p "$agent_dir/extensions"
cp "$script_dir/pi-statusline.ts" "$agent_dir/extensions/memoline.ts"
omp config set composer.shape memoline
printf 'Installed Pi statusline in %s; restart omp to see it.\n' "$agent_dir/extensions/memoline.ts"
