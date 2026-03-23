{
  plugins.snacks.settings.notifier = {
    enabled = true;
    timeout = 3000;
  };

  autoCmd = [
    {
      desc = "Show language server progress";
      event = [ "LspProgress" ];
      callback = {
        __raw =
          # lua
          ''
            function(args)
              local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
              vim.notify(vim.lsp.status(), "info", {
                id = "lsp_progress",
                title = "LSP Progress",
                opts = function(notif)
                  notif.icon = args.data.params.value.kind == "end" and " "
                    or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
                end,
              })
            end
          '';
      };
    }
  ];
}
