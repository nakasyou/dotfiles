# Nix cache redirect worker

This Worker implements the read side of a Nix HTTP binary cache. It serves
`/nix-cache-info`, resolves `.narinfo` and NAR paths from the `index.json` asset
in the fixed `nix-cache-index` GitHub Release, then sends the client to the
matching public GitHub Release asset with a `302` response. It deliberately
does not proxy NAR bytes. The index is held in the Workers Cache API for five
minutes; Cloudflare KV is not used.

## Bootstrap

1. Generate an Ed25519 cache key outside this repository:

   ```bash
   nix key generate-secret --key-name cache.nakasyou.how-1 > cache-private.key
   nix key convert-secret-to-public < cache-private.key
   ```

2. Add the contents of `cache-private.key` as the GitHub Actions secret
   `NIX_CACHE_SIGNING_KEY`.
3. Deploy the Worker and bind `cache.nakasyou.how/*` to it:

   ```bash
   npx wrangler deploy --config workers/nix-cache/wrangler.jsonc \
     --route 'cache.nakasyou.how/*'
   ```

4. Put the public key from step 1 in both host configurations and replace the
   existing Cachix substituter with `https://cache.nakasyou.how`.

The cache must use public GitHub Releases: the Worker redirects clients rather
than forwarding authenticated GitHub downloads.

## Index format

The publisher stores request-path mappings in the fixed Release asset
`nix-cache-index/index.json`. For example:

```json
{
  "format": 2,
  "objects": {
    "/nar/0abc123.nar.zst": {
      "tag": "nix-cache-linux-123456-1-001",
      "asset": "0abc123.nar.zst"
    }
  },
  "roots": {
    "linux": ["/nar/0abc123.nar.zst"]
  }
}
```

Each publish excludes paths already available from `cache.nixos.org`. Every
indexed `.narinfo` is validated against its referenced NAR before upload. If a
previous interrupted run left only one half of a pair, both mappings are
re-uploaded together.

## Index garbage collection

The publisher records one custom closure per logical root (`linux` and `darwin`
in the workflow). After each publish it retains only the union of the latest
closures in the index. It removes unreachable index entries, but deliberately
leaves old GitHub Releases and their assets intact.

An older flake lock can therefore still be rebuilt from source, but it will not
be substituted from this cache once its closure has been collected from the
index.
