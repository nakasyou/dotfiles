# Nix cache redirect worker

This Worker implements the read side of a Nix HTTP binary cache. It serves
`/nix-cache-info`, resolves `.narinfo` and NAR paths from Workers KV, then sends
the client to the matching public GitHub Release asset with a `302` response.
It deliberately does not proxy NAR bytes.

## Bootstrap

1. Generate an Ed25519 cache key outside this repository:

   ```bash
   nix key generate-secret --key-name cache.nakasyou.how-1 > cache-private.key
   nix key convert-secret-to-public < cache-private.key
   ```

2. Add the contents of `cache-private.key` as the GitHub Actions secret
   `NIX_CACHE_SIGNING_KEY`.
3. Create a Cloudflare KV namespace and put its ID in `wrangler.jsonc`.
4. Create a Cloudflare API token restricted to that namespace and add these
   GitHub Actions secrets: `CLOUDFLARE_ACCOUNT_ID`,
   `CLOUDFLARE_KV_NAMESPACE_ID`, and `CLOUDFLARE_API_TOKEN`.
5. Deploy the Worker and bind `cache.nakasyou.how/*` to it:

   ```bash
   npx wrangler deploy --config workers/nix-cache/wrangler.jsonc \
     --route 'cache.nakasyou.how/*'
   ```

6. Put the public key from step 1 in both host configurations and replace the
   existing Cachix substituter with `https://cache.nakasyou.how`.

The cache must use public GitHub Releases: the Worker redirects clients rather
than forwarding authenticated GitHub downloads.

## Index format

The publisher stores an entry under the Workers KV key `path:<request-path>`.
For example:

```json
{
  "tag": "nix-cache-123456-1-001",
  "asset": "0abc123.nar.zst"
}
```

The same mapping is retained in the mutable `nix-cache-index` GitHub Release as
`index.json.zst`. KV can therefore be reconstructed without relying on a local
database.

## KV garbage collection

The publisher records one complete closure per logical root (`linux` and
`darwin` in the workflow). After each publish it retains only the union of the
latest closures for every root in Workers KV. It removes index and KV entries
that are no longer reachable from those roots, but deliberately leaves the old
GitHub Releases and their assets intact.

An older flake lock can therefore still be rebuilt from source, but it will not
be substituted from this cache once its closure has been collected from KV.
