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
}
