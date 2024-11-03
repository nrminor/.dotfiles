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

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, homebrew-core, homebrew-cask, ... }: 
  let
    configuration = { pkgs, config, ... }: {

      nixpkgs.config.allowUnfree = true;
    
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [ 
          pkgs.cmake
          pkgs.clang
          pkgs.neovim
      	  pkgs.helix
          pkgs.tmux
          pkgs.screen
          pkgs.zoxide
          pkgs.fastfetch
          pkgs.oh-my-zsh
          pkgs.nushell
          pkgs.du-dust
          pkgs.zellij
          pkgs.bat
          pkgs.fzf
          pkgs.yazi
          pkgs.ripgrep
          pkgs.zoxide
          pkgs.btop
          pkgs.just
          pkgs.ouch
          pkgs.watchexec
          pkgs.git
          pkgs.lazygit
          pkgs.zstd
          pkgs.curl
          pkgs.wget
          pkgs.lychee
          pkgs.python3
          pkgs.uv
          pkgs.ruff
          pkgs.pyright
          pkgs.rustc
          pkgs.rustfmt
          pkgs.cargo
          pkgs.rust-analyzer
          pkgs.rust-script
          pkgs.maturin
          pkgs.julia-bin
          pkgs.erlang
          pkgs.gleam
          pkgs.elixir
          pkgs.elixir-ls
          pkgs.ocaml
          pkgs.dune_3
          pkgs.dotter
          pkgs.marksman
          pkgs.seqkit
          pkgs.minimap2
          pkgs.bedtools
          pkgs.samtools
          pkgs.bcftools
          pkgs.prqlc
          pkgs.nextflow
          pkgs.duckdb
          pkgs.marimo
          pkgs.warp-terminal
        ];

      homebrew = {

        enable = true;
        brews = [
          "mas"
          "gcc"
        ];

        casks = [
          "warp"
          "arc"
          "zed"
          "positron"
          "slack"
          "basecamp"
          "docker"

        ];

        masApps = {
          "Bear" = 1091189122;
          "Spark" = 1176895641;
        };

        onActivation.cleanup = "zap";
        onActivation.autoUpdate = true;
        onActivation.upgrade = true;

      };

      fonts.packages = [
        (pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
      ];

      system.activationScripts.applications.text = let
        env = pkgs.buildEnv {
          name = "system-applications";
          paths = config.environment.systemPackages;
          pathsToLink = "/Applications";
        };

        system.activationScripts.deployDotfiles = {
          text = ''
            # clone my dotfiles repo if it's not already present
            if [ ! 0d "$HOME/.dotfiles" ]; then
              echo "Cloning dotfiles repository..."
              git clone https://github.com/nrminor/.dotfiles.git "$HOME/.dotfiles"
            fi

            # deploy the dotfiles
            cd "$HOME/.dotfiles"
            echo "Deploying dotfiles with dotter:"
            "${pkgs.dotter}/bin/dotter" deploy -f -y -v

          '';
        };

      darwinConfigurations.macbook = {
        # (...)
        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              # Install Homebrew under the default prefix
              enable = true;

              # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
              enableRosetta = true;

              # User owning the Homebrew prefix
              user = "nickminor";

              # Optional: Declarative tap management
              taps = {
                "homebrew/homebrew-core" = homebrew-core;
                "homebrew/homebrew-cask" = homebrew-cask;
              };

              # Optional: Enable fully-declarative tap management
              #
              # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
              mutableTaps = false;
            };
          }
        ];
      };
    in
        pkgs.lib.mkForce ''
          # Set up applications.
          echo "setting up /Applications .." >&2
          rm -rf /Applications/Nix\ Apps
          mkdir -p /Applications/Nix\ Apps
          find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
          while read src; do
            app_name=$(basename "$src")
            echo "copying $src" >&2
            ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
          done
        '';

      system.defaults = {
        # dock settings
        dock = {
          autohide = false;
          mineffect = "scale";
          orientation = "left";
          persistent-apps = [
            "/Applications/Arc.app"
            "/Applications/Bear.app"
            "/Applications/Spark.app"
            "/Applications/Basecamp 3.app"
            "/Applications/Slack.app"
            "/Applications/Warp.app"
            "/Applications/Zed.app"
          ];
          wvous-tr-corner = 1;
          wvous-tl-corner = 1;
          wvous-br-corner = 1;
          wvous-bl-corner = 1;
          tilesize = 32;
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
        screencapture.location = "~/Documents/screenshots";

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
      services.nix-daemon.enable = true;
      # nix.package = pkgs.nix;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Create /etc/zshrc that loads the nix-darwin environment.
      programs.zsh.enable = true;  # default shell on catalina
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
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
