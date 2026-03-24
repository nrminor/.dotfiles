{ pkgs, lib, ... }:
let
  nextflow-lsp = pkgs.stdenv.mkDerivation rec {
    pname = "nextflow-language-server";
    version = "25.10.3";

    src = pkgs.fetchurl {
      url = "https://github.com/nextflow-io/language-server/releases/download/v${version}/language-server-all.jar";
      sha256 = "sha256-aBaD4Naxand76OaIZ7WnjDkgei8T0rjwohRFRH2Z2FI=";
    };

    dontUnpack = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      mkdir -p $out/lib $out/bin
      cp $src $out/lib/language-server-all.jar
      makeWrapper ${pkgs.jdk}/bin/java $out/bin/nextflow-language-server \
        --add-flags "-jar $out/lib/language-server-all.jar"
    '';

    meta = with lib; {
      description = "Language server for Nextflow";
      homepage = "https://github.com/nextflow-io/language-server";
      license = licenses.asl20;
    };
  };
in
{
  extraPackages = [ nextflow-lsp ];

  # Reuse the Groovy parser for Nextflow buffers so Tree-sitter highlighting
  # works for .nf files.
  plugins.treesitter.languageRegister = {
    groovy = "nextflow";
  };

  # Register the filetype and LSP manually since nextflow isn't in nvim-lspconfig
  extraConfigLua = ''
    vim.filetype.add({
      extension = {
        nf = "nextflow",
      },
      pattern = {
        ["nextflow%.config"] = "nextflow",
        [".*%.nf%.test"] = "nextflow",
      },
    })

    vim.lsp.config["nextflow-language-server"] = {
      cmd = { "${nextflow-lsp}/bin/nextflow-language-server" },
      filetypes = { "nextflow", "groovy" },
      root_markers = { "nextflow.config", "main.nf", ".git" },
      settings = {
        nextflow = {
          files = {
            exclude = { ".pixi", ".git", ".nf-test", "work" },
          },
          formatting = {
            harshilAlignment = true,
          },
        },
      },
    }
    vim.lsp.enable("nextflow-language-server")
  '';
}
