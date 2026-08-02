# Homebrew runtime for macOS
#
# nix-homebrew continues to provide the Homebrew executable while package
# declarations migrate from nix-darwin to mise and native application updaters.
{ username, ... }:

{
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    user = username;
    autoMigrate = true;
  };
}
