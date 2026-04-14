{ lib, pkgs, ... }:
let
  vimFrign = pkgs.vimUtils.buildVimPlugin {
    pname = "vim-frign";
    version = "3abc464";
    src = pkgs.fetchFromGitHub {
      owner = "KimNorgaard";
      repo = "vim-frign";
      rev = "3abc464a7f21151bfdd596089ddcab80be658eb3";
      hash = "sha256-/fgd+cLAmn7ntfLScwHv1fh6K0JSddmnoFV/eMa4sSg=";
    };
    meta = with lib; {
      homepage = "https://github.com/KimNorgaard/vim-frign";
      license = licenses.mit;
    };
  };

  quietlightVim = pkgs.vimUtils.buildVimPlugin {
    pname = "quietlight-vim";
    version = "61b00ed";
    src = pkgs.fetchFromGitHub {
      owner = "aonemd";
      repo = "quietlight.vim";
      rev = "61b00ed7c9678c2b23a5ceec8b895001f76af56b";
      hash = "sha256-GlIF4Y9rjsg/m/ZghgE7v8Y05UXjULxuDuUXjfoX6SA=";
    };
    meta = with lib; {
      homepage = "https://github.com/aonemd/quietlight.vim";
      license = licenses.mit;
    };
  };

in
{
  colorschemes = {
    catppuccin = {
      enable = true;
      settings = {
        flavour = "latte";
        transparent_background = true;
        no_bold = true;
        no_italic = true;
        integrations = {
          blink_cmp = true;
          gitsigns = true;
          indent_blankline = {
            enabled = false;
            scope_color = "sapphire";
            colored_indent_levels = false;
          };
          native_lsp = {
            enabled = true;
          };
          symbols_outline = true;
          telescope = true;
          treesitter = true;
          treesitter_context = true;
        };
      };
    };
  };

  extraFiles = {
    "bluescreen.lua" = {
      source = ./colors/bluescreen.lua;
      target = "colors/bluescreen.lua";
    };
    "bluescreen_soft.lua" = {
      source = ./colors/bluescreen_soft.lua;
      target = "colors/bluescreen_soft.lua";
    };
  };

  extraPlugins = [
    pkgs.vimPlugins.deepwhite-nvim
    pkgs.vimPlugins.everforest
    pkgs.vimPlugins.miasma-nvim
    vimFrign
    quietlightVim
  ];
}
