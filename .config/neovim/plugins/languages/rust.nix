{
  lib,
  pkgs,
  rustowlPlugin ? null,
  optionalNeovimFeatures ? { },
  ...
}:
let
  rustowlEnabled = lib.attrByPath [ "rustowl" ] false optionalNeovimFeatures;
in
{
  plugins.lsp.servers = {
    rust_analyzer = {
      enable = true;
      installCargo = false;
      installRustc = false;
      settings = {
        check = {
          command = "clippy";
          extraArgs = [
            "--all-features"
          ];
        };
        checkOnSave = {
          enable = true;
          command = "clippy";
          extraArgs = [
            "--all-features"
          ];
        };
        inlayHints = {
          enable = false;
          lifetimeElisionHints = {
            enable = "skip_trivial";
            useParameterNames = true;
          };
          parameterHints.enable = true;
          chainingHints.enable = false;
          closureCaptureHints.enable = false;
          closureStyle = "impl_fn";
          closureReturnTypeHints.enable = "always";
          expressionAdjustmentHints.enable = "never";
          implicitDrops.enable = false;
        };
      };
    };

  };

  extraPlugins = [ pkgs.vimPlugins.crates-nvim ] ++ lib.optionals rustowlEnabled [ rustowlPlugin ];

  extraConfigLua = builtins.concatStringsSep "\n" (
    [ (builtins.readFile ./crates.lua) ]
    ++ lib.optionals rustowlEnabled [ (builtins.readFile ./rustowl.lua) ]
  );
}
