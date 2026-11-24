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

### Rex

[Rex](https://superlogical.com/rex/docs) is a native client/server alternative
to Ghostty with Herdr, not a host for another multiplexer. Both remain installed.
Rex calls a workspace a **session**, a tab a **window** in its server API, and a
terminal pane a **block**. Closing a client window is not the same as ending its
server-side processes.

On macOS, bootstrap installs the official Preview DMG only when neither a
system nor user installation exists. New installations go into `~/Applications`;
the installer verifies Superlogical's signing identity and Gatekeeper assessment.
The download follows `latest` and is not version-locked. Rex owns subsequent app
and server updates; bootstrap does not replace an existing installation.

```bash
mise run rex:install          # initial installation, if missing
mise run dots                # deploy the CLI and GUI-safe Nushell launchers
# Open Rex Beta and enable Remote Control in Settings.
mise run rex:setup --dry-run  # inspect supported settings without applying
mise run rex:setup            # apply preferences, bindings, and OpenCode/Pi skill
mise run rex:check            # check configuration and connected-client support
```

Bootstrap does not open a GUI or grant permissions. Finish `rex:setup` once a
local Mac client is connected; with multiple clients, select one using
`REX_CLIENT`. Setup backs up Mac preferences under
`~/.local/state/dotfiles/backups` before changing them. It imports Macchiato once,
then selects the existing exact-name theme on subsequent runs. If you edit that
palette in Rex, setup preserves those edits. Duplicate exact-name themes are
reported rather than chosen arbitrarily.

The [Lua configuration](.config/rex/init.lua) owns bindings and actions;
[preferences.json](.config/rex/preferences.json) supplies Mac preferences through
Rex's public action API. `rex config check` validates Lua without applying it;
`rex config reload` applies changes without restarting terminals. There is no
automatic file watching. Edit tracked preferences and rerun `rex:setup` to
reassert them. Runtime sessions, window positions, and remote-host credentials
are not deployed.

New GUI terminals use `~/.local/bin/nu-login`, which establishes
`XDG_CONFIG_HOME` before invoking mise's Nushell with `--login`. This is important
when launching from Finder: pointing directly at the mise shim both misses the
shell's XDG environment and can fail when a terminal supplies login-style
`argv[0]`. Existing Nushell modules, Atuin, Starship, completions, mise, Direnv,
and the `code` alias for OpenCode remain shared. Berkeley Mono must already be
installed separately.

Rex keeps its native shortcuts and adds the familiar **Cmd+B** prefix:

| After Cmd+B | Action |
| --- | --- |
| H / J / K / L | Focus left / down / up / right |
| V / minus | Split right / down |
| Z / X | Zoom / close pane |
| C / N / P / 1–9 | New / next / previous / numbered tab |
| O / I / W | Previous / next / choose session |
| Shift+N | New session |
| R, then H/J/K/L | Resize; Escape or Enter leaves resize mode |
| Option+B / Option+Y / Cmd+R | Floating Btop / Yazi / Tuicr |
| Option+O / Option+P | OpenCode / Pi in a new tab |

Cmd+[ and Cmd+] also focus adjacent panes; Shift+Enter sends a literal newline.
Utilities and agent tabs inherit the focused terminal's foreground working
directory and load the same Nushell environment. A missing working directory
fails visibly rather than deliberately choosing home. These custom launchers
are for the local server; remote servers need their own tools and configuration.

The little Btop popup is a native Rex floating layer:

```lua
rex.session.new_layer{
  bounds = { 0.1, 0.1, 0.8, 0.8 }, -- x, y, width, height: window fractions
  focus = true,
  layout = rex.layout.block{
    flavor = "com.superlogical.terminal.shell",
    options = { command = { "btop" } },
  },
}
```

The actual `open_btop` action adds working-directory inheritance and the
Nushell launcher. Each invocation creates another floating terminal, rather
than toggling a single popup. Quit the utility to close it. Yazi uses the same
80% bounds; Tuicr uses 90%.

OpenCode and Pi receive Rex's official skill, not command hooks or guaranteed
activity-status reporting. Agent conversation recovery belongs to those tools;
Rex session restoration does not resurrect a process after a reboot. The TUI's
Jujutsu workspace plugin is not ported: use `jj workspace add` and open a Rex
session in that directory. Ghostty's exact opacity/blur and 18% cell-height
adjustment are not claimed as equivalent to Rex's Glass rendering.

`mise run check:nu-login` and `mise run check:rex` exercise launch arguments,
configuration loading, repeat setup, and failure handling without modifying live
preferences. Live keyboard input, image paste, and recovery still need an
interactive trial. To undo a trial, restore the saved preferences with Rex
closed (`defaults import com.superlogical.rex /path/to/preferences.plist`),
then reopen it. Removing deployment declarations does not uninstall the app or
remove existing deployed files.

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

### Browser access

Global mise installs the pinned official `@opencode/browse` package; the managed
OpenCode configuration runs its MCP server through mise. Bootstrap installs the
CLI and applies that configuration without opening a browser. On each machine,
run:

```bash
mise run browse:setup
```

Install the extension from the printed Chrome Web Store link in Helium (or
another supported Chromium browser), unless it is already installed. In its
Options, enter the pairing code printed by the task. Pairing keys and
browser state remain local in browse's XDG directories, outside this repository.
Check the connection with `browse status --json`.

Browse's self-updater is disabled so mise owns CLI upgrades. Change the version
in `.config/mise/config.toml`, then run `mise install npm:@opencode/browse` and
`mise lock --global npm:@opencode/browse`. Chrome manages extension updates
separately. Node.js 22.19 or newer is required, including in projects that override
the global Node version. Use the pairing task rather than `browse install`, which
can install another npm-global copy and rewrite agent configuration.

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

TypeScript servers use workspace-local dependencies, never a global compiler or
language server. Classic TypeScript projects need `typescript-language-server`
as a development dependency alongside `typescript`; Neovim selects `ts_ls` and
passes the local `typescript/lib/tsserver.js` path. Native TypeScript projects use
their local `tsc` or `tsgo` LSP. A declared `@effect/tsgo` takes precedence and keeps
its Effect-specific integration. Missing local tools produce an error rather than
an automatic installation or global fallback. Run `mise run check:typescript-lsp`
to verify selection, launch commands, missing dependencies, and Deno exclusion.
