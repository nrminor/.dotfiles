{
  # Requires zig and zls to be installed (uncomment in common/packages.nix)
  plugins.lsp.servers.zls = {
    enable = true;
    package = null;
  };
}
