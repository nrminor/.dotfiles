{
  plugins.lsp.servers.lua_ls = {
    enable = true;
    settings = {
      diagnostics = {
        globals = [ "vim" ];
      };
      workspace = {
        checkThirdParty = false;
      };
    };
  };
}
