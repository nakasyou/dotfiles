{
  lib,
  buildNpmPackage,
  nodejs_24,
  runCommand,
  src,
  stdenv,
}:

let
  preparedSrc = runCommand "twitter-api-safe-relay-mcp-source" { } ''
    cp -R ${src} $out
    chmod -R u+w $out
    cp ${./twitter-api-safe-relay-mcp-package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "twitter-api-safe-relay-mcp";
  version = "0.1.2";

  src = preparedSrc;
  nodejs = nodejs_24;
  npmDepsHash = if stdenv.hostPlatform.isDarwin then
    "sha256-c0Vq+/IwoaPmJJiAoqTfmj6WEOzh+ktTwigkZ/uBC34="
  else
    "sha256-lWgAM838stZDMLj8LV0O2XkVtAC7WEqbEs+oRJjKJHc=";

  npmBuildScript = "build";

  meta = {
    description = "MCP server for twitter_api_safe_relay";
    homepage = "https://github.com/nakasyou/twitter_api_safe_relay_mcp";
    license = lib.licenses.mit;
    mainProgram = "twitter_api_safe_relay_mcp";
    platforms = lib.platforms.unix;
  };
}
