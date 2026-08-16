{
  lib,
  optionalNeovimFeatures ? { },
  ...
}:
let
  gleamEnabled = lib.attrByPath [ "gleam" ] true optionalNeovimFeatures;
in
{
  # Gleam has a built-in LSP (gleam lsp) and formatter (gleam format)
  plugins.lsp.servers.gleam = {
    enable = gleamEnabled;
  };
}
