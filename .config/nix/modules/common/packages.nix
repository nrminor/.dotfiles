# Common packages
#
# A list of packages that work across platforms. This is pure data -
# it returns a list, not a module configuration. The consuming module
# decides where to install them (environment.systemPackages, home.packages, etc.)
{ pkgs, inputs }:

let
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
in
[
  # ===== Build Tools & System Libraries =====
  pkgs.cmake
  pkgs.clang
  pkgs.libiconv
  pkgs.pkg-config
  pkgs.pkgconf
  pkgs.zlib
  pkgs.llvm
  pkgs.gettext

  # ===== Nix Tooling =====
  pkgs.nixd
  pkgs.nixfmt
  pkgs.nil

  # ===== Editors =====
  pkgs.neovim
  pkgs.helix
  # pkgs.ghostty

  # ===== Core CLI Tools =====
  pkgs.less
  pkgs.tailspin
  pkgs.tree
  pkgs.parallel
  pkgs.curl
  pkgs.wget
  pkgs.jq
  pkgs.ripgrep
  pkgs.ripgrep-all
  pkgs.fd
  pkgs.fzf
  pkgs.fzf-make
  pkgs.bat
  pkgs.eza
  pkgs.tokei
  pkgs.hyperfine
  pkgs.ouch
  pkgs.xz
  pkgs.zstd
  pkgs.bzip2
  pkgs.p7zip
  pkgs.xclip

  # ===== Shell & Prompt =====
  pkgs.zoxide
  pkgs.fastfetch
  pkgs.starship
  pkgs.atuin
  pkgs.carapace

  # ===== Nushell Ecosystem =====
  pkgs.nushell
  pkgs.nushellPlugins.polars
  # pkgs.nushellPlugins.units
  pkgs.nushellPlugins.query
  pkgs.nushellPlugins.highlight
  pkgs.nushellPlugins.gstat
  pkgs.nushellPlugins.formats
  pkgs.topiary
  pkgs.nufmt

  # ===== Disk Usage & Monitoring =====
  pkgs.dust
  pkgs.dua
  pkgs.btop
  pkgs.htop
  # pkgs.bottom

  # ===== Terminal Multiplexer =====
  pkgs.zellij

  # ===== File Management =====
  pkgs.yazi
  pkgs.yaziPlugins.sudo
  pkgs.yaziPlugins.starship
  pkgs.yaziPlugins.rsync
  pkgs.yaziPlugins.ouch
  pkgs.yaziPlugins.smart-filter
  pkgs.yaziPlugins.smart-enter
  pkgs.yaziPlugins.mount
  pkgs.yaziPlugins.mediainfo
  pkgs.yaziPlugins.chmod
  pkgs.yaziPlugins.git
  pkgs.yaziPlugins.lazygit
  pkgs.yaziPlugins.gitui
  pkgs.yaziPlugins.duckdb

  # ===== Git & Version Control =====
  pkgs.git
  pkgs.lazygit
  # pkgs.gitui
  pkgs.difftastic
  pkgs.pre-commit
  pkgs.wrkflw
  pkgs.jujutsu
  pkgs.lazyjj
  pkgs.jjui
  inputs.jj-starship.packages.${pkgs.system}.jj-starship
  pkgs.mergiraf
  pkgs.gh

  # ===== Development Tools =====
  pkgs.just
  # pkgs.mask
  pkgs.direnv
  # pkgs.mise
  pkgs.devbox
  pkgs.watchexec
  pkgs.dotter
  pkgs.lychee
  pkgs.gnuplot
  pkgs.wiki-tui
  pkgs.tlrc

  # ===== Bash/Zsh =====
  pkgs-stable.bash-language-server
  pkgs.shellcheck
  pkgs.shfmt
  pkgs.zsh-autosuggestions
  pkgs.zsh-syntax-highlighting

  # ===== Awk =====
  pkgs.gawk
  pkgs.awk-language-server

  # ===== Rust Ecosystem =====
  pkgs.rustup
  pkgs.mdbook
  pkgs.rust-script
  pkgs.evcxr
  pkgs.maturin
  pkgs.bacon
  pkgs.rusty-man
  pkgs.cargo-msrv
  pkgs.cargo-sort
  pkgs.cargo-audit
  pkgs.cargo-info
  pkgs.cargo-fuzz
  pkgs.cargo-insta
  pkgs.cargo-dist
  pkgs.cargo-shear
  pkgs.cargo-wizard
  pkgs.cargo-show-asm
  pkgs.cargo-generate
  pkgs.cargo-readme
  pkgs.reindeer
  pkgs.crate2nix
  pkgs.dioxus-cli

  # ===== SQL & Data =====
  pkgs.duckdb
  pkgs.tabiew
  pkgs.visidata

  # ===== Python Ecosystem =====
  pkgs.python313
  # pkgs.uv
  # pkgs.pixi
  pkgs.ruff
  # pkgs.ty
  pkgs.basedpyright
  pkgs.pylyzer
  pkgs-stable.marimo
  # pkgs.python313Packages.radian
  pkgs.python313Packages.ipython
  pkgs.python313Packages.notebook
  # pkgs.python313Packages.marimo
  pkgs.python313Packages.jupyter-core
  pkgs.python313Packages.jupyterlab
  pkgs.python313Packages.ipykernel
  pkgs.python313Packages.polars
  pkgs.python313Packages.biopython
  pkgs.python313Packages.pysam

  # ===== R Ecosystem =====
  # pkgs.R
  # pkgs.rstudio
  pkgs.rPackages.languageserver
  pkgs.air-formatter
  # pkgs.rPackages.tidyverse
  pkgs.rPackages.BiocManager

  # ===== TOML =====
  pkgs.taplo

  # ===== Go Ecosystem =====
  pkgs.go
  pkgs.gopls
  pkgs.gotools
  pkgs.goreleaser

  # ===== Zig Ecosystem =====
  # pkgs.zig
  # pkgs.zls

  # ===== Docker =====
  pkgs.docker-ls

  # ===== YAML =====
  pkgs.yaml-language-server

  # ===== Lua Ecosystem =====
  pkgs.lua
  pkgs.luau
  pkgs.luajit
  pkgs.lua-language-server
  pkgs.stylua

  # ===== Java & JVM =====
  pkgs.openjdk
  pkgs.jdk
  pkgs.jdt-language-server
  pkgs.nextflow

  # ===== Web Development =====
  # pkgs.vscode-langservers-extracted
  pkgs.superhtml
  pkgs.fnm
  # pkgs.nodejs_23
  # pkgs.deno
  # pkgs.bun
  # pkgs.typescript
  # pkgs.typescript-language-server
  # pkgs.javascript-typescript-langserver
  # pkgs.biome
  # pkgs.oxlint
  # pkgs.rescript-language-server

  # ===== OCaml =====
  pkgs.ocaml
  # pkgs.opam

  # ===== Haskell =====
  # pkgs.haskellPackages.ghcup
  # pkgs.haskell-language-server
  # pkgs.stylish-haskell
  # pkgs.haskellPackages.fourmolu

  # ===== Lean 4 =====
  # pkgs.lean4

  # ===== BEAM VM (Erlang/Elixir/Gleam) =====
  pkgs.erlang
  pkgs.rebar3
  pkgs.gleam
  pkgs.beam28Packages.elixir
  pkgs.beam28Packages.elixir-ls

  # ===== Authoring & Documentation =====
  pkgs.marksman
  pkgs.markdown-oxide
  pkgs.rumdl
  pkgs.typst
  pkgs.typstyle
  pkgs.tinymist
  # pkgs.quarto
  pkgs.presenterm
  pkgs.d2

  # ===== Media Processing =====
  pkgs.poppler
  pkgs.ffmpeg
  pkgs.imagemagick
  pkgs.graphviz

  # ===== Bioinformatics =====
  pkgs.seqkit
  pkgs.minimap2
  pkgs.bedtools
  pkgs.samtools
  pkgs.bcftools

  # ===== Music =====
  pkgs.ncspot

  # ===== AI =====
  # pkgs.opencode
]
