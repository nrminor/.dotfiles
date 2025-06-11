with import <nixpkgs> { };

pkgs.mkShell {
  buildInputs = [
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.CoreServices
    pkgconfig
    openssl
  ];

  shellHook = ''
    export LIBRARY_PATH="${pkgs.libiconv}/lib"
    export CPATH="${pkgs.libiconv}/include"
  '';
}
