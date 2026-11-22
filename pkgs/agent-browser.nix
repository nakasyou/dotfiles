{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  chromium,
  which,
}:

rustPlatform.buildRustPackage rec {
  pname = "agent-browser";
  version = "0.43.0";

  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    tag = "v${version}";
    hash = "sha256-+hmbSIgTqs5uZW7j0hAhz/9Fd24Np80DfoccqN4fGF4=";
  };

  # The Rust CLI lives in the `cli` workspace member.
  sourceRoot = "${src.name}/cli";

  cargoHash = "sha256-MKTL/1k3gvGB0ylg4iAi2WyZ1sNrEpBJVtvjc7J6maA=";

  nativeBuildInputs = [ makeWrapper ];

  # rust-embed expands `../packages/dashboard/out` during macro expansion,
  # before cli/build.rs gets a chance to create its placeholder. Provide the
  # placeholder up front so a Rust-only build can embed a minimal dashboard.
  postUnpack = ''
    chmod -R u+w source/packages/dashboard
    mkdir -p source/packages/dashboard/out
    cat > source/packages/dashboard/out/index.html <<'EOF'
    <!DOCTYPE html><html><body><p>Dashboard not built. Run: cd packages/dashboard &amp;&amp; pnpm build</p></body></html>
    EOF
  '';

  # `which_exists` shells out to `which` at runtime. Pin it so the CLI does not
  # depend on `which` being present in the user's PATH.
  postPatch = ''
    substituteInPlace src/doctor/helpers.rs src/install.rs \
      --replace-fail '"which"' '"${lib.getExe which}"'
  '';

  # The Rust-only build embeds a placeholder dashboard (building the Next.js
  # dashboard needs a full pnpm workspace build). The CLI, MCP server and
  # bundled skills are fully functional.
  # Unit tests spawn browser/daemon helpers and need a writable HOME.
  doCheck = false;

  postInstall = ''
    cp -r ../skills $out/skills
    cp -r ../skill-data $out/skill-data

    # Chrome for Testing / Playwright downloads do not run on NixOS. Use the
    # nixpkgs Chromium by default, while still allowing an explicit override.
    wrapProgram $out/bin/agent-browser \
      --set-default AGENT_BROWSER_EXECUTABLE_PATH "${chromium}/bin/chromium"
  '';

  meta = {
    description = "Browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "agent-browser";
    platforms = lib.platforms.linux;
  };
}
