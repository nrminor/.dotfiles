# Environment variables
#
# Compiler and linker configuration to help native builds
# find Nix-provided libraries and headers.
{ pkgs, ... }:

{
  environment.variables = {
    # Help pkg-config find Nix packages
    PKG_CONFIG_PATH = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
      pkgs.xz
      pkgs.zstd
      pkgs.libiconv
    ];

    # Linker flags for Nix libraries
    NIX_LDFLAGS = pkgs.lib.concatStringsSep " " [
      "-L${pkgs.bzip2}/lib"
      "-L${pkgs.xz}/lib"
      "-L${pkgs.zstd}/lib"
      "-L${pkgs.libiconv}/lib"
    ];

    # Compiler flags for Nix headers
    NIX_CFLAGS_COMPILE = pkgs.lib.concatStringsSep " " [
      "-I${pkgs.xz.dev}/include"
      "-I${pkgs.zstd.dev}/include"
      "-I${pkgs.libiconv.dev}/include"
    ];
  };
}
