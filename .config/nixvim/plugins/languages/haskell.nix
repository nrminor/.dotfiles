{
  # Haskell LSP — assumes haskell-language-server is on PATH via ghcup.
  # We don't install HLS via nix because:
  #   1. It compiles from source (~30+ min)
  #   2. It must match the exact GHC version of your project
  #   3. ghcup manages both GHC and HLS together
  # If HLS isn't installed, nvim works fine — LSP just won't attach.
  plugins.lsp.servers.hls = {
    enable = true;
    package = null;
    installGhc = false;
  };
}
