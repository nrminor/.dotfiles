# Darwin activation scripts
#
# Scripts that run during 'darwin-rebuild switch' to handle
# tasks that can't be done declaratively.
{ lib, ... }:

{
  system.activationScripts = {
    # Homebrew owns macOS applications; suppress nix-darwin's app copier.
    applications.text = lib.mkForce "";

    xcodeSetup.text = ''
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
    '';
  };
}
