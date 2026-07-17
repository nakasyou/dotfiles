interface CacheObject {
  asset: string;
  nar?: string;
  tag: string;
}

interface CacheIndex {
  format: number;
  objects: Record<string, CacheObject>;
}

interface Env {
  GITHUB_REPOSITORY: string;
}

const INDEX_RELEASE_TAG = "nix-cache-index";
const INDEX_ASSET_NAME = "index.json";
const INDEX_CACHE_SECONDS = 60;

const immutableRedirectHeaders = {
  "Cache-Control": "public, max-age=31536000, immutable",
};

function isCachePath(pathname: string): boolean {
  return (
    /^\/[0-9a-z]{32}\.narinfo$/i.test(pathname) ||
    /^\/nar\/[A-Za-z0-9][A-Za-z0-9._-]*\.nar(?:\.(?:zst|xz|bz2|gz))?$/.test(pathname)
  );
}

function isSafeAssetPart(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value);
}

function githubAssetUrl(repository: string, tag: string, asset: string): URL | null {
  const [owner, repo, ...rest] = repository.split("/");
  if (!owner || !repo || rest.length > 0 || !isSafeAssetPart(tag) || !isSafeAssetPart(asset)) {
    return null;
  }

  return new URL(
    `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/releases/download/${encodeURIComponent(tag)}/${encodeURIComponent(asset)}`,
  );
}

function indexCacheKey(repository: string): Request {
  return new Request(`https://nix-cache-index.invalid/${encodeURIComponent(repository)}/${INDEX_ASSET_NAME}`);
}

async function loadIndex(repository: string): Promise<CacheIndex | null> {
  const cache = caches.default;
  const key = indexCacheKey(repository);
  let response = await cache.match(key);

  if (!response) {
    const source = githubAssetUrl(repository, INDEX_RELEASE_TAG, INDEX_ASSET_NAME);
    if (!source) return null;

    // GitHub Release assets are replaced in place. A changing query string makes
    // GitHub's CDN revalidate while this Worker still keeps one Cache API entry.
    source.searchParams.set("v", String(Math.floor(Date.now() / (INDEX_CACHE_SECONDS * 1000))));
    const upstream = await fetch(source.toString());
    if (!upstream.ok) return null;

    response = new Response(upstream.body, {
      headers: {
        "Cache-Control": `public, max-age=${INDEX_CACHE_SECONDS}`,
        "Content-Type": "application/json; charset=utf-8",
      },
    });
    await cache.put(key, response.clone());
  }

  try {
    const index = (await response.json()) as CacheIndex;
    if (index.format !== 2 || !index.objects || typeof index.objects !== "object") return null;
    return index;
  } catch {
    return null;
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed\n", {
        status: 405,
        headers: { Allow: "GET, HEAD" },
      });
    }

    const { pathname } = new URL(request.url);
    if (pathname === "/nix-cache-info") {
      return new Response(request.method === "HEAD" ? null : "StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 30\n", {
        headers: {
          "Cache-Control": "public, max-age=86400",
          "Content-Type": "text/plain; charset=utf-8",
        },
      });
    }

    if (!isCachePath(pathname)) return new Response("Not found\n", { status: 404 });

    const index = await loadIndex(env.GITHUB_REPOSITORY);
    const object = index?.objects[pathname];
    if (!object) return new Response("Not found\n", { status: 404 });
    if (pathname.endsWith(".narinfo") && (!object.nar || !index?.objects[object.nar])) {
      return new Response("Incomplete cache entry\n", { status: 404 });
    }

    const location = githubAssetUrl(env.GITHUB_REPOSITORY, object.tag, object.asset);
    if (!location) return new Response("Invalid cache index entry\n", { status: 500 });

    return new Response(null, {
      status: 302,
      headers: { ...immutableRedirectHeaders, Location: location.toString() },
    });
  },
};
