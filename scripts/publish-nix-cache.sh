#!/usr/bin/env bash

set -euo pipefail

: "${NIX_CACHE_SIGNING_KEY:?Set NIX_CACHE_SIGNING_KEY to the cache private key}"
: "${GITHUB_REPOSITORY:?Run this from GitHub Actions or set GITHUB_REPOSITORY}"
: "${GITHUB_RUN_ID:?Set GITHUB_RUN_ID}"
: "${GITHUB_RUN_ATTEMPT:=1}"
: "${NIX_CACHE_ROOT:?Set NIX_CACHE_ROOT to a stable cache root, such as linux or darwin}"
: "${GH_TOKEN:?Set GH_TOKEN to a token allowed to create Releases}"

if (($# == 0)); then
  echo "usage: $0 STORE_PATH..." >&2
  exit 64
fi

workdir=$(mktemp -d)
cache_dir="$workdir/cache"
key_file="$workdir/cache-private.key"
index_file="$workdir/index.json"
publish_succeeded=false
index_published=false

cleanup() {
  rm -rf "$workdir"
}

wait_for_github_limit() {
  local headers=$1 attempt=$2 retry_after reset now delay
  retry_after=$(awk 'BEGIN { IGNORECASE = 1 } /^retry-after:/ { gsub("\\r", "", $2); print $2; exit }' "$headers")
  reset=$(awk 'BEGIN { IGNORECASE = 1 } /^x-ratelimit-reset:/ { gsub("\\r", "", $2); print $2; exit }' "$headers")
  now=$(date +%s)
  if [[ $retry_after =~ ^[0-9]+$ ]]; then
    delay=$retry_after
  elif [[ $reset =~ ^[0-9]+$ ]] && ((reset > now)); then
    delay=$((reset - now + 5))
  else
    delay=$((attempt * 30))
    ((delay > 300)) && delay=300
  fi
  ((delay < 5)) && delay=5
  echo "GitHub rate limit reached; waiting ${delay}s before retrying." >&2
  sleep "$delay"
}

github_command() {
  local attempt=0 output status delay
  while :; do
    attempt=$((attempt + 1))
    output=$(mktemp "$workdir/github-command.XXXXXX")
    if "$@" >"$output" 2>&1; then
      cat "$output"
      rm -f "$output"
      return 0
    else
      status=$?
    fi
    cat "$output" >&2
    if ! grep --ignore-case --quiet 'rate limit' "$output"; then
      rm -f "$output"
      return "$status"
    fi
    rm -f "$output"
    delay=$((attempt * 30))
    ((delay > 300)) && delay=300
    echo "GitHub API rate limit reached; waiting ${delay}s before retrying." >&2
    sleep "$delay"
  done
}

upload_asset() {
  local release_id=$1 file=$2 asset=$3 attempt=0 headers body status encoded_asset
  encoded_asset=$(jq --null-input --raw-output --arg value "$asset" '$value | @uri')

  while :; do
    attempt=$((attempt + 1))
    headers=$(mktemp "$workdir/github-headers.XXXXXX")
    body=$(mktemp "$workdir/github-body.XXXXXX")
    status=$(curl --silent --show-error --output "$body" --dump-header "$headers" --write-out '%{http_code}' \
      --request POST \
      --header "Authorization: Bearer $GH_TOKEN" \
      --header 'Accept: application/vnd.github+json' \
      --header 'Content-Type: application/octet-stream' \
      --data-binary "@$file" \
      "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$release_id/assets?name=$encoded_asset") || status=000

    case "$status" in
      200|201)
        rm -f "$headers" "$body"
        return 0
        ;;
      429)
        cat "$body" >&2
        wait_for_github_limit "$headers" "$attempt"
        rm -f "$headers" "$body"
        ;;
      403)
        cat "$body" >&2
        if grep --ignore-case --quiet 'rate limit' "$body"; then
          wait_for_github_limit "$headers" "$attempt"
          rm -f "$headers" "$body"
        else
          rm -f "$headers" "$body"
          return 1
        fi
        ;;
      422)
        # A response can be lost after GitHub has accepted an upload.  The
        # resulting duplicate-name response means this exact asset is present.
        if jq -e '.errors[]? | select(.code == "already_exists")' "$body" >/dev/null 2>&1; then
          rm -f "$headers" "$body"
          return 0
        fi
        cat "$body" >&2
        rm -f "$headers" "$body"
        return 1
        ;;
      *)
        cat "$body" >&2
        rm -f "$headers" "$body"
        return 1
        ;;
    esac
  done
}

publish_index() {
  [[ -f $index_file ]] || return 0

  # Keep one stable Release asset.  The Worker fetches this JSON at most once
  # per Cache API TTL, so cache lookups never require a KV read.
  if github_command gh release view nix-cache-index >/dev/null; then
    github_command gh release upload nix-cache-index "$index_file#index.json" --clobber
  else
    github_command gh release create nix-cache-index --target "$GITHUB_SHA" --title "Nix cache index" --notes "Mutable index for the Nix cache." "$index_file#index.json"
  fi
  index_published=true
}

