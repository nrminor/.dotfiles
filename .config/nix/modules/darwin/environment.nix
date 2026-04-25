# Environment variables
#
# Compiler and linker configuration to help native builds
# find Nix-provided libraries and headers.
{ pkgs, ... }:

{
  environment.variables = {
    # Use Nix's pkgconf binary for native builds.
    PKG_CONFIG = "pkgconf";

    # Help pkg-config find Nix packages. Nix packages are not entirely
    # consistent about whether .pc files live under lib/pkgconfig or
    # share/pkgconfig, so include both layouts.
    PKG_CONFIG_PATH = pkgs.lib.concatStringsSep ":" [
      (pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
        pkgs.zlib
        pkgs.xz
        pkgs.zstd
        pkgs.libiconv
      ])
      (pkgs.lib.makeSearchPathOutput "dev" "share/pkgconfig" [
        pkgs.zlib
        pkgs.xz
        pkgs.zstd
        pkgs.libiconv
      ])
    ];

    # Linker flags for Nix libraries
    NIX_LDFLAGS = pkgs.lib.concatStringsSep " " [
      "-L${pkgs.bzip2}/lib"
      "-L${pkgs.xz}/lib"
      "-L${pkgs.zstd}/lib"
      "-L${pkgs.zlib}/lib"
      "-L${pkgs.libiconv}/lib"
    ];

    # Compiler flags for Nix headers
    NIX_CFLAGS_COMPILE = pkgs.lib.concatStringsSep " " [
      "-I${pkgs.xz.dev}/include"
      "-I${pkgs.zstd.dev}/include"
      "-I${pkgs.zlib.dev}/include"
      "-I${pkgs.libiconv.dev}/include"
    ];
  };
}
