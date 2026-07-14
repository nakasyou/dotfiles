#!/usr/bin/env bash
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
assets="$work/assets.ndjson"

for tag in "$@"; do
  release_id=$(gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag" --jq '.id')
  gh api --paginate "repos/$GITHUB_REPOSITORY/releases/$release_id/assets?per_page=100" --jq '.[].name' \
    | jq -R --arg tag "$tag" '
        if endswith(".narinfo") then { path: ("/" + .), tag: $tag, asset: . }
        elif test("\\.nar\\.(zst|xz|bz2|gz)$") then { path: ("/nar/" + .), tag: $tag, asset: . }
        else empty end
      ' >> "$assets"
done

jq -s '
  {
    format: 2,
    objects: (reduce .[] as $entry ({}; .[$entry.path] = { tag: $entry.tag, asset: $entry.asset })),
    roots: { linux: (map(.path) | unique) }
  }
' "$assets" > "$work/index.json"
if gh release view nix-cache-index >/dev/null 2>&1; then
  gh release upload nix-cache-index "$work/index.json#index.json" --clobber
else
  gh release create nix-cache-index --target main --title "Nix cache index" \
    --notes "Recovered index for the Nix cache." "$work/index.json#index.json"
fi

jq -r '.objects | length' "$work/index.json"
