# A growing bundle of dotfiles for bioinformatics and software development

That's right: another person's dotfiles. I use a lot of tools as a
bioinformatician and data scientist, but most of this repository supports a
small core environment:

1. [Nushell](https://www.nushell.sh/), my shell and command-line environment
2. [Neovim](https://neovim.io/), my text editor and development environment
3. [Ghostty](https://ghostty.org/), my terminal
4. [Jujutsu](https://github.com/jj-vcs/jj), my Git-compatible version control system
5. [OpenCode](https://opencode.ai/), my AI coding-agent harness

The wider system includes scientific tooling, notebook environments, language
servers, terminal utilities, and desktop applications. System packages and
bootstrap tools live under [`.config/nix`](.config/nix), while user-level tools
live in [mise's global configuration](.config/mise/config.toml). Nushell
commands and aliases live under [`.config/nushell`](.config/nushell).

This setup is deliberately peculiar to me and changes frequently. Treat it as
a reference or starting point rather than a general-purpose macOS distribution.

## How the environment is divided

Three tools divide system and user-environment responsibilities:

```text
nix-darwin  machine configuration, applications, and bootstrap tools
mise        global and project tools, environment variables, and tasks
Dotter      configuration-file deployment
```

Nix remains the source of truth for the machine. Mise owns portable user-level
tools, replaces the former root development flake, and exposes repository
workflows through `mise run`.
Project-local Node dependencies are pinned in the pnpm-compatible
`pnpm-lock.yaml`.

Just and direnv remain installed globally for compatibility with other
repositories, but this repository has neither a justfile nor an `.envrc`.

## Set up a new Apple machine

On a fresh Mac, invoking `git` prompts macOS to install the Xcode command-line
tools if they are not already present. Clone the repository after that finishes:

```bash
git clone https://github.com/nrminor/.dotfiles.git ~/.dotfiles
```

Install Nix and enable flakes:

```bash
sh <(curl -L https://nixos.org/nix/install)
mkdir -p ~/.config/nix
printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
```

Restart the terminal, or load the Nix daemon profile in the current shell, and
apply the initial nix-darwin configuration:

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix run nix-darwin -- switch --flake ~/.dotfiles/.config/nix#starter
```

The first rebuild installs the global environment, including mise, Nushell,
Dotter, and Prek. Prepare the checkout after opening a fresh shell:

```bash
cd ~/.dotfiles
mise trust
mise run setup
```

`setup` installs the tools pinned by `mise.lock`, installs the locked Node
dependencies, and installs the repository hooks. It does not rebuild the system
or deploy dotfiles.

The preferred mise executable may be a self-updating installation in
`~/.local/bin`; nix-darwin also provides a fallback. The project declares the
oldest mise version its configuration supports rather than requiring both
installations to be on the same patch release.

## Work with the system day to day

The common workflows are intentionally short:

```bash
mise run rebuild       # rebuild and activate nix-darwin
mise run update        # update the system flake, then rebuild
mise run deploy        # deploy managed dotfiles
mise run full-update   # update, rebuild, then deploy
```

The corresponding high-frequency aliases are available through mise:

```bash
mise run b   # rebuild
mise run u   # update
mise run d   # deploy
mise run f   # format
mise run c   # check
mise run v   # validate
```

Run `mise tasks` to see the complete task surface. Longer workflows are
executable Nushell file tasks under `.mise/tasks`; short leaf tasks are declared
in `mise.toml`.

### System administration

The `nix:*` namespace keeps less-frequent operations explicit:

```bash
mise run nix:build
mise run nix:update-lock
mise run nix:update-input nixpkgs
mise run nix:generations
mise run nix:rollback
mise run nix:switch-generation 42
```

Manual cleanup remains available for periods of heavy Nix iteration:

```bash
mise run nix:gc
mise run nix:clean-generations
mise run nix:clean
mise run nix:store-size
```

Automatic garbage collection still runs through nix-darwin; these tasks are
deliberate ways to reclaim space sooner.

### Formatting and verification

Formatting is mutating; checking is not:

```bash
mise run format
mise run check
```

`format` runs the maintained Nix, shell, and TOML formatters. `check` runs all
Prek hooks, Statix and the system flake checks, the TypeScript compiler, Clippy,
and Nushell syntax checks. Prek remains the low-level Git-hook and file-selection
engine beneath mise's orchestration.

The custom repository validator has TypeScript, Rust, and Nushell
implementations:

```bash
mise run validate             # TypeScript by default
mise run validate rust
mise run validate nu
mise run validate all
```

TypeScript is a project dependency so tools resolve the compiler associated
with this checkout. Mise adds `node_modules/.bin` to `PATH`, making the compiler
available alongside its mise-managed Node runtime.

### Neovim

Mise supplies Neovim, Dotter deploys the ordinary Lua configuration under
`.config/nvim`, and Neovim's built-in `vim.pack` restores plugins at the
revisions in `nvim-pack-lock.json`. Language servers, formatters, linters, and
additional Tree-sitter parsers come from the active development environment or
explicit editor installation rather than from the editor bootstrap.
