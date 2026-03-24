let
  inherit (import ./utilities.nix) nnoremap vnoremap;
in
{
  keymaps = [
    ##########################################################################
    # General
    ##########################################################################

    # Disabled Keys
    {
      mode = "n";
      key = "<space>";
      action = "<nop>";
      options = {
        silent = true;
        noremap = true;
      };
    }

    # Movement
    (nnoremap "L" "$" "Jump End of [L]ine")
    (nnoremap "H" "^" "Jump Start of [L]ine")
    (nnoremap "j" "jzz" "Vertically Center Cursor Down")
    (nnoremap "k" "kzz" "Vertically Center Cursor Up")
    (nnoremap "gg" "ggzz" "Vertically Center Cursor Start Of File")
    (nnoremap "G" "Gzz" "Vertically Center Cursor End Of File")

    # Redo
    (nnoremap "U" "<C-r>" "Redo")

    # Save Buffer
    (nnoremap "<C-s>" "<cmd>w<cr>" "Save Current Buffer")

    # Turn off highlighted results
    (nnoremap "<leader>no" "<cmd>noh<cr>" "[N]o Highlight")

    # Save and Quit
    {
      mode = "n";
      key = "<leader>w";
      action = "<cmd>w<cr>";
      options = {
        desc = "[W]rite Buffer";
        silent = false;
      };
    }
    {
      mode = "n";
      key = "<leader>q";
      action = "<cmd>q<cr>";
      options = {
        desc = "[Q]uit Buffer";
        silent = false;
      };
    }
    {
      mode = "n";
      key = "<leader>z";
      action = "<cmd>wq<cr>";
      options = {
        desc = "[W]rite [Q]uit Buffer";
        silent = false;
      };
    }

    (vnoremap "<" "<gv" "Visual Mode Outdent")
    (vnoremap ">" ">gv" "Visual Mode Indent")

    ##########################################################################
    # LSP Navigation (Helix-style)
    ##########################################################################

    (nnoremap "gr" "<cmd>lua Snacks.picker.lsp_references()<cr>" "[G]oto [R]eferences")

    ##########################################################################
    # Buffer Navigation (Helix-style)
    ##########################################################################

    (nnoremap "gn" "<cmd>bnext<cr>" "[G]o [N]ext Buffer")
    (nnoremap "gb" "<cmd>bprev<cr>" "[G]o [B]ack Buffer (Previous)")
    (nnoremap "gp" "<cmd>bprev<cr>" "[G]o [P]revious Buffer")
    (nnoremap "<leader>b" "<cmd>lua Snacks.picker.buffers()<cr>" "Buffer Picker")

    ##########################################################################
    # Window Management
    ##########################################################################

    (nnoremap "<leader>w-" "<C-w>s" "Split [W]indow Vertical")
    (nnoremap "<leader>w|" "<C-w>v" "Split [W]indow Horizontal")
    (nnoremap "<leader>wd" "<C-w>c" "Delete [W]indow")
    (nnoremap "<leader>wr" "<C-w>c" "Rotate [W]indow")
    (nnoremap "<leader>=" "<C-w>=" "Resize Windows Equal")
    (nnoremap "<C-j>" {
      __raw =
        # lua
        ''
          function()
            if vim.fn.exists(":KittyNavigateDown") ~= 0 and os.getenv("TERM") == "xterm-kitty" then
              vim.cmd.KittyNavigateDown()
            elseif vim.fn.exists(":NvimTmuxNavigateDown") ~= 0 then
              vim.cmd.NvimTmuxNavigateDown()
            else
              vim.cmd.wincmd("j")
            end
          end
        '';
    } "Navigate Window Down")
    (nnoremap "<C-k>" {
      __raw =
        # lua
        ''
          function()
            if vim.fn.exists(":KittyNavigateUp") ~= 0 and os.getenv("TERM") == "xterm-kitty" then
              vim.cmd.KittyNavigateUp()
            elseif vim.fn.exists(":NvimTmuxNavigateUp") ~= 0 then
              vim.cmd.NvimTmuxNavigateUp()
            else
              vim.cmd.wincmd("k")
            end
          end
        '';
    } "Navigate Window Up")
    (nnoremap "<C-h>" {
      __raw =
        # lua
        ''
          function()
            if vim.fn.exists(":KittyNavigateLeft") ~= 0 and os.getenv("TERM") == "xterm-kitty" then
              vim.cmd.KittyNavigateLeft()
            elseif vim.fn.exists(":NvimTmuxNavigateLeft") ~= 0 then
              vim.cmd.NvimTmuxNavigateLeft()
            else
              vim.cmd.wincmd("h")
            end
          end
        '';
    } "Navigate Window Left")
    (nnoremap "<C-l>" {
      __raw =
        # lua
        ''
          function()
            if vim.fn.exists(":KittyNavigateRight") ~= 0 and os.getenv("TERM") == "xterm-kitty" then
              vim.cmd.KittyNavigateRight()
            elseif vim.fn.exists(":NvimTmuxNavigateRight") ~= 0 then
              vim.cmd.NvimTmuxNavigateRight()
            else
              vim.cmd.wincmd("l")
            end
          end
        '';
    } "Navigate Window Right")

    ##########################################################################
    # Tab Management
    ##########################################################################
    (nnoremap "<leader><tab><tab>" "<cmd>tabnew<cr>" "Open new tab")
    (nnoremap "<leader><tab>d" "<cmd>tabclose<cr>" "Close current tab")
    (nnoremap "<leader>tl" {
      __raw =
        # lua
        ''
          function()
            local current = vim.fn.tabpagenr()
            local total = vim.fn.tabpagenr("$")
            if current == total then
              vim.cmd("tabfirst")
            else
              vim.cmd("tabnext")
            end
          end
        '';
    } "Move to next tab (wraps around)")
    (nnoremap "<leader>th" {
      __raw =
        # lua
        ''
          function()
            local current = vim.fn.tabpagenr()
            if current == 1 then
              vim.cmd("tablast")
            else
              vim.cmd("tabprevious")
            end
          end
        '';
    } "Move to previous tab (wraps around)")

    ##########################################################################
    # Terminal Management
    ##########################################################################
    {
      mode = "t";
      key = "<Esc>";
      action = "<C-\\><C-n>";
      options = {
        desc = "Enter normal mode";
      };
    }
    {
      mode = "t";
      key = "jj";
      action = "<C-\\><C-n>";
      options = {
        desc = "Enter normal mode";
      };
    }
    {
      mode = "t";
      key = "<C-h>";
      action = "<cmd>wincmd h<cr>";
      options = {
        desc = "Move to left window";
      };
    }
    {
      mode = "t";
      key = "<C-l>";
      action = "<cmd>wincmd l<cr>";
      options = {
        desc = "Move to right window";
      };
    }
    {
      mode = "t";
      key = "<C-k>";
      action = "<cmd>wincmd k<cr>";
      options = {
        desc = "Move to top window";
      };
    }
    {
      mode = "t";
      key = "<C-k>";
      action = "<cmd>wincmd j<cr>";
      options = {
        desc = "Move to bottom window";
      };
    }
    {
      mode = "t";
      key = "<Space>";
      action = "<Space>";
      options = {
        desc = "Remove input delay on space in terminal";
      };
    }

    ##########################################################################
    # Plugin Keymaps
    ##########################################################################
    # Conform
    (nnoremap "<leader>f" {
      __raw =
        # lua
        ''
          function()
            require("conform").format({
              async = true,
              timeout_ms = 500,
              lsp_format = "fallback",
            })
          end
        '';
    } "[F]ormat Current Buffer")
  ];
}
