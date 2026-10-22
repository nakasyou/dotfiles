#!/usr/bin/env bash
set -euo pipefail

cache_dir=$1
key_file=$2
closure_file=$3
custom_paths_file=$4
shift 4

mkdir -p "$cache_dir/nar"
printf '%s\n' "$@" | nix path-info --recursive --stdin | sort -u > "$closure_file"
: > "$custom_paths_file"
export cache_dir custom_paths_file
if ! xargs -P 32 -n 1 bash -c '
  path=$1
  base=${path##*/}
  hash=${base%%-*}
  narinfo="$cache_dir/$hash.narinfo"
  status=$(curl --silent --show-error --output "$narinfo" --write-out "%{http_code}" \
    --retry 4 --retry-all-errors --retry-delay 2 \
    "https://cache.nixos.org/${hash}.narinfo") || exit 1
  case "$status" in
    200) ;;
    404) rm -f "$narinfo"; printf "%s\n" "$path" >> "$custom_paths_file" ;;
    *) echo "Unexpected cache.nixos.org response $status for $path" >&2; exit 1 ;;
  esac
' _ < "$closure_file"; then
  echo "Failed while checking the official Nix cache." >&2
  exit 1
fi
sort -u -o "$custom_paths_file" "$custom_paths_file"
official_count=$(($(wc -l < "$closure_file") - $(wc -l < "$custom_paths_file")))
custom_count=$(wc -l < "$custom_paths_file")
echo "Excluding $official_count paths available from cache.nixos.org; preparing $custom_count custom paths."

# Nix checks references against the seeded metadata and only writes custom NARs.
nix copy --to "file://$cache_dir?compression=zstd&secret-key=$key_file" "$@"
