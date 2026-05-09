# Portable Neovim outside Nix/nixvim

This repository’s normal Neovim setup is managed by Nix, Home Manager, and nixvim. That is the source of truth, but it is not always the right deployment format. Some machines may not have Nix, may not allow user-level Nix, or may simply be places where a small editor bundle is easier to reason about than a full declarative environment.

The portable export is intentionally narrower than the local setup: it copies the generated Neovim config and plugin sources, while assuming Neovim, language servers, formatters, compilers, and other executables come from the target machine’s `PATH`.

The key constraint is that native artifacts should belong to the target machine, not the Mac that produced the bundle. Do not expect tree-sitter parsers, native plugin code, or Nix-built binaries copied from macOS to work on Linux.

## Build the bundle locally

From this dotfiles repository on a machine with Nix and Nushell:

```sh
just nvim-export-portable-archive
```

This writes:

```text
dist/nvim-portable/
dist/nvim-portable.tar.gz
```

The directory is useful for local inspection. The archive is the thing to copy to the target machine.

## Install the bundle on another machine

Copy the archive to the target machine, then unpack it somewhere under your home directory:

```sh
mkdir -p ~/opt
tar -xzf ~/nvim-portable.tar.gz -C ~/opt
```

Put the launcher somewhere on your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -sf ~/opt/nvim-portable/bin/nvim-portable ~/.local/bin/nvim-portable
```

Make sure `~/.local/bin` is on `PATH`. If your shell startup files do not already do this, add the equivalent of:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

The launcher uses POSIX `sh`, not Nushell. At runtime the bundle does not require Nix, Nushell, or just.

## Check Neovim first

The generated config uses modern Neovim LSP APIs such as `vim.lsp.config` and `vim.lsp.enable`, so the target machine should provide Neovim 0.11 or newer. Check with:

```sh
nvim --version
```

If the available Neovim is too old, install a newer user-local Neovim binary and put it before the system Neovim on `PATH`. The bundle intentionally calls `nvim` from `PATH` rather than shipping its own editor binary.

You can smoke-test the launcher with:

```sh
nvim-portable --headless '+lua print("nvim-portable ok")' '+qa'
```

## Tree-sitter parsers

Do not copy tree-sitter parsers built on macOS to a Linux target. They are native shared libraries and should be built on the machine that will load them, or on a compatible machine.

After unpacking the bundle, make sure a compiler and git are available. On managed systems this may mean loading modules, for example:

```sh
module load gcc
module load git
```

Then install parsers into the bundle’s data directory:

```sh
nvim-portable --headless \
  '+TSInstallSync lua vim vimdoc query bash python rust markdown markdown_inline json yaml toml nix' \
  '+qa'
```

Because the launcher sets `XDG_DATA_HOME` to `~/opt/nvim-portable/data`, parser files should land inside the bundle rather than in your normal `~/.local/share/nvim`.

If the target machine has no internet but can compile, you may need to fetch parser sources through some other workflow. If the target cannot compile parsers at all, build them on a compatible Linux machine and copy the resulting parser files, not macOS-built ones.

## Language servers, formatters, and tools

The bundle expects external tools to come from the target environment. Install or load only what you need. Useful examples include:

```text
git, rg, fd
ruff, ty
rust-analyzer
bash-language-server, shellcheck, shfmt
lua-language-server
taplo
yaml-language-server
markdown-oxide
ocamllsp
haskell-language-server
zls
tinymist
```

Missing language servers should degrade to “no LSP for that language” rather than preventing basic editing. If a particular project provides tools through modules, virtual environments, `opam`, `ghcup`, `uv`, `npm`, or similar, load that project environment before starting `nvim-portable`.

## Native-plugin caution

The portable export is safest for Lua and Vimscript plugins. Native or native-adjacent pieces are the likely failure points, especially when the export was produced on macOS and used on Linux. Watch tree-sitter, fuzzy matching backends, and any plugin with compiled components first.

The right mental model is:

```text
bundle:       config and plugin sources
target PATH:  binaries and language tools
target host:  native compilation artifacts
```

If the export grows a long list of target-specific rewrites, stop and consider a smaller dedicated portable Neovim profile instead.
