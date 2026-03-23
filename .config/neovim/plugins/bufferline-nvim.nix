{
  plugins.bufferline = {
    enable = true;
    settings = {
      options = {
        mode = "buffers";
        diagnostics = "nvim_lsp";
        show_buffer_close_icons = false;
        show_close_icon = false;
        always_show_bufferline = true;
        separator_style = "thin";
        offsets = [
          {
            filetype = "oil";
            text = "File Explorer";
            highlight = "Directory";
            separator = true;
          }
        ];
      };
    };
  };

  # Always show the tabline
  opts.showtabline = 2;
}
