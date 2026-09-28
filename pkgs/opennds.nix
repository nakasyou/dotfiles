{ lib
, fetchFromGitHub
, libmicrohttpd
, stdenv
}:

stdenv.mkDerivation rec {
  pname = "opennds";
  version = "11.0.0";

  src = fetchFromGitHub {
    owner = "openNDS";
    repo = "openNDS";
    rev = "v${version}";
    hash = "sha256-yfSUGWaMxrUCQhipcP4Kw9rIzDWH6mWz8jG91t/FFgk=";
  };

  buildInputs = [ libmicrohttpd ];

  postPatch = ''
    substituteInPlace $(grep -rl '/usr/lib/opennds' src forward_authentication_service) \
      --replace-quiet '/usr/lib/opennds' "$out/libexec/opennds"
    substituteInPlace $(grep -rl '/usr/bin/opennds' src forward_authentication_service) \
      --replace-quiet '/usr/bin/opennds' "$out/bin/opennds"
  '';

  installFlags = [ "DESTDIR=$(out)" ];

  postInstall = ''
    mkdir -p "$out/bin" "$out/libexec" "$out/share/opennds"
    mv "$out/usr/bin"/* "$out/bin/"
    mv "$out/usr/lib/opennds" "$out/libexec/opennds"
    mv "$out/etc/opennds/htdocs" "$out/share/opennds/htdocs"
    mv "$out/etc/opennds"/*.php "$out/share/opennds/"
    install -Dm644 resources/opennds.conf "$out/share/opennds/opennds.conf"
    rm -rf "$out/usr" "$out/etc"
    patchShebangs "$out/libexec/opennds"
  '';

  meta = {
    description = "Captive portal gateway and network demarcation service";
    homepage = "https://github.com/openNDS/openNDS";
    license = lib.licenses.gpl2Only;
    mainProgram = "opennds";
    platforms = lib.platforms.linux;
  };
}
