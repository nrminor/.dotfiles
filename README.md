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
bootstrap tools live under [`.config/nix`](.config/nix), while user-level tools,
including the complete Nushell distribution, live in
[mise's global configuration](.config/mise/config.toml). Nushell commands and
aliases live under [`.config/nushell`](.config/nushell).

This setup is deliberately peculiar to me and changes frequently. Treat it as
a reference or starting point rather than a general-purpose macOS distribution.

## Set up a new Apple machine

Install mise using its upstream installation instructions. On a fresh Mac,
invoking `git` prompts macOS to install the Xcode command-line tools if they are
not already present. Clone and bootstrap the user environment after that
finishes:

```bash
git clone https://github.com/nrminor/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
mise trust
mise bootstrap --yes
```

Bootstrap installs platform packages, pulls in some source repositories,
applies dotfiles, installs declared tools, prepares this checkout, and finally
synchronizes globally managed agent skills. `mise run setup` can repeat the
checkout preparation as needed without rerunning machine bootstrap.

Install Nix separately to establish the macOS system layer and enable flakes:

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

## Work with the system day to day

The common workflows are explicit:

```bash
mise run nix:darwin:rebuild   # rebuild and activate nix-darwin
mise run nix:darwin:update    # update the system flake, then rebuild
mise run dots                  # apply managed dotfiles
mise run dots:dry              # preview dotfile changes
mise run dots:status           # report missing or drifted dotfiles
```

The corresponding high-frequency aliases are available through mise:

```bash
mise run b   # rebuild
mise run u   # update
mise run f   # format
mise run c   # check
mise run v   # validate
```

Run `mise tasks` to see the complete task surface. Longer workflows are
executable Nushell file tasks under `.mise/tasks`; short leaf tasks are declared
in `mise.toml`.

### Nushell

Mise installs Nushell from its official release bundle and registers the
release-matched Polars, query, Git status, and format plugins. Update the
distribution directly through mise:

```bash
mise up nushell
```

Plugin registration runs automatically after installation and updates. It can
also be repaired or refreshed through either interface:

```bash
mise run nu:plugins
nu plugins sync
```

Start a new Nushell process after refreshing the registry so it loads the new
plugin command signatures.

### Tool lockfiles

The repository has one lockfile per mise configuration scope. `mise.lock`
pins the repository tools declared in `mise.toml`; `.config/mise/mise.lock`
pins the global user environment declared in `.config/mise/config.toml`. Both
cover macOS ARM64, Linux x86_64, and Linux ARM64 and belong in version control.

Refresh the existing versions and platform metadata without changing the TOML
declarations:

```bash
mise lock
GITHUB_TOKEN="$(gh auth token)" mise lock --global
```

### Pi

[Pi](https://pi.dev/) is a minimal alternative to OpenCode. Global mise installs
the pinned CLI; dotfiles deploy its [working preferences](.config/pi/AGENTS.md)
and [settings](.config/pi/settings.json) to `~/.pi/agent`. The default model is
`openai/gpt-6.1-sol`. The pinned community package
[`pi-catppuccin`](https://github.com/madeleineostoja/pi-catppuccin) supplies Latte
for light terminals and Macchiato for dark terminals, switching automatically.
Pi discovers the existing `~/.agents/skills` directory natively, so it needs no
separate skill installation. OpenCode remains unchanged.

To install or reapply this setup on an existing machine:

```bash
mise install npm:@earendil-works/pi-coding-agent
mise run dots:dry
mise run dots
pi
```

Use `/login` to authenticate and `/model` to change the current model. Credentials,
trust decisions, and sessions stay local under `~/.pi/agent`, outside this
repository. Pi can write preferences and runtime metadata back to the deployed
settings file; review those changes before committing. Node 22.19 or newer must
be available, including in projects that override the global Node version.

Start with the built-in tools: no third-party extensions, MCP servers, subagents,
goal tracking, or custom prompt templates are configured. Skills load their
full instructions on demand; `/skill:name` invokes one explicitly. Some shared
skills assume another harness's tools and may need adaptation.

The working preferences are guidance, not enforced permissions. Pi does not
inherit OpenCode's ask/deny rules and runs tools with the current user's OS
permissions. Update its executable through mise rather than Pi's self-updater;
change the version pin deliberately and refresh the global lockfile.

### Yazi

Mise installs Yazi and its `ya` package manager from the same official release.
The tracked `package.toml` pins plugins and flavors by revision and content hash;
machine bootstrap restores them automatically. Repeat that convergence with:

```bash
mise run yazi:packages
```

Use `ya pkg upgrade` when intentionally advancing package revisions. The
generated `plugins/` and `flavors/` directories are owned exclusively by
`ya pkg`; mise owns the hand-written configuration and package manifest.
Portable preview dependencies come from official release bundles where
available and otherwise from mise's rootless Conda backend. This keeps the same
declarative setup across macOS and Linux without choosing a Linux distribution
package manager or creating user-managed Conda environments.

### System administration

Darwin system operations live under `nix:darwin:*`; cross-platform Nix
operations remain under `nix:*`:

```bash
mise run nix:darwin:build
mise run nix:darwin:generations
mise run nix:darwin:rollback
mise run nix:darwin:switch-generation 42
mise run nix:update-lock
mise run nix:update-input nixpkgs
```

Manual cleanup remains available for periods of heavy Nix iteration:

```bash
mise run nix:gc
mise run nix:store-size
mise run nix:darwin:clean-generations
mise run nix:darwin:clean
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
pre-commit hooks, Statix and the system flake checks, the TypeScript compiler, and
Nushell syntax checks.

The custom repository validator can be run with:

```bash
mise run validate
```

### Neovim

Mise supplies Neovim and deploys the ordinary Lua configuration under
`.config/nvim`. Neovim's built-in `vim.pack` restores plugins at the
revisions in `nvim-pack-lock.json`. Language servers, formatters, linters, and
additional Tree-sitter parsers come from the active development environment or
explicit editor installation rather than from the editor bootstrap.
