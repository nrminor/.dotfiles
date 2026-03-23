{
  plugins.lsp.servers = {
    jsonls = {
      enable = true;
      settings = {
        init_options = {
          provide_formatter = false;
        };
      };
    };
  };
}
