{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_10_latest,
  pnpmConfigHook,
  nodejs,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "panerelay";
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "F-loat";
    repo = "panerelay";
    tag = "v${finalAttrs.version}";
    hash = "sha256-uHQuIwFbcps0m2wpeI9rE3c8dNRaQOW7/1nCD3g9io4=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10_latest;
    fetcherVersion = 3;
    hash = "sha256-Iidvz14tTt2WqvLcD0n6cFiWg36KVonEVAV9wD2Rt8g=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10_latest
    pnpmConfigHook
    makeWrapper
  ];

  env = {
    CI = "1";
    HUSKY = "0";
  };

  buildPhase = ''
    runHook preBuild

    # Build the CLI and the Native Messaging host plus their workspace deps.
    pnpm --filter @panerelay/bridge... build

    # The CLI is published as plain ESM with workspace imports; bundle it so
    # the package does not need a pnpm node_modules tree at runtime.
    pnpm exec esbuild packages/cli/dist/cli.js \
      --bundle \
      --platform=node \
      --format=esm \
      --target=node20 \
      --outfile=panerelay-cli.mjs

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/panerelay/dist $out/bin

    # Keep the published layout (dist/cli.js): the CLI reads
    # ../package.json relative to import.meta.url.
    cp panerelay-cli.mjs $out/libexec/panerelay/dist/cli.mjs
    cp packages/bridge/dist/native-host.bundle.cjs $out/libexec/panerelay/native-host.bundle.cjs
    cp packages/bridge/dist/native-host.bundle.cjs.map $out/libexec/panerelay/native-host.bundle.cjs.map

    # The CLI reads its version from ../package.json next to the bundle.
    cat > $out/libexec/panerelay/package.json <<EOF
    {
      "name": "@panerelay/cli",
      "version": "${finalAttrs.version}",
      "type": "module"
    }
    EOF

    makeWrapper ${nodejs}/bin/node $out/bin/panerelay \
      --add-flags $out/libexec/panerelay/dist/cli.mjs
    makeWrapper ${nodejs}/bin/node $out/bin/panerelay-native-host \
      --add-flags $out/libexec/panerelay/native-host.bundle.cjs

    runHook postInstall
  '';

  meta = {
    description = "Bridge AI agents to an existing Chrome or Edge browser";
    homepage = "https://github.com/F-loat/panerelay";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "panerelay";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
