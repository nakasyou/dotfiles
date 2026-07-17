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
closure_file="$workdir/closure-paths"
custom_paths_file="$workdir/custom-paths"
pair_file="$workdir/object-pairs.jsonl"

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
      --upload-file "$file" \
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

# GitHub Releases should contain only paths that are unavailable from the
# official cache. References to official paths remain valid and are fetched
# directly from cache.nixos.org by clients.
printf '%s\n' "$@" | nix path-info --recursive --stdin | sort --unique > "$closure_file"
: > "$custom_paths_file"
export custom_paths_file
if ! xargs --no-run-if-empty --max-procs=32 --max-args=1 bash -c '
  path=$1
  base=${path##*/}
  hash=${base%%-*}
  status=$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    --retry 4 --retry-all-errors --retry-delay 2 \
    "https://cache.nixos.org/${hash}.narinfo") || exit 1
  case "$status" in
    200) ;;
    404) printf "%s\\n" "$path" >> "$custom_paths_file" ;;
    *) echo "Unexpected cache.nixos.org response $status for $path" >&2; exit 1 ;;
  esac
' _ < "$closure_file"; then
  echo "Failed while checking the official Nix cache." >&2
  exit 1
fi
sort --unique --output "$custom_paths_file" "$custom_paths_file"

official_count=$(($(wc -l < "$closure_file") - $(wc -l < "$custom_paths_file")))
custom_count=$(wc -l < "$custom_paths_file")
echo "Excluding $official_count paths available from cache.nixos.org; preparing $custom_count custom paths."

mkdir -p "$cache_dir/nar"
# A file binary cache requires referenced paths to be present while it is
# assembled. Materialize the complete closure locally, then select only custom
# narinfo/NAR pairs for Release upload below.
nix copy --to "file://$cache_dir?compression=zstd&secret-key=$key_file" "$@"

declare -a paths files
declare -A custom_store_hashes selected_paths
while IFS= read -r path; do
  store_name=${path##*/}
  custom_store_hashes[${store_name%%-*}]=1
done < "$custom_paths_file"
: > "$pair_file"
while IFS= read -r -d '' narinfo_file; do
  narinfo_name=${narinfo_file##*/}
  store_hash=${narinfo_name%.narinfo}
  [[ -n ${custom_store_hashes[$store_hash]+x} ]] || continue

  nar_relative=$(sed -n 's/^URL: //p' "$narinfo_file")
  narinfo_path="/$narinfo_name"
  nar_path="/$nar_relative"
  nar_file="$cache_dir/$nar_relative"

  if [[ ! $nar_relative =~ ^nar/[A-Za-z0-9][A-Za-z0-9._-]*\.nar(\.(zst|xz|bz2|gz))?$ ]] || [[ ! -f $nar_file ]]; then
    echo "Refusing to publish $narinfo_path without its NAR: $nar_relative" >&2
    exit 1
  fi

  if [[ -z ${selected_paths[$nar_path]+x} ]]; then
    paths+=("$nar_path")
    files+=("$nar_file")
    selected_paths[$nar_path]=1
  fi
  paths+=("$narinfo_path")
  files+=("$narinfo_file")
  selected_paths[$narinfo_path]=1
  jq --null-input --compact-output \
    --arg narinfo "$narinfo_path" --arg nar "$nar_path" \
    '{narinfo: $narinfo, nar: $nar}' >> "$pair_file"
done < <(find "$cache_dir" -maxdepth 1 -type f -name '*.narinfo' -print0)

# If an earlier interrupted run indexed only one half of a narinfo/NAR pair,
# remove both mappings so this run uploads a complete replacement pair.
jq --slurpfile pairs "$pair_file" '
  reduce $pairs[] as $pair (.;
    if ((.objects[$pair.narinfo] != null) != (.objects[$pair.nar] != null))
    then del(.objects[$pair.narinfo], .objects[$pair.nar])
    else .
    end
  )
' "$index_file" > "$workdir/index.repaired.json"
mv "$workdir/index.repaired.json" "$index_file"

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
    tag=$(printf 'nix-cache-%s-%s-%s-%03d' "$NIX_CACHE_ROOT" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$shard")
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
root_paths_file="$workdir/root-paths.json"
printf '%s\n' "${paths[@]}" | jq --raw-input --slurp 'split("\n") | map(select(length > 0))' > "$root_paths_file"
jq --arg root "$NIX_CACHE_ROOT" --slurpfile paths "$root_paths_file" '.roots[$root] = $paths[0]' "$index_file" > "$workdir/index.with-root.json"
mv "$workdir/index.with-root.json" "$index_file"

live_paths_file="$workdir/live-paths.json"
jq '[.roots[]?[]] | unique | map({key: ., value: true}) | from_entries' "$index_file" > "$live_paths_file"
removed_count=$(jq --slurpfile live "$live_paths_file" '$live[0] as $live | [.objects | keys[] | select($live[.] | not)] | length' "$index_file")
jq --slurpfile live "$live_paths_file" '$live[0] as $live | .objects |= with_entries(select($live[.key]))' "$index_file" > "$workdir/index.gc.json"
mv "$workdir/index.gc.json" "$index_file"
echo "Published ${#new_paths[@]} new objects in $shard Release shard(s); removed $removed_count stale index entries."
