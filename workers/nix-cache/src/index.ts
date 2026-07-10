interface CacheObject {
  asset: string;
  tag: string;
}

interface Env {
  GITHUB_REPOSITORY: string;
  NIX_CACHE_INDEX: KVNamespace;
}

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

function githubAssetUrl(repository: string, object: CacheObject): URL | null {
  const [owner, repo, ...rest] = repository.split("/");
  if (!owner || !repo || rest.length > 0 || !isSafeAssetPart(object.tag) || !isSafeAssetPart(object.asset)) {
    return null;
  }

  return new URL(
    `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/releases/download/${encodeURIComponent(object.tag)}/${encodeURIComponent(object.asset)}`,
  );
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

    if (!isCachePath(pathname)) {
      return new Response("Not found\n", { status: 404 });
    }

    const object = await env.NIX_CACHE_INDEX.get<CacheObject>(`path:${pathname}`, "json");
    if (!object) {
      return new Response("Not found\n", { status: 404 });
    }

    const location = githubAssetUrl(env.GITHUB_REPOSITORY, object);
    if (!location) {
      return new Response("Invalid cache index entry\n", { status: 500 });
    }

    return new Response(null, {
      status: 302,
      headers: {
        ...immutableRedirectHeaders,
        Location: location.toString(),
      },
    });
  },
};
