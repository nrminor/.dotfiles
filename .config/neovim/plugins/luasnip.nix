{
  plugins.luasnip = {
    enable = true;
    fromLua = [
      { }
      { paths = ./snippets; }
    ];
    settings = {
      # Update dynamic snippets while typing
      updateevents = "TextChanged,TextChangedI";
    };
  };

  autoCmd = [
    {
      desc = "Leave snippet on mode change";
      event = [ "ModeChanged" ];
      callback = {
        __raw =
          # lua
          ''
            function()
              if ((vim.v.event.old_mode == 's' and vim.v.event.new_mode == 'n') or vim.v.event.old_mode == 'i')
                   and require('luasnip').session.current_nodes[vim.api.nvim_get_current_buf()]
                   and not require('luasnip').session.jump_active
               then
                 require('luasnip').unlink_current()
               end
             end
          '';
      };
    }
  ];
}
