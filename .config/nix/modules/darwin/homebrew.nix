# Homebrew configuration for macOS
#
# Manages Homebrew installation (via nix-homebrew) and declares
# all brews, casks, and Mac App Store apps.
{
  inputs,
  username,
  ...
}:

{
  # nix-homebrew: manages the Homebrew installation itself
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    user = username;
    autoMigrate = true;
    taps = {
      "steipete/tap" = inputs.homebrew-steipete;
    };
  };

  # homebrew: what to install via Homebrew
  homebrew = {
    enable = true;

    # CLI tools via 'brew install'
    brews = [
      "mas"
      "gcc"
      "lld"
      "llvm"
      "libiconv"
      # "zlib"
      # "pkgconf"
      # "xz"
      # "bzip2"
      "sevenzip"
      "opam"
    ];

    # GUI applications via 'brew install --cask'
    casks = [
      "ghostty"
      "arc"
      "raycast"
      "figma"
      "slack"
      "discord"
      "signal"
      "visual-studio-code"
      "rstudio"
      "docker-desktop"
      "zoom"
      "font-symbols-only-nerd-font"
      "steipete/tap/repobar"
    ];

    # Mac App Store apps (IDs from 'mas search <name>')
    masApps = {
      "Bear" = 1091189122;
      "Instapaper" = 288545208;
      "Spark" = 1176895641;
      "HazeOver" = 430798174;
      "Amphetamine" = 937984704;
      "Bartender" = 441258766;
      "Smart Countdown Timer" = 1410709951;
      "Xcode" = 497799835;
    };

    # Behavior on darwin-rebuild
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
  };
}
