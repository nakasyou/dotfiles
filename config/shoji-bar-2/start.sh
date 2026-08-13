#!/usr/bin/env bash
set -euo pipefail

socket="${XDG_RUNTIME_DIR}/astal/shoji-bar-2.sock"
if [[ -S "$socket" ]] && ! fuser "$socket" >/dev/null 2>&1; then
  rm -f "$socket"
fi

# The compositor service historically forced Cairo. Use GTK's GPU renderer on
# the AMD render node for the remaining bar and popup surfaces.
export GSK_RENDERER=ngl

exec /home/nakasyou/.local/state/nix/profiles/home-manager/home-path/bin/ags run --gtk4 app.tsx
