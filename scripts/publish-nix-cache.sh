#!/usr/bin/env bash

set -euo pipefail

: "${NIX_CACHE_SIGNING_KEY:?Set NIX_CACHE_SIGNING_KEY to the cache private key}"
: "${CLOUDFLARE_ACCOUNT_ID:?Set CLOUDFLARE_ACCOUNT_ID}"
: "${CLOUDFLARE_KV_NAMESPACE_ID:?Set CLOUDFLARE_KV_NAMESPACE_ID}"
: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN}"
: "${GITHUB_REPOSITORY:?Run this from GitHub Actions or set GITHUB_REPOSITORY}"
: "${GITHUB_RUN_ID:?Set GITHUB_RUN_ID}"
: "${GITHUB_RUN_ATTEMPT:=1}"
: "${NIX_CACHE_ROOT:?Set NIX_CACHE_ROOT to a stable cache root, such as linux or darwin}"

if (($# == 0)); then
  echo "usage: $0 STORE_PATH..." >&2
  exit 64
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cache_dir="$workdir/cache"
key_file="$workdir/cache-private.key"
index_file="$workdir/index.json"
compressed_index="$workdir/index.json.zst"
delta_file="$workdir/kv-delta.json"

umask 077
printf '%s\n' "$NIX_CACHE_SIGNING_KEY" > "$key_file"

nix copy \
  --to "file://$cache_dir?compression=zstd&secret-key=$key_file" \
  "$@"

printf '%s\n' '{"format":2,"objects":{},"roots":{}}' > "$index_file"
if gh release view nix-cache-index >/dev/null 2>&1; then
  gh release download nix-cache-index --pattern index.json.zst --dir "$workdir"
  zstd --decompress --stdout "$workdir/index.json.zst" > "$index_file"
fi
jq '.format = 2 | .objects //= {} | .roots //= {}' "$index_file" > "$workdir/index.normalized.json"
mv "$workdir/index.normalized.json" "$index_file"

declare -a paths files
while IFS= read -r -d '' file; do
  paths+=("/nar/${file##*/}")
  files+=("$file")
done < <(find "$cache_dir/nar" -type f -print0)
while IFS= read -r -d '' file; do
  paths+=("/${file##*/}")
  files+=("$file")
done < <(find "$cache_dir" -maxdepth 1 -type f -name '*.narinfo' -print0)

declare -a new_paths new_files
for i in "${!paths[@]}"; do
  if ! jq --exit-status --arg path "${paths[$i]}" '.objects[$path] != null' "$index_file" >/dev/null; then
    new_paths+=("${paths[$i]}")
    new_files+=("${files[$i]}")
  fi
done

printf '%s\n' '[]' > "$delta_file"
shard=0
if ((${#new_paths[@]} > 0)); then
  for start in $(seq 0 900 $((${#new_paths[@]} - 1))); do
    shard=$((shard + 1))
    tag=$(printf 'nix-cache-%s-%s-%03d' "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$shard")
    gh release create "$tag" --target "$GITHUB_SHA" --title "$tag" --notes "Nix binary-cache shard."

    end=$((start + 900))
    if ((end > ${#new_paths[@]})); then end=${#new_paths[@]}; fi
    for ((i = start; i < end; i++)); do
      gh release upload "$tag" "${new_files[$i]}"
      asset=${new_files[$i]##*/}
      entry=$(jq --compact-output --arg tag "$tag" --arg asset "$asset" '{tag: $tag, asset: $asset}')
      tmp_index="$workdir/index.next.json"
      jq --arg path "${new_paths[$i]}" --argjson entry "$entry" '.objects[$path] = $entry' "$index_file" > "$tmp_index"
      mv "$tmp_index" "$index_file"
      tmp_delta="$workdir/delta.next.json"
      jq --arg key "path:${new_paths[$i]}" --arg value "$entry" '. + [{key: $key, value: $value}]' "$delta_file" > "$tmp_delta"
      mv "$tmp_delta" "$delta_file"
    done
  done
fi

root_paths=$(jq --null-input '$ARGS.positional' --args "${paths[@]}")
jq --arg root "$NIX_CACHE_ROOT" --argjson paths "$root_paths" '.roots[$root] = $paths' "$index_file" > "$workdir/index.with-root.json"
mv "$workdir/index.with-root.json" "$index_file"

removed_file="$workdir/removed.json"
jq '
  . as $index
  | [$index.roots[]?[]] | unique as $live
  | [
      $index.objects
      | to_entries[]
      | select(.key as $key | ($live | index($key) | not))
    ]
' "$index_file" > "$removed_file"

jq --slurpfile removed "$removed_file" 'reduce $removed[0][] as $entry (. ; del(.objects[$entry.key]))' "$index_file" > "$workdir/index.gc.json"
mv "$workdir/index.gc.json" "$index_file"

zstd --quiet --force "$index_file" --output "$compressed_index"
if gh release view nix-cache-index >/dev/null 2>&1; then
  gh release upload nix-cache-index "$compressed_index" --clobber
else
  gh release create nix-cache-index --target "$GITHUB_SHA" --title "Nix cache index" --notes "Mutable index for the Nix cache." "$compressed_index"
fi

if (($(jq 'length' "$delta_file") > 0)); then
  for start in $(seq 0 10000 $(($(jq 'length' "$delta_file") - 1))); do
    batch_file="$workdir/kv-batch.json"
    jq --argjson start "$start" '.[$start:($start + 10000)]' "$delta_file" > "$batch_file"
    curl --fail-with-body --silent --show-error \
      --request PUT \
      --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      --header 'Content-Type: application/json' \
      --data-binary "@$batch_file" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/storage/kv/namespaces/$CLOUDFLARE_KV_NAMESPACE_ID/bulk" \
      | jq --exit-status '.success == true' >/dev/null
  done
fi

removed_keys_file="$workdir/removed-keys.json"
jq '[.[].key | "path:" + .]' "$removed_file" > "$removed_keys_file"
if (($(jq 'length' "$removed_keys_file") > 0)); then
  for start in $(seq 0 10000 $(($(jq 'length' "$removed_keys_file") - 1))); do
    batch_file="$workdir/kv-delete-batch.json"
    jq --argjson start "$start" '.[$start:($start + 10000)]' "$removed_keys_file" > "$batch_file"
    curl --fail-with-body --silent --show-error \
      --request DELETE \
      --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      --header 'Content-Type: application/json' \
      --data-binary "@$batch_file" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/storage/kv/namespaces/$CLOUDFLARE_KV_NAMESPACE_ID/bulk" \
      | jq --exit-status '.success == true' >/dev/null
  done
fi

echo "Published ${#new_paths[@]} new objects in $shard Release shard(s); removed $(jq 'length' "$removed_file") stale KV entries."
