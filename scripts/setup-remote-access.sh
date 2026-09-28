#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# path: includes the user's existing untracked local package/config files.
sudo nixos-rebuild switch --flake "path:$repo_dir#p14s"
sudo systemctl start rustdesk.service
sudo systemctl is-active --quiet rustdesk.service

umask 077
credential_dir="${XDG_CONFIG_HOME:-$HOME/.config}/remote-access"
mkdir -p "$credential_dir"
password_file="$credential_dir/rustdesk-password"
if [[ ! -s "$password_file" ]]; then
  od -An -N12 -tx1 /dev/urandom | tr -d ' \n' > "$password_file"
fi
chmod 600 "$password_file"

configured=false
for attempt in {1..15}; do
  result=$(sudo -H /run/current-system/sw/bin/rustdesk --password "$(cat "$password_file")" 2>&1)
  if [[ "$result" == *"Done!"* ]]; then
    configured=true
    break
  fi
  sleep 1
done
if [[ "$configured" != true ]]; then
  printf 'RustDesk password was NOT applied: %s\n' "$result" >&2
  exit 1
fi

printf '\nRustDesk ID: '
sudo -H /run/current-system/sw/bin/rustdesk --get-id
printf 'RustDesk password: %s\n' "$(cat "$password_file")"
printf '\nChrome Remote Desktop: finish account registration at https://remotedesktop.google.com/headless\n'
