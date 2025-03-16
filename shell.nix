let
  pkgs = import <nixpkgs> { };
  unstable = import (pkgs.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "6607cf789e541e7873d40d3a8f7815ea92204f32";
    hash = "sha256-cPfs8qMccim2RBgtKGF+x9IBCduRvd/N5F4nYpU0TVE=";
  }){ config = pkgs.config; };
in pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    unstable.zig_0_14
    pkg-config
    wayland
    wayland-scanner
    wayland-protocols
    libGL
    libxkbcommon
  ];
}
