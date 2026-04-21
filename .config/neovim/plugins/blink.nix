{ config, lib, ... }:
{
  plugins.blink-cmp = {
    enable = true;
    setupLspCapabilities = true;
    settings = {
      appearance = {
        nerd_font_variant = "mono";
      };
      completion = {
        list = {
          selection = {
            preselect = false;
          };
        };
        documentation = {
          auto_show = true;
          auto_show_delay_ms = 100;
        };
        trigger = {
          show_in_snippet = false;
        };
      };
      fuzzy = {
        implementation = "prefer_rust";
      };
      keymap = {
        preset = "default";
        "<CR>" = [
          "accept"
          "fallback"
        ];
        "<C-j>" = [
          "scroll_documentation_down"
          "fallback"
        ];
        "<C-k>" = [
          "scroll_documentation_up"
          "fallback"
        ];
        "<Tab>" = [
          "select_next"
          "snippet_forward"
          "fallback"
        ];
        "<S-Tab>" = [
          "select_prev"
          "snippet_backward"
          "fallback"
        ];
      };
      signature = {
        enabled = true;
      };
      snippets = {
        preset = "luasnip";
      };
      sources = {
        default = [
          "lsp"
          "buffer"
          "snippets"
          "path"
        ]
        ++ (lib.optionals config.plugins.codecompanion.enable [ "codecompanion" ]);
        providers = {
          lsp = {
            score_offset = 4;
          };
          snippets = {
            score_offset = 5;
            should_show_items = {
              __raw =
                # lua
                ''
                  function(ctx)
                    return not (
                      ctx.trigger.initial_kind == "manual" or 
                      ctx.trigger.initial_kind == "trigger_character" 
                    )
                  end
                '';
            };
          };
        };
      };
    };
  };
}
