{ lib, pkgs, ... }:
let
  vclibPlugin = pkgs.vimUtils.buildVimPlugin {
    pname = "vclib.nvim";
    version = "0-unstable-2026-07-06";
    src = pkgs.fetchFromGitHub {
      owner = "algmyr";
      repo = "vclib.nvim";
      rev = "24c36d22ddd28c8d001d85e1fb69fcd2e38a8858";
      hash = "sha256-yab6Sk39rgOeK08KxAFEgCQHAyHbJDb6k0UFsLGAIgM=";
    };
    doCheck = false;
    meta = with lib; {
      homepage = "https://github.com/algmyr/vclib.nvim";
      license = licenses.mit;
    };
  };

  vcsignsPlugin = pkgs.vimUtils.buildVimPlugin {
    pname = "vcsigns.nvim";
    version = "0-unstable-2026-07-06";
    src = pkgs.fetchFromGitHub {
      owner = "algmyr";
      repo = "vcsigns.nvim";
      rev = "40fb52b35d5402740b83642ac53dcc3e29552ac2";
      hash = "sha256-V1xoXxUvwmWxznxOc0cTH8wVT7d4NWZiVqsUc74eE84=";
    };
    doCheck = false;
    meta = with lib; {
      homepage = "https://github.com/algmyr/vcsigns.nvim";
      license = licenses.mit;
    };
  };
in
{
  extraPlugins = [
    pkgs.vimPlugins.async-nvim
    vclibPlugin
    vcsignsPlugin
  ];

  extraConfigLua = ''
    local vcsigns = require("vcsigns")
    local vcsigns_actions = require("vcsigns.actions")

    vcsigns.setup({ auto_enable = false })

    local function jj_root(bufnr)
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == "" then
        return nil
      end

      local path = vim.uv.fs_realpath(name) or vim.fs.dirname(name)
      return vim.fs.root(path, ".jj")
    end

    local function attach_to_jj_buffer(bufnr)
      if not jj_root(bufnr) then
        return
      end

      vcsigns_actions.start_if_needed(bufnr)

      local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, {
          buffer = bufnr,
          desc = desc,
          silent = true,
        })
      end

      map("]c", function()
        vcsigns_actions.hunk_next(bufnr, vim.v.count1)
      end, "Next hunk")

      map("[c", function()
        vcsigns_actions.hunk_prev(bufnr, vim.v.count1)
      end, "Previous hunk")
    end

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
      group = vim.api.nvim_create_augroup("jj_vcsigns", { clear = true }),
      callback = function(args)
        attach_to_jj_buffer(args.buf)
      end,
      desc = "Attach VCSigns to Jujutsu buffers",
    })
  '';
}
