#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Two store paths with a real reference, without building any packages.
dep=$(nix eval --raw --expr 'builtins.toFile "cache-test-dependency" "official dependency"')
root=$(nix eval --raw --expr 'let dep = builtins.toFile "cache-test-dependency" "official dependency"; in builtins.toFile "cache-test-root" "custom root references ${dep}"')
nix-store --generate-binary-cache-key cache-test "$workdir/key" "$workdir/key.pub"
nix copy --to "file://$workdir/official?compression=zstd" "$dep"
base=${dep##*/}
export test_official_hash=${base%%-*}
export test_official_dir="$workdir/official"
mkdir "$workdir/bin"
cat > "$workdir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  case "$1" in
    --output) output=$2; shift 2 ;;
    https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
if [[ ${test_cache_error:-0} == 1 ]]; then
  printf 'Service unavailable' > "$output"
  printf 503
elif [[ $url == "https://cache.nixos.org/$test_official_hash.narinfo" ]]; then
  cp "$test_official_dir/$test_official_hash.narinfo" "$output"
  printf 200
else
  printf 'Not found' > "$output"
  printf 404
fi
MOCK
chmod +x "$workdir/bin/curl"
PATH="$workdir/bin:$PATH" bash "$repo_dir/scripts/prepare-nix-cache.sh" \
  "$workdir/staging" "$workdir/key" "$workdir/closure" "$workdir/custom" "$root"

[[ $(cat "$workdir/custom") == "$root" ]]
[[ $(wc -l < "$workdir/closure") -eq 2 ]]
base=${root##*/}
root_info="$workdir/staging/${base%%-*}.narinfo"
grep -q '^Sig: cache-test:' "$root_info"
root_nar=$(sed -n 's/^URL: //p' "$root_info")
dep_nar=$(sed -n 's/^URL: //p' "$workdir/official/$test_official_hash.narinfo")
[[ -f $workdir/staging/$root_nar ]]
[[ ! -e $workdir/staging/$dep_nar ]]
[[ $(find "$workdir/staging/nar" -type f | wc -l) -eq 1 ]]
# Restore into an isolated store using the official cache for the missing NAR.
nix copy --from "file://$workdir/official" --to "$workdir/restored" --no-check-sigs "$dep"
nix copy --from "file://$workdir/staging" --to "$workdir/restored" --no-check-sigs "$root"
cmp "$workdir/restored$root" "$root"
# A closure entirely on the official cache must produce no NAR files.
PATH="$workdir/bin:$PATH" bash "$repo_dir/scripts/prepare-nix-cache.sh" \
  "$workdir/official-only" "$workdir/key" "$workdir/closure" "$workdir/custom" "$dep"
[[ ! -s $workdir/custom ]]
[[ $(find "$workdir/official-only/nar" -type f | wc -l) -eq 0 ]]

# An outage must fail closed, rather than classify every path as custom.
if test_cache_error=1 PATH="$workdir/bin:$PATH" bash "$repo_dir/scripts/prepare-nix-cache.sh" \
  "$workdir/unavailable" "$workdir/key" "$workdir/closure" "$workdir/custom" "$root"; then
  echo 'Expected cache availability check to fail.' >&2
  exit 1
fi
[[ $(find "$workdir/unavailable/nar" -type f | wc -l) -eq 0 ]]
echo 'Cache staging regression test passed.'
