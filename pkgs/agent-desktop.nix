{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "agent-desktop";
  version = "1.3.1";

  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-desktop";
    tag = "v${version}";
    hash = "sha256-/SZ2AR1ww8pcUeffEk1Np24M3roiS1yXNQyCle82T5Q=";
  };

  cargoHash = "sha256-VlPyMlUtTm7v3AHbCiippZLAOGM4yH3+Oc2B9ZAOJ1g=";

  # Build only the Linux CLI and its clipboard owner helper. The workspace's
  # default members also include the macOS and Windows adapters.
  cargoBuildFlags = [
    "-p" "agent-desktop"
    "-p" "agent-desktop-linux"
  ];

  # The integration tests need a live AT-SPI/D-Bus desktop session.
  doCheck = false;

  meta = {
    description = "Computer use for AI agents through the OS accessibility tree";
    homepage = "https://github.com/vercel-labs/agent-desktop";
    license = lib.licenses.asl20;
    mainProgram = "agent-desktop";
    platforms = lib.platforms.linux;
  };
}
