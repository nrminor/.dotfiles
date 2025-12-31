{
  description = "NRM Darwin system flake for configuring a new Apple computer.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
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
    homebrew-steipete = {
      url = "github:steipete/homebrew-tap";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      nixpkgs-stable,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      homebrew-steipete,
      ...
    }:
    let
      configuration =
        { pkgs, config, ... }:
        let
          primaryUser = config.system.primaryUser or "nickminor";
          userHome = "/Users/${primaryUser}";
        in

        {
          programs.direnv = {
            enable = true;
            nix-direnv.enable = true;
          };

          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = [

            # system and command line utilities
            pkgs.cmake
            pkgs.clang
            pkgs.libiconv
            pkgs.pkg-config
            pkgs.pkgconf
            pkgs.zlib
            pkgs.llvm
            pkgs.gettext
            pkgs.nixd
            pkgs.nixfmt-rfc-style
            pkgs.nil
            pkgs.mkalias
            pkgs.neovim
            pkgs.helix
            # pkgs.ghostty
            pkgs.less
            pkgs.tailspin
            pkgs.tree
            pkgs.parallel
            pkgs.zoxide
            pkgs.fastfetch
            pkgs.starship
            pkgs.atuin
            pkgs.hyperfine
            pkgs.carapace
            pkgs.skhd
            pkgs.nushell
            pkgs.nushellPlugins.polars
            # pkgs.nushellPlugins.units
            pkgs.nushellPlugins.query
            pkgs.nushellPlugins.highlight
            pkgs.nushellPlugins.gstat
            pkgs.nushellPlugins.formats
            pkgs.topiary
            pkgs.dust
            pkgs.dua
            pkgs.zellij
            pkgs.bat
            pkgs.fzf
            pkgs.fzf-make
            pkgs.yazi
            pkgs.yaziPlugins.sudo
            pkgs.yaziPlugins.starship
            pkgs.yaziPlugins.rsync
            pkgs.yaziPlugins.ouch
            pkgs.yaziPlugins.smart-filter
            pkgs.yaziPlugins.smart-enter
            pkgs.yaziPlugins.mount
            pkgs.yaziPlugins.mediainfo
            pkgs.yaziPlugins.chmod
            pkgs.yaziPlugins.git
            pkgs.yaziPlugins.lazygit
            pkgs.yaziPlugins.gitui
            pkgs.yaziPlugins.duckdb
            pkgs.ripgrep
            pkgs.ripgrep-all
            pkgs.tokei
            pkgs.poppler
            pkgs.ffmpeg
            pkgs.imagemagick
            pkgs.graphviz
            pkgs.xclip
            pkgs.p7zip
            pkgs.ncspot
            pkgs.fd
            pkgs.jq
            pkgs.btop
            pkgs.bottom
            pkgs.just
            pkgs.mask
            pkgs.direnv
            pkgs.mise
            pkgs.devbox
            pkgs.ouch
            pkgs.watchexec
            pkgs.git
            pkgs.lazygit
            pkgs.gitui
            pkgs.difftastic
            pkgs.pre-commit
            pkgs.wrkflw
            pkgs.jujutsu
            pkgs.lazyjj
            pkgs.jjui
            pkgs.mergiraf
            pkgs.xz
            pkgs.zstd
            pkgs.bzip2
            pkgs.eza
            pkgs.curl
            pkgs.wget
            pkgs.dotter
            pkgs.lychee
            pkgs.gnuplot
            pkgs.wiki-tui
            pkgs.tlrc

            # bash/zsh
            nixpkgs-stable.legacyPackages.${pkgs.system}.bash-language-server
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.zsh-autosuggestions
            pkgs.zsh-syntax-highlighting

            # awk
            pkgs.gawk
            pkgs.awk-language-server

            # rust
            pkgs.rustup
            pkgs.mdbook
            pkgs.rust-script
            pkgs.evcxr
            pkgs.maturin
            pkgs.bacon
            pkgs.rusty-man
            pkgs.cargo-msrv
            pkgs.cargo-sort
            pkgs.cargo-audit
            pkgs.cargo-info
            pkgs.cargo-fuzz
            pkgs.cargo-dist
            pkgs.cargo-shear
            pkgs.cargo-wizard
            pkgs.cargo-show-asm
            pkgs.cargo-generate
            pkgs.cargo-readme
            pkgs.reindeer
            pkgs.crate2nix
            pkgs.dioxus-cli

            # sql stuff
            pkgs.duckdb
            pkgs.tabiew
            pkgs.visidata

            # python
            pkgs.python313
            # pkgs.uv
            # pkgs.pixi
            pkgs.ruff
            # pkgs.ty
            pkgs.basedpyright
            pkgs.pylyzer
            nixpkgs-stable.legacyPackages.${pkgs.system}.marimo
            # pkgs.python313Packages.radian
            pkgs.python313Packages.ipython
            pkgs.python313Packages.notebook
            # pkgs.python313Packages.marimo
            pkgs.python313Packages.jupyter-core
            pkgs.python313Packages.jupyterlab
            pkgs.python313Packages.ipykernel
            pkgs.python313Packages.polars
            pkgs.python313Packages.biopython
            pkgs.python313Packages.pysam

            # R
            # pkgs.R
            # pkgs.rstudio
            pkgs.rPackages.languageserver
            pkgs.air-formatter
            # pkgs.rPackages.tidyverse
            pkgs.rPackages.BiocManager

            # toml
            pkgs.taplo

            # go
            pkgs.go
            pkgs.gopls
            pkgs.gotools
            pkgs.goreleaser

            # zig
            # pkgs.zig
            # pkgs.zls

            # docker
            pkgs.docker-ls

            # yaml
            pkgs.yaml-language-server

            # lua
            pkgs.lua
            pkgs.luau
            pkgs.luajit
            pkgs.lua-language-server
            pkgs.stylua

            # java (and also nextflow)
            pkgs.openjdk
            pkgs.jdk
            pkgs.jdt-language-server
            pkgs.nextflow

            # HTML, JS/TS, and other web stuff
            # pkgs.vscode-langservers-extracted
            pkgs.superhtml
            pkgs.fnm
            # pkgs.nodejs_23
            # pkgs.deno
            # pkgs.bun
            # pkgs.typescript
            # pkgs.typescript-language-server
            # pkgs.javascript-typescript-langserver
            # pkgs.biome
            # pkgs.oxlint
            # pkgs.rescript-language-server

            # OCaml
            pkgs.ocaml
            # pkgs.opam

            # Haskell
            # pkgs.haskellPackages.ghcup
            # pkgs.haskell-language-server
            # pkgs.stylish-haskell
            # pkgs.haskellPackages.fourmolu

            # Lean 4
            # pkgs.lean4

            # BEAM VM ecosystem
            pkgs.erlang
            pkgs.rebar3
            pkgs.gleam
            pkgs.beam28Packages.elixir
            pkgs.beam28Packages.elixir-ls

            # authoring tools (e.g. typst, latex, quarto, markdown)
            pkgs.marksman
            pkgs.markdown-oxide
            pkgs.rumdl
            pkgs.typst
            pkgs.typstyle
            pkgs.tinymist
            pkgs.typstyle
            # pkgs.quarto
            pkgs.presenterm
            pkgs.d2

            # bioinformatics tools
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

            casks = [
              "arc"
              "visual-studio-code"
              "docker-desktop"
              "slack"
              "discord"
              "zoom"
              "raycast"
              "ghostty"
              "figma"
              "font-symbols-only-nerd-font"
              "steipete/tap/repobar"
            ];

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

            onActivation.cleanup = "zap";
            onActivation.autoUpdate = true;
            onActivation.upgrade = true;

          };

          system.primaryUser = "nickminor";
          system.defaults = {
            # dock settings
            dock = {
              autohide = false;
              mineffect = "scale";
              orientation = "right";
              persistent-apps = [
                "/Applications/Arc.app"
                "/Applications/Superhuman.app"
                "/Applications/Bear.app"
                # "/Applications/Instapaper.app"
                "/Applications/Ghostty.app"
                "/Applications/Figma.app"
              ];
              wvous-tr-corner = 1;
              wvous-tl-corner = 1;
              wvous-br-corner = 1;
              wvous-bl-corner = 1;
              tilesize = 28;
              show-recents = false;
              show-process-indicators = true;
              persistent-others = [
                {
                  folder = {
                    path = "${userHome}/Downloads";
                    arrangement = "date-added";
                    displayas = "stack";
                    showas = "automatic";
                  };
                }
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
              autoLoginUser = primaryUser;
            };

            # Miscellaneous other settings
            menuExtraClock.ShowSeconds = true;
            screencapture.location = "${userHome}/Documents/screenshots";

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
              # "com.apple.AdLib" = {
              #  allowApplePersonalizedAdvertising = false;
              # };

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

            # Automatic garbage collection
            gc = {
              automatic = true;
              interval = {
                Day = 7;
              }; # Run weekly
              options = "--delete-older-than 30d";
            };
          };

          # Create /etc/zshrc that loads the nix-darwin environment.
          programs.zsh = {
            enable = true;
            enableCompletion = true;
            promptInit = "";

            interactiveShellInit = ''
              source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
              source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
            '';

          };
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
                  pathsToLink = [ "/Applications" ];
                };
                # Get the primary user from system.primaryUser setting
                primaryUser = config.system.primaryUser or "nickminor";
                userHome = "/Users/${primaryUser}";
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
                if [ ! -d "${userHome}/Documents/bioinformatics" ]; then
                  echo "Creating bioinformatics directory..." >&2
                  mkdir -p "${userHome}/Documents/bioinformatics"
                  chown -R nickminor:staff ${userHome}/Documents/bioinformatics
                fi

                if [ ! -d "${userHome}/Documents/hacking" ]; then
                  echo "Creating hacking directory..." >&2
                  mkdir -p "${userHome}/Documents/hacking"
                  chown -R nickminor:staff ${userHome}/Documents/hacking
                fi

                if [ ! -d "${userHome}/Documents/screenshots" ]; then
                  echo "Creating screenshots directory..." >&2
                  mkdir -p "${userHome}/Documents/screenshots"
                  chown -R nickminor:staff ${userHome}/Documents/screenshots
                fi

                echo "Looking for dotfiles directory..."
                # Clone my dotfiles repo if it's not already present
                if [ ! -d "${userHome}/.dotfiles" ]; then
                  echo "Cloning dotfiles repository..."
                  git clone https://github.com/nrminor/.dotfiles.git "${userHome}/.dotfiles"
                else
                  echo "dotfiles directory found."
                fi

                # Deploy the dotfiles
                cd "${userHome}/.dotfiles"
                echo "Deploying dotfiles with dotter..."
                sudo -u ${primaryUser} env HOME=/Users/${primaryUser} "${pkgs.dotter}/bin/dotter" deploy -f -y -v
              '';

            yaziPlugins.text =
              let
                primaryUser = config.system.primaryUser or "nickminor";
                userHome = "/Users/${primaryUser}";
                pluginsDir = "${userHome}/.config/yazi/plugins";

                # List all yazi plugins that should be symlinked
                yaziPluginsList = [
                  pkgs.yaziPlugins.sudo
                  pkgs.yaziPlugins.starship
                  pkgs.yaziPlugins.rsync
                  pkgs.yaziPlugins.ouch
                  pkgs.yaziPlugins.smart-filter
                  pkgs.yaziPlugins.smart-enter
                  pkgs.yaziPlugins.mount
                  pkgs.yaziPlugins.mediainfo
                  pkgs.yaziPlugins.chmod
                  pkgs.yaziPlugins.git
                  pkgs.yaziPlugins.lazygit
                  pkgs.yaziPlugins.duckdb
                ];
              in
              ''
                echo "Setting up Yazi plugins..." >&2

                # Create plugins directory if it doesn't exist
                mkdir -p "${pluginsDir}"

                # Remove old nix-managed plugin symlinks (but preserve ya pkg managed ones)
                # We identify nix symlinks by checking if they point to /nix/store
                for plugin in "${pluginsDir}"/*.yazi; do
                  if [ -L "$plugin" ] && readlink "$plugin" | grep -q "^/nix/store"; then
                    echo "Removing old Nix plugin symlink: $plugin" >&2
                    rm "$plugin"
                  fi
                done

                # Create symlinks for each plugin
                ${pkgs.lib.concatMapStringsSep "\n" (plugin: ''
                  # Extract plugin name: hash-name.yazi-version -> name.yazi
                  full_name=$(basename "${plugin}")
                  plugin_name=$(echo "$full_name" | sed 's/^[^-]*-\(.*\)\.yazi-.*/\1.yazi/')
                  echo "Linking $plugin_name..." >&2
                  ln -sf "${plugin}" "${pluginsDir}/$plugin_name"
                  chown -h ${primaryUser}:staff "${pluginsDir}/$plugin_name"
                '') yaziPluginsList}

                echo "Yazi plugins setup complete!" >&2
              '';

            nushellPlugins.text =
              let
                primaryUser = config.system.primaryUser or "nickminor";
                userHome = "/Users/${primaryUser}";
                pluginsDir = "${userHome}/.local/share/nushell-plugins";

                # List of nushell plugins to symlink
                nushellPluginsList = [
                  pkgs.nushellPlugins.polars
                  pkgs.nushellPlugins.query
                  pkgs.nushellPlugins.highlight
                  pkgs.nushellPlugins.gstat
                  pkgs.nushellPlugins.formats
                ];
              in
              ''
                echo "Setting up Nushell plugins..." >&2

                # Create plugins directory
                mkdir -p "${pluginsDir}"

                # Remove old nix-managed plugin symlinks
                for plugin in "${pluginsDir}"/nu_plugin_*; do
                  if [ -L "$plugin" ] && readlink "$plugin" | grep -q "^/nix/store"; then
                    echo "Removing old Nix plugin symlink: $plugin" >&2
                    rm "$plugin"
                  fi
                done

                # Create symlinks for each plugin binary
                ${pkgs.lib.concatMapStringsSep "\n" (plugin: ''
                  # Plugin binaries are in ${plugin}/bin/nu_plugin_<name>
                  for binary in "${plugin}"/bin/nu_plugin_*; do
                    if [ -f "$binary" ]; then
                      plugin_name=$(basename "$binary")
                      echo "Linking $plugin_name..." >&2
                      ln -sf "$binary" "${pluginsDir}/$plugin_name"
                      chown -h ${primaryUser}:staff "${pluginsDir}/$plugin_name"
                    fi
                  done
                '') nushellPluginsList}

                echo "Nushell plugins setup complete!" >&2
              '';

          };

        };
    in
    {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#starter
      darwinConfigurations."starter" = nix-darwin.lib.darwinSystem {
        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = false;
              user = "nickminor";
              autoMigrate = true;
              taps = {
                "steipete/tap" = homebrew-steipete;
              };
            };
          }
          (
            { pkgs, ... }:
            {
              # Make pkg-config see Nix .pc files: use *dev* outputs
              environment.variables.PKG_CONFIG_PATH = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
                pkgs.xz
                pkgs.zstd
                pkgs.libiconv
              ];

              # bzip2 typically has no .pc — feed the Nix cc wrapper the lib paths
              environment.variables.NIX_LDFLAGS = pkgs.lib.concatStringsSep " " [
                "-L${pkgs.bzip2}/lib"
                "-L${pkgs.xz}/lib"
                "-L${pkgs.zstd}/lib"
                "-L${pkgs.libiconv}/lib"
              ];

              # (Optional) headers for C-using crates
              environment.variables.NIX_CFLAGS_COMPILE = pkgs.lib.concatStringsSep " " [
                "-I${pkgs.xz.dev}/include"
                "-I${pkgs.zstd.dev}/include"
                "-I${pkgs.libiconv.dev}/include"
              ];
            }

          )
          configuration
        ];
      };

      # Expose the package set, including overlays, for convenience.
      darwinPackages = self.darwinConfigurations."starter".pkgs;

    };
}
