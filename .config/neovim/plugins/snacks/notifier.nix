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
              local value = (args.data and args.data.params and args.data.params.value) or {}
              local kind = value.kind or ""
              local client = args.data and args.data.client_id and vim.lsp.get_client_by_id(args.data.client_id)

              local parts = {}
              if client and client.name then
                table.insert(parts, client.name)
              end
              if value.title and value.title ~= "" then
                table.insert(parts, value.title)
              end
              if value.message and value.message ~= "" then
                table.insert(parts, value.message)
              end

              local message = #parts > 0 and table.concat(parts, ": ") or "LSP progress"

              vim.notify(message, "info", {
                id = "lsp_progress",
                title = "LSP Progress",
                opts = function(notif)
                  notif.icon = kind == "end" and " "
                    or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
                end,
              })
            end
          '';
      };
    }
  ];
}
