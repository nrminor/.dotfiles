let
  inherit (import ../utilities.nix) inoremap nnoremap;
in
{
  plugins = {
    lsp = {
      enable = true;

      keymaps = {
        # Mappings for `vim.diagnostic.<action>` functions to be added when an
        # LSP it attached
        diagnostic = {
          "]d" = {
            action = "goto_next";
            desc = "Goto Next Diagnostic";
          };
          "[d" = {
            action = "goto_prev";
            desc = "Goto Previous Diagnostic";
          };
        };

        # Mappings for `vim.lsp.buf.<action>` functions to be added when an
        # LSP it attached
        lspBuf = {
          "K" = {
            action = "hover";
            desc = "Hover Documentation";
          };
          "<leader>ca" = {
            action = "code_action";
            desc = "LSP: [C]ode [A]ction";
          };
          "<leader>rn" = {
            action = "rename";
            desc = "LSP: [R]ename";
          };
          "<leader>k" = {
            action = "signature_help";
            desc = "LSP: [S]ignature [H]elp";
          };
          "gd" = {
            action = "definition";
            desc = "LSP: [G]oto [D]efinition";
          };
          "gD" = {
            action = "declaration";
            desc = "LSP: [G]oto [D]eclaration";
          };
          "gt" = {
            action = "type_definition";
            desc = "LSP: [G]oto [T]ype Definition";
          };
        };

        extra = [
          (inoremap "<C-k>" "<cmd>lua vim.lsp.buf.signature_help()<cr>" "LSP: [S]ignature [H]elp")
          (nnoremap "<leader>d" {
            __raw =
              # lua
              ''
                function()
                  vim.diagnostic.open_float({ border = "rounded" })
                end
              '';
          } "LSP: Show Line [D]iagnostics")
          (nnoremap "<leader>ll" {
            __raw =
              # lua
              ''
                function()
                  if vim.diagnostic.config().virtual_text == false then
                    vim.diagnostic.config({
                      virtual_text = {
                        source = "always",
                        prefix = "●",
                      },
                    })
                  else
                    vim.diagnostic.config({
                      virtual_text = false,
                    })
                  end
                end
              '';
          } "LSP: Toggle Inline Diagnostics")
          (nnoremap "<leader>lL" {
            __raw =
              # lua
              ''
                function()
                  if vim.g.diagnostics_visible then
                    vim.g.diagnostics_visible = false
                    vim.diagnostic.disable()
                  else
                    vim.g.diagnostics_visible = true
                    vim.diagnostic.enable()
                  end
                end
              '';
          } "LSP: Toggle Diagnostics")
        ];
      };
    };
  };
}
