{
  description = "NRM Darwin system flake for configuring a new Apple computer.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      ...
    }:
    let
      configuration =
        { pkgs, config, ... }:
        {

          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = [
            pkgs.cmake
            pkgs.nixd
            pkgs.nixfmt-rfc-style
            pkgs.mkalias
            pkgs.neovim
            pkgs.helix
            # pkgs.ghostty
            pkgs.tree
            pkgs.zoxide
            pkgs.fastfetch
            pkgs.starship
            pkgs.atuin
            pkgs.carapace
            pkgs.skhd
            pkgs.nushell
            pkgs.du-dust
            pkgs.zellij
            pkgs.bat
            pkgs.fzf
            pkgs.yazi
            pkgs.ripgrep
            pkgs.poppler
            pkgs.ffmpeg
            pkgs.imagemagick
            pkgs.xclip
            pkgs.p7zip
            pkgs.fd
            pkgs.jq
            pkgs.btop
            pkgs.just
            pkgs.ouch
            pkgs.watchexec
            pkgs.git
            pkgs.lazygit
            pkgs.zstd
            pkgs.eza
            pkgs.curl
            pkgs.wget
            pkgs.dotter
            pkgs.lychee
            pkgs.bash-language-server
            pkgs.shfmt
            pkgs.awk-language-server
            pkgs.terraform
            pkgs.terraform-ls
            pkgs.hclfmt
            pkgs.hcl2json
            pkgs.go
            pkgs.gopls
            pkgs.gotools
            pkgs.golangci-lint
            pkgs.golangci-lint-langserver
            pkgs.zig
            pkgs.zls
            pkgs.docker-ls
            pkgs.yaml-language-server
            pkgs.lua
            pkgs.luau
            pkgs.luajit
            pkgs.lua-language-server
            pkgs.stylua
            pkgs.duckdb
            pkgs.python3
            pkgs.uv
            pkgs.ruff
            pkgs.basedpyright
            pkgs.marimo
            pkgs.rustup
            pkgs.rust-script
            pkgs.maturin
            pkgs.openjdk
            pkgs.jdk
            pkgs.jdt-language-server
            pkgs.nextflow
            pkgs.vscode-langservers-extracted
            pkgs.superhtml
            pkgs.erlang
            pkgs.rebar3
            pkgs.gleam
            pkgs.ocaml
            pkgs.opam
            pkgs.ocamlformat_0_26_1
            pkgs.dune_3
            pkgs.marksman
            pkgs.typst
            pkgs.typstfmt
            pkgs.tinymist
            pkgs.quarto
            pkgs.seqkit
            pkgs.minimap2
            pkgs.bedtools
            pkgs.samtools
            pkgs.bcftools
          ];

          homebrew = {

            enable = true;
            brews = [
              "mas"
              "gcc"
              "llvm"
              "libiconv"
              "sevenzip"
            ];

            casks = [
              "arc"
              "zed"
              "visual-studio-code"
              "slack"
              "basecamp"
              "discord"
              "docker"
              "zoom"
              "raycast"
              "ghostty"
              "font-symbols-only-nerd-font"
            ];

            masApps = {
              "Bear" = 1091189122;
              "Spark" = 1176895641;
              "HazeOver" = 430798174;
              "Amphetamine" = 937984704;
              "Bartender" = 441258766;
              "Smart Countdown Timer" = 1410709951;
              "Xcode" = 497799835;
            };

            onActivation.cleanup = "zap";
            onActivation.autoUpdate = true;
            onActivation.upgrade = true;

          };

          system.defaults = {
            # dock settings
            dock = {
              autohide = false;
              mineffect = "scale";
              orientation = "left";
              persistent-apps = [
                "/Applications/Arc.app"
                "/Applications/Spark.app"
                "/Applications/Bear.app"
                "/Applications/Slack.app"
                "/Applications/Ghostty.app"
              ];
              wvous-tr-corner = 1;
              wvous-tl-corner = 1;
              wvous-br-corner = 1;
              wvous-bl-corner = 1;
              tilesize = 28;
              show-recents = false;
              show-process-indicators = true;
              persistent-others = [
                "/Users/nickminor/Downloads"
              ];
            };

            # finder settings
            finder = {
              AppleShowAllExtensions = false;
              AppleShowAllFiles = true;
              ShowPathbar = true;
              FXPreferredViewStyle = "Nlsv";
              FXEnableExtensionChangeWarning = false;
              FXDefaultSearchScope = "SCcf";
              CreateDesktop = false;
              _FXSortFoldersFirst = true;
            };

            # login window settings
            loginwindow = {
              autoLoginUser = "nickminor";
            };

            # Miscellaneous other settings
            menuExtraClock.ShowSeconds = true;
            screencapture.location = "/Users/nickminor/Documents/screenshots";

            # Custom preferences
            CustomUserPreferences = {

              # additional finder settings
              "com.apple.finder" = {
                ShowExternalHardDrivesOnDesktop = false;
                ShowHardDrivesOnDesktop = false;
                ShowMountedServersOnDesktop = false;
                ShowRemovableMediaOnDesktop = false;
                _FXSortFoldersFirst = true;
                FXDefaultSearchScope = "SCcf";
              };

              # additional desktop settings
              "com.apple.desktopservices" = {
                # Avoid creating .DS_Store files on network or USB volumes
                DSDontWriteNetworkStores = true;
                DSDontWriteUSBStores = true;
              };

              # tracking settings
              "com.apple.AdLib" = {
                allowApplePersonalizedAdvertising = false;
              };

              # no, you don't need to keep the printer app open when I'm done printing
              "com.apple.print.PrintingPrefs" = {
                # Automatically quit printer app once the print jobs complete
                "Quit When Finished" = true;
              };

              # look for updates daily
              "com.apple.SoftwareUpdate" = {
                AutomaticCheckEnabled = true;
                # Check for software updates daily, not just once per week
                ScheduleFrequency = 1;
                # Download newly available updates in background
                AutomaticDownload = 1;
                # Install System data files & security updates
                CriticalUpdateInstall = 1;
              };

            };

          };

          # Auto upgrade nix package and the daemon service.
          # services.nix-daemon.enable = true;
          # nix.package = pkgs.nix;

          # allow closed-source install
          nixpkgs.config.allowUnfree = true;

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";
          nix = {
            extraOptions = ''
              experimental-features = nix-command flakes
            '';
          };

          # Create /etc/zshrc that loads the nix-darwin environment.
          programs.zsh.enable = true; # default shell on catalina
          # programs.fish.enable = true;

          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 5;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = "aarch64-darwin";

          # install the jetbrains font
          fonts.packages = [
            pkgs.nerd-fonts.jetbrains-mono
          ];

          # run some activation scripts post-setup
          system.activationScripts = {

            applications.text =
              let
                env = pkgs.buildEnv {
                  name = "system-applications";
                  paths = config.environment.systemPackages;
                  pathsToLink = "/Applications";
                };
              in
              pkgs.lib.mkForce ''
                # Set up applications.
                echo "setting up /Applications..." >&2
                rm -rf /Applications/Nix\ Apps
                mkdir -p /Applications/Nix\ Apps
                find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
                while read -r src; do
                  app_name=$(basename "$src")
                  echo "copying $src" >&2
                  ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
                done

                # accepting xcode license
                sudo xcodebuild -license accept

                echo "Setting up directories..." >&2
                if [ ! -d "/Users/nickminor/Documents/bioinformatics" ]; then
                  echo "Creating bioinformatics directory..." >&2
                  mkdir -p "/Users/nickminor/Documents/bioinformatics"
                  chown -R nickminor:staff /Userss/nickminor/Documents/bioinformatics
                fi

                if [ ! -d "/Users/nickminor/Documents/hacking" ]; then
                  echo "Creating hacking directory..." >&2
                  mkdir -p "/Users/nickminor/Documents/hacking"
                  chown -R nickminor:staff /Users/nickminor/Documents/hacking
                fi

                if [ ! -d "/Users/nickminor/Documents/screenshots" ]; then
                  echo "Creating screenshots directory..." >&2
                  mkdir -p "/Users/nickminor/Documents/screenshots"
                  chown -R nickminor:staff /Users/nickminor/Documents/screenshots
                fi

                echo "Looking for dotfiles directory..."
                # Clone my dotfiles repo if it's not already present
                if [ ! -d "/Users/nickminor/.dotfiles" ]; then
                  echo "Cloning dotfiles repository..."
                  git clone https://github.com/nrminor/.dotfiles.git "/Users/nickminor/.dotfiles"
                else
                  echo "dotfiles directory found."
                fi

                # Deploy the dotfiles
                cd "/Users/nickminor/.dotfiles"
                echo "Deploying dotfiles with dotter..."
                sudo -u nickminor "${pkgs.dotter}/bin/dotter" deploy -f -y -v

                # setup positron application directory
                # echo "Making positron directory..."
                # sudo -u nickminor mkdir -p "/Users/nickminor/Library/Application Support/Positron"
                # chown -R nickminor:staff "/Users/nickminor/Library/Application Support/Positron"
                # sudo -u nickminor chmod +rw "/Users/nickminor/Library/Application Support/Positron"
                # sudo -u nickminor mkdir -p /Users/nickminor/.positron/extensions
                # chown -R nickminor:staff /Users/nickminor/.positron/extensions
                # sudo -u nickminor chmod +rw /Users/nickminor/.positron/extensions

                # # install vscode/positron extensions
                # echo "Installing positron extensions..."
                # cat .config/positron/extensions.txt \
                # | xargs -L 1 sudo -u nickminor /Applications/Positron.app/Contents/Resources/app/bin/code \
                # --force --install-extension
              '';

          };

        };
    in
    {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#starter
      darwinConfigurations."starter" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              user = "nickminor";
              autoMigrate = true;
            };
          }
        ];
      };

      # Expose the package set, including overlays, for convenience.
      darwinPackages = self.darwinConfigurations."starter".pkgs;

    };
}
