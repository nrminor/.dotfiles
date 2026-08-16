# Darwin activation scripts
#
# Scripts that run during 'darwin-rebuild switch' to handle
# tasks that can't be done declaratively.
{
  config,
  pkgs,
  username,
  ...
}:

let
  userHome = "/Users/${username}";

  # Import common plugin lists
  plugins = import ../common/plugins.nix { inherit pkgs; };
in
{
  system.activationScripts = {
    # Application aliases for Spotlight indexing
    applications.text =
      let
        env = pkgs.buildEnv {
          name = "system-applications";
          paths = config.environment.systemPackages;
          pathsToLink = [ "/Applications" ];
        };
      in
      pkgs.lib.mkForce ''
        # Set up applications
        echo "setting up /Applications..." >&2
        rm -rf /Applications/Nix\ Apps
        mkdir -p /Applications/Nix\ Apps
        find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
        while read -r src; do
          app_name=$(basename "$src")
          echo "copying $src" >&2
          ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
        done

        # Require an Apple-native compiler and SDK for builds outside Nix derivations.
        if ! /usr/bin/xcrun --sdk macosx --find clang >/dev/null 2>&1; then
          echo "Xcode Command Line Tools are required for native development." >&2
          echo "Install them with: xcode-select --install" >&2
          exit 1
        fi

        sdkroot=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
        if [ ! -f "$sdkroot/usr/lib/libiconv.tbd" ]; then
          echo "The selected macOS SDK does not provide libiconv: $sdkroot" >&2
          exit 1
        fi

        # A Command Line Tools installation has no Xcode license to accept.
        developer_dir=$(/usr/bin/xcode-select --print-path)
        if [ -x "$developer_dir/usr/bin/xcodebuild" ]; then
          /usr/bin/xcodebuild -license accept
        fi

        # Create standard directories
        echo "Setting up directories..." >&2
        if [ ! -d "${userHome}/Documents/bioinformatics" ]; then
          echo "Creating bioinformatics directory..." >&2
          mkdir -p "${userHome}/Documents/bioinformatics"
          chown -R ${username}:staff ${userHome}/Documents/bioinformatics
        fi

        if [ ! -d "${userHome}/Documents/hacking" ]; then
          echo "Creating hacking directory..." >&2
          mkdir -p "${userHome}/Documents/hacking"
          chown -R ${username}:staff ${userHome}/Documents/hacking
        fi

        if [ ! -d "${userHome}/Documents/screenshots" ]; then
          echo "Creating screenshots directory..." >&2
          mkdir -p "${userHome}/Documents/screenshots"
          chown -R ${username}:staff ${userHome}/Documents/screenshots
        fi

      '';

    # Plugin symlinks (runs after system setup)
    postActivation.text =
      let
        yaziPluginsDir = "${userHome}/.config/yazi/plugins";
      in
      ''
        # ===== Yazi Plugins =====
        echo "Setting up Yazi plugins..." >&2

        mkdir -p "${yaziPluginsDir}"

        # Remove old nix-managed plugin symlinks (preserve ya pkg managed ones)
        for plugin in "${yaziPluginsDir}"/*.yazi; do
          if [ -L "$plugin" ] && readlink "$plugin" | grep -q "^/nix/store"; then
            echo "Removing old Nix plugin symlink: $plugin" >&2
            rm "$plugin"
          fi
        done

        # Create symlinks for each plugin
        ${pkgs.lib.concatMapStringsSep "\n" (plugin: ''
          full_name=$(basename "${plugin}")
          # Extract plugin name: hash-name.yazi-version -> name.yazi
          temp="''${full_name#*-}"
          plugin_name="''${temp%%.yazi-*}.yazi"
          echo "Linking $plugin_name..." >&2
          ln -sf "${plugin}" "${yaziPluginsDir}/$plugin_name"
          chown -h ${username}:staff "${yaziPluginsDir}/$plugin_name"
        '') plugins.yazi}

        echo "Yazi plugins setup complete!" >&2
      '';
  };
}
