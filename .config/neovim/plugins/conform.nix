{
  userCommands = {
    "FormatEnable" = {
      desc = "Enable format on save";
      command = {
        __raw =
          # lua
          ''
            function()
              vim.b.disable_autoformat = false
              vim.g.disable_autoformat = false
            end
          '';
      };
    };
    "FormatDisable" = {
      desc = "Disable format on save";
      bang = true;
      command = {
        __raw =
          # lua
          ''
            function(args)
              if args.bang then
                -- FormatDisable! will disable formatting just for this buffer
                vim.b.disable_autoformat = true
              else
                vim.g.disable_autoformat = true
              end
            end
          '';
      };
    };
  };

  plugins.conform-nvim = {
    enable = true;
    settings = {
      log_level = "debug";
      notify_on_error = false;
      notify_no_formatters = false;
      format_after_save = {
        __raw =
          # lua
          ''
            function(buffer_number)
              -- Returning nil skips formatting for this save.
              -- Returning an options table tells Conform how to format.
              if vim.g.disable_autoformat or vim.b[buffer_number].disable_autoformat then
                return
              end

              local filetype = vim.bo[buffer_number].filetype
              local is_ocaml_filetype = filetype == "ocaml"
                or filetype == "ocamlinterface"
                or filetype == "ocamllex"
                or filetype == "menhir"

              return {
                -- Match Helix behavior for OCaml: always use ocamlformat.
                lsp_format = is_ocaml_filetype and "never" or "prefer",
                stop_after_first = true,
                timeout_ms = is_ocaml_filetype and 2000 or 500,
                async = true,
              }
            end
          '';
      };
      formatters_by_ft =
        let
          js_common = {
            __unkeyed-1 = "oxfmt";
            __unkeyed-2 = "biome";
            stop_after_first = true;
          };
        in
        {
          javascript = js_common;
          javascriptreact = js_common;
          typescript = js_common;
          typescriptreact = js_common;
          ocaml = [ "ocamlformat_impl" ];
          ocamlinterface = [ "ocamlformat_intf" ];
          ocamllex = [ "ocamlformat_impl" ];
          menhir = [ "ocamlformat_impl" ];
          nu = [ "topiary" ];
        };
      formatters = {
        topiary = {
          command = "topiary";
          args = [
            "format"
            "--language"
            "nu"
          ];
          stdin = true;
        };
        ocamlformat_impl = {
          command = "ocamlformat";
          args = [
            "-"
            "--impl"
            "--enable-outside-detected-project"
          ];
          stdin = true;
        };
        ocamlformat_intf = {
          command = "ocamlformat";
          args = [
            "-"
            "--intf"
            "--enable-outside-detected-project"
          ];
          stdin = true;
        };
      };
    };
  };
}
