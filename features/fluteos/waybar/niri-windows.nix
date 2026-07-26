{ lib, buildGoModule, fetchFromGitHub, pkg-config, gtk3 }:

buildGoModule rec {
  pname = "fluteos-waybar-windows";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "calico32";
    repo = "waybar-niri-windows";
    # 17828f9 (2026-03-27) pulls in two GTK-thread-safety fixes not in the old
    # pin (c0cfe95): "prevent SIGSEGV from GC finalizers racing with GTK main
    # thread" and "prevent SIGSEGV from double g_object_unref in Go finalizers".
    # These fix the recurring waybar coredumps (Go runtime sighandler firing
    # inside GTK widget/CSS calls).
    rev = "17828f901b56250e88acb421054b87ef311d8f3a";
    sha256 = "sha256-bnPxKRugnIGj/Od8R+6PAl0MRhhl361H9rYydCWQ/yw=";
  };

  vendorHash = "sha256-jK87vZYfUe8znk65SmJ1mN8qP5K3dtt950hKGWTYXs4=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ gtk3 ];

  buildPhase = ''
    runHook preBuild
    go build -buildmode=c-shared -o waybar-niri-windows.so ./main
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp waybar-niri-windows.so $out/lib/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Waybar module that shows a graphical minimap of windows on the current niri workspace";
    homepage = "https://github.com/calico32/waybar-niri-windows";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
