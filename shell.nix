with import <nixpkgs> {};

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    zig
    pkg-config
    wayland
    wayland-scanner
    wayland-protocols
    libGL
    libxkbcommon
  ];
}
