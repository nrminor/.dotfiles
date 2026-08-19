# Common packages
#
# A list of packages that work across platforms. This is pure data -
# it returns a list, not a module configuration. The consuming module
# decides where to install them (environment.systemPackages, home.packages, etc.)
{ pkgs, inputs }:

let
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
[
  # ===== Build Tools & System Libraries =====
  pkgs.cmake
]
++ pkgs.lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin) [
  pkgs.clang
]
++ [
  pkgs.libiconv
  pkgs.pkgconf # Modern pkg-config replacement
  pkgs.zlib
  pkgs.llvm
  pkgs.gettext

  # ===== Core CLI Tools =====
  pkgs.less
  pkgs.parallel
  pkgs.curl
  pkgs.wget
  pkgs.unixtools.watch
  pkgs.fzf-make
  pkgs.tokei
  pkgs.xz
  pkgs.zstd
  pkgs.bzip2
  # pkgs.tailspin

  # ===== Nushell Tooling =====
  pkgs.topiary
  pkgs.nufmt

  # ===== Disk Usage & Monitoring =====
  pkgs.htop
  # pkgs.bottom

  # ===== Git & Version Control =====
  pkgs.git
  pkgs.mergiraf
  pkgs.gitlogue # for funzies

  # ===== Development Tools =====
  pkgs.just
  # pkgs.mask
  pkgs.usage
  pkgs.watchexec
  pkgs-stable.watchman
  pkgs.lychee
  # pkgs.gnuplot
  pkgs.tlrc
  pkgs.binsider

  # ===== Media Processing =====
  pkgs.ghostscript
  pkgs.graphviz

  # ===== Bioinformatics =====
  pkgs.minimap2
  pkgs.bedtools
  pkgs.samtools
  pkgs.bcftools

  # ===== Authoring & Documentation =====
  pkgs.markdown-oxide
  pkgs.typst
  pkgs.typstyle
  pkgs.tinymist
  pkgs.pandoc
  # pkgs.quarto # can't install quarto this way because it will hardcode the nix python install instead of using local venvs
  pkgs.presenterm

  # ===== Bash/Zsh =====
  pkgs-stable.bash-language-server
  pkgs.shellcheck
  pkgs.shfmt

  # ===== Awk =====
  pkgs.gawk
  pkgs.awk-language-server

  # ===== Rust Ecosystem =====
  pkgs.rustup
  pkgs.mdbook
  pkgs.rust-script
  # pkgs.evcxr
  pkgs.maturin
  pkgs.bacon
  pkgs.rusty-man
  pkgs.cargo-nextest
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
  pkgs.cargo-sweep
  pkgs.cargo-cache
  pkgs.cargo-semver-checks
  pkgs.crate2nix
  pkgs.dioxus-cli
  pkgs.rust-cbindgen
  pkgs.rune
  pkgs.rune-languageserver

  # ===== WebAssembly =====
  pkgs.wasm-pack

  # ===== SQL & Data =====
  pkgs.duckdb
  # pkgs.tabiew

  # ===== Python Ecosystem =====
  pkgs.python313

  # ===== Go Ecosystem =====
  pkgs.go
  pkgs.gopls
  pkgs.gotools
  pkgs.goreleaser

  # ===== YAML =====
  pkgs.yaml-language-server

  # ===== TOML =====
  pkgs.taplo

  # ===== Nix Tooling =====
  pkgs.nixd
  pkgs.nixfmt
  pkgs.nil
  pkgs.statix

  # ===== Docker =====
  pkgs.docker-ls

  # ===== Lua Ecosystem =====
  # Note: lua, luau, and luajit conflict (all provide /bin/lua)
  # Using luajit as it's the most common; comment out others
  # pkgs.lua
  # pkgs.luau
  pkgs.luajit
  pkgs.lua-language-server
  pkgs.stylua

  # ===== R Ecosystem =====
  pkgs-stable.R
  pkgs.radian # pulls in unstable R + texlive; install via pip if needed
  # Note: R packages may conflict in home.packages buildEnv - testing
  # pkgs.rPackages.languageserver
  pkgs.air-formatter

  # ===== Java & JVM =====
  pkgs.openjdk
  pkgs.jdk
  pkgs.jdt-language-server
  # pkgs.nextflow

  # ===== OCaml =====
  pkgs.ocaml

  # ===== Haskell =====
  # pkgs.haskellPackages.ghcup
  # pkgs.haskell-language-server
  # pkgs.stylish-haskell
  # pkgs.haskellPackages.fourmolu

  # ===== BEAM VM (Erlang/Elixir/Gleam) =====
  pkgs.beamPackages.erlang
  pkgs.rebar3
  pkgs.gleam
]
