{
  lib,
  stdenvNoCC,
  nodejs_24,
  pnpm_11,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
  src,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "twitter-api-safe-relay";
  version = "unstable-2026-07-20";

  inherit src;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 3;
    hash = "sha256-wFpa28OzVfWO3wXUyrceOxx7MTrsZAv3hh/1PkO9aXc=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_24
    pnpm_11
    pnpmConfigHook
  ];

  env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

  postPatch = ''
    substituteInPlace packages/server/src/server.ts \
      --replace-fail \
        'serve({ fetch: app.fetch, port: settings.port });' \
        'serve({ fetch: app.fetch, port: settings.port, hostname: "127.0.0.1" });'
  '';

  buildPhase = ''
    runHook preBuild
    pnpm --filter twitter-api-safe-relay build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    appDir="$out/lib/twitter-api-safe-relay"
    mkdir -p "$appDir" "$out/bin"
    cp -R node_modules "$appDir/node_modules"
    cp -R packages examples "$appDir/"

    makeWrapper ${lib.getExe nodejs_24} "$out/bin/twitter-api-safe-relay" \
      --add-flags "$appDir/packages/server/dist/server.js" \
      --set NODE_ENV production \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1

    runHook postInstall
  '';

  meta = {
    description = "HTTP relay server for safe Twitter/X web API requests";
    homepage = "https://github.com/fa0311/twitter_api_safe_relay";
    license = lib.licenses.mit;
    mainProgram = "twitter-api-safe-relay";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
})
