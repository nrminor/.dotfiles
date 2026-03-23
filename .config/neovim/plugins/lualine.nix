{
  plugins.lualine = {
    enable = true;
    settings = {
      options = {
        theme = "auto";
        globalstatus = true;
        component_separators = {
          left = "";
          right = "";
        };
        section_separators = {
          left = "█";
          right = "█";
        };
      };
      sections = {
        # Left: mode, branch, filename (with modified/readonly indicators)
        lualine_a = [ "mode" ];
        lualine_b = [
          {
            __unkeyed-1 = "branch";
            icon = "";
          }
        ];
        lualine_c = [
          {
            __unkeyed-1 = "filename";
            path = 1;
            symbols = {
              modified = "[+]";
              readonly = "[RO]";
            };
          }
        ];

        # Right: diagnostics, selections, position, progress, total lines, encoding, filetype
        lualine_x = [
          "diagnostics"
          "selectioncount"
        ];
        lualine_y = [
          "location"
          "progress"
          {
            __unkeyed-1 = {
              __raw = ''
                function()
                  return vim.api.nvim_buf_line_count(0) .. "L"
                end
              '';
            };
          }
        ];
        lualine_z = [ "filetype" ];
      };
    };
  };
}