finalize() {
  local status=$?
  trap - EXIT

  # On a failed upload the in-memory index already contains every asset whose
  # upload returned success. Publish it before propagating the failure. GC is
  # deliberately skipped below unless the complete run succeeds.
  if ! publish_index; then
    echo "Failed to publish the Nix cache index during finalization." >&2
    ((status == 0)) && status=1
  fi
  cleanup
  exit "$status"
}
trap finalize EXIT

umask 077
printf '%s\n' "$NIX_CACHE_SIGNING_KEY" > "$key_file"

nix copy --to "file://$cache_dir?compression=zstd&secret-key=$key_file" "$@"

printf '%s\n' '{"format":2,"objects":{},"roots":{}}' > "$index_file"
if github_command gh release view nix-cache-index >/dev/null; then
  mkdir "$workdir/index-download"
  if github_command gh release view nix-cache-index --json assets --jq '.assets[].name' | grep --fixed-strings --line-regexp index.json >/dev/null; then
    github_command gh release download nix-cache-index --pattern index.json --dir "$workdir/index-download"
    jq '.format = 2 | .objects //= {} | .roots //= {}' "$workdir/index-download/index.json" > "$index_file"
  elif github_command gh release view nix-cache-index --json assets --jq '.assets[].name' | grep --fixed-strings --line-regexp index.json.zst >/dev/null; then
    # One-time compatibility path for the previous compressed index format.
    github_command gh release download nix-cache-index --pattern index.json.zst --dir "$workdir/index-download"
    zstd --decompress --stdout "$workdir/index-download/index.json.zst" | jq '.format = 2 | .objects //= {} | .roots //= {}' > "$index_file"
  fi
fi

declare -a paths files
while IFS= read -r -d '' file; do paths+=("/nar/${file##*/}"); files+=("$file"); done < <(find "$cache_dir/nar" -type f -print0)
while IFS= read -r -d '' file; do paths+=("/${file##*/}"); files+=("$file"); done < <(find "$cache_dir" -maxdepth 1 -type f -name '*.narinfo' -print0)

declare -a new_paths new_files
for i in "${!paths[@]}"; do
  if ! jq --exit-status --arg path "${paths[$i]}" '.objects[$path] != null' "$index_file" >/dev/null; then
    new_paths+=("${paths[$i]}")
    new_files+=("${files[$i]}")
  fi
done

shard=0
if ((${#new_paths[@]} > 0)); then
  for start in $(seq 0 900 $((${#new_paths[@]} - 1))); do
    shard=$((shard + 1))
    tag=$(printf 'nix-cache-%s-%s-%03d' "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$shard")
    release_id=$(github_command gh api --method POST "repos/$GITHUB_REPOSITORY/releases" -f tag_name="$tag" -f target_commitish="$GITHUB_SHA" -f name="$tag" -f body="Nix binary-cache shard." --jq '.id')
    end=$((start + 900)); ((end > ${#new_paths[@]})) && end=${#new_paths[@]}
    for ((i = start; i < end; i++)); do
      asset=${new_files[$i]##*/}
      upload_asset "$release_id" "${new_files[$i]}" "$asset"
      entry=$(jq --null-input --compact-output --arg tag "$tag" --arg asset "$asset" '{tag: $tag, asset: $asset}')
      jq --arg path "${new_paths[$i]}" --argjson entry "$entry" '.objects[$path] = $entry' "$index_file" > "$workdir/index.next.json"
      mv "$workdir/index.next.json" "$index_file"
    done
  done
fi

# The Linux closure contains enough paths to exceed execve's argument-size
# limit if passed through `jq --args`.
root_paths=$(printf '%s\n' "${paths[@]}" | jq --raw-input --slurp 'split("\n") | map(select(length > 0))')
jq --arg root "$NIX_CACHE_ROOT" --argjson paths "$root_paths" '.roots[$root] = $paths' "$index_file" > "$workdir/index.with-root.json"
mv "$workdir/index.with-root.json" "$index_file"

removed_file="$workdir/removed.json"
jq '. as $index | [$index.roots[]?[]] | unique as $live | [$index.objects | to_entries[] | select(.key as $key | ($live | index($key) | not))]' "$index_file" > "$removed_file"
jq --slurpfile removed "$removed_file" 'reduce $removed[0][] as $entry (. ; del(.objects[$entry.key]))' "$index_file" > "$workdir/index.gc.json"
mv "$workdir/index.gc.json" "$index_file"
publish_succeeded=true

echo "Published ${#new_paths[@]} new objects in $shard Release shard(s); removed $(jq 'length' "$removed_file") stale index entries."
