{
  plugins.which-key = {
    enable = true;
    settings = {
      delay = 300;
      icons = {
        breadcrumb = "»";
        separator = "→";
      };
      win = {
        border = "rounded";
        padding = [
          1
          2
        ];
        col.__raw = "vim.o.columns";
        row.__raw = "math.huge";
        width.__raw = "math.floor(vim.o.columns * 0.4)";
        height = {
          min = 4;
          max = 20;
        };
      };
      layout = {
        width = {
          min = 20;
        };
        spacing = 3;
      };
      spec = [
        {
          __unkeyed-1 = "<leader>f";
          group = "Find";
        }
        {
          __unkeyed-1 = "<leader>g";
          group = "Git";
        }
        {
          __unkeyed-1 = "<leader>h";
          group = "Git hunks";
        }
        {
          __unkeyed-1 = "<leader>l";
          group = "LSP";
        }
        {
          __unkeyed-1 = "<leader>t";
          group = "Toggle";
        }
        {
          __unkeyed-1 = "<leader>w";
          group = "Window";
        }
        {
          __unkeyed-1 = "<leader><tab>";
          group = "Tabs";
        }
        {
          __unkeyed-1 = "<leader>d";
          group = "Diagnostics/Dadbod";
        }
      ];
    };
  };
}
