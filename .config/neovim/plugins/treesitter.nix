{ pkgs, ... }:
{
  config = {
    extraPackages = [ pkgs.tree-sitter ];

    plugins = {
      treesitter = {
        enable = true;
        nixvimInjections = true;
        settings = {
          autopairs.enable = true;
          indent.enable = true;
          highlight.enable = true;
          incremental_selection.enable = true;
        };
      };

      ts-autotag = {
        enable = true;
      };

      ts-context-commentstring = {
        enable = true;
        disableAutoInitialization = false;
      };

      # Enable the plugin but configure via raw Lua (nixvim's declarative
      # config calls the deprecated nvim-treesitter.configs API)
      treesitter-textobjects.enable = true;
    };

    extraConfigLua = ''
      -- Treesitter textobjects: select
      local ts_select = require("nvim-treesitter-textobjects.select")
      local ts_move = require("nvim-treesitter-textobjects.move")

      -- Selection keymaps
      local select_keymaps = {
        ["aa"] = "@parameter.outer",
        ["ia"] = "@parameter.inner",
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
        ["ii"] = "@conditional.inner",
        ["ai"] = "@conditional.outer",
        ["il"] = "@loop.inner",
        ["al"] = "@loop.outer",
        ["at"] = "@comment.outer",
      }

      for key, query in pairs(select_keymaps) do
        vim.keymap.set({ "x", "o" }, key, function()
          ts_select.select_textobject(query, "textobjects")
        end, { desc = "Select " .. query })
      end

      -- Movement keymaps
      local move_maps = {
        ["]m"] = { query = "@function.outer", method = "goto_next_start" },
        ["]]"] = { query = "@class.outer", method = "goto_next_start" },
        ["]M"] = { query = "@function.outer", method = "goto_next_end" },
        ["]["] = { query = "@class.outer", method = "goto_next_end" },
        ["[m"] = { query = "@function.outer", method = "goto_previous_start" },
        ["[["] = { query = "@class.outer", method = "goto_previous_start" },
        ["[M"] = { query = "@function.outer", method = "goto_previous_end" },
        ["[]"] = { query = "@class.outer", method = "goto_previous_end" },
      }

      for key, opts in pairs(move_maps) do
        vim.keymap.set({ "n", "x", "o" }, key, function()
          ts_move[opts.method](opts.query, "textobjects")
        end, { desc = opts.method .. " " .. opts.query })
      end
    '';
  };
}
