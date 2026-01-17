# A growing bundle of dotfiles for doing bioinformatics and software development

That's right. It's yet another guy's dotfiles. Though I use lots of tools as a
bioinformatician and data scientist, most of my configurations are for a core
set of developer tools:

1. [nushell](https://www.nushell.sh/), my shell and command-line environment
2. [Helix](https://helix-editor.com/) my text editor and development environment
3. [Ghostty](https://ghostty.org/), my terminal of choice
4. [Jujutsu](https://github.com/jj-vcs/jj), the git-compatible version control system
5. [OpenCode](https://opencode.ai/), an AI coding agent harness

(Yes, I do almost everything in the command line)

That said, the setup comes with VSCode, the Python notebook systems Marimo and
Jupyter, RStudio, etc. Other goodies include
[Raycast](https://www.raycast.com/), [DuckDB](https://duckdb.org/),
[Typst](https://typst.app/), language servers for Bash and awk,
[Atuin](https://atuin.sh/), [Ouch](https://github.com/ouch-org/ouch),
[fzf](https://junegunn.github.io/fzf/),
[btop](https://github.com/aristocratos/btop),
[imagemagick](https://github.com/ImageMagick/ImageMagick), and much, much more.
See all installed packages [here](https://github.com/nrminor/.dotfiles/blob/main/.config/nix/modules/common/packages.nix)
and my growing list of handy aliases
[here](https://github.com/nrminor/.dotfiles/blob/main/.config/nushell/aliases.nu)

If you do bioinformatics and data science and use these tools on Apple computers
like me, read on!

### Setup on a new Apple machine <!-- rumdl-disable-line MD001 -->

The point of this repository is to make setting up my development environment on
different machines easy. To do so, I use [NixOS](https://nixos.org/), and
ultimately [nix-darwin](https://github.com/LnL7/nix-darwin), to install packages
from the Nix Package Repository, from Homebrew, and from the Mac App Store. Nix
also handles downloading and deploying my dotfiles (which is to say this repo)
with [dotter](https://github.com/SuperCuber/dotter). With these tools, we can
take a very tedious series of manual installs, all of which tend toward bloat,
and reduce them to just a few commands on a new machine.

First, assuming you've fired up a Terminal window on a fresh Mac, you'll need
git. If you don't have it yet, running `git` will prompt you to install the
Xcode command line tools. Once that's done, clone this repo:

```bash
git clone https://github.com/nrminor/.dotfiles.git ~/.dotfiles
```

Next, install Nix (the package manager, not NixOS the Linux distribution):

```bash
sh <(curl -L https://nixos.org/nix/install)
```

Before running the nix-darwin installer (which sets up macOS system management), you'll need to enable flakes. Create
or edit `~/.config/nix/nix.conf` and add:

```
experimental-features = nix-command flakes
```

Then restart your terminal (or run `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`)
and run the installer:

```bash
nix run nix-darwin -- switch --flake ~/.dotfiles/.config/nix#starter
```

This will take a while on the first run—it's installing everything from the
flake, including Homebrew packages and Mac App Store apps. Once it completes,
you'll have `just` available and can use the recipes described below for
subsequent updates.

All said, this setup is very peculiar to me and should be expected to change
frequently. Use at your own risk—or, use as a starting point for your own Nix
journey!

### Working with the system day-to-day

Once the system is set up, you'll rarely need to run `darwin-rebuild` directly.
Instead, there's a justfile at the root of this repo with recipes for common
operations. Run `just` to see what's available, or `just --list` for a more
organized view.

The most common workflow is updating the system after pulling changes or editing
the flake:

```bash
just b          # rebuild the system (alias for `just rebuild`)
just u          # update flake inputs and rebuild
just d          # deploy dotfiles with dotter
```

If you want to do everything at once—update the flake, rebuild, and deploy
dotfiles—there's a recipe for that:

```bash
just fu         # full update
```

The justfile also has recipes for maintenance tasks like garbage collection
(`just gc`), checking for broken symlinks (`just check-links`), and viewing how
much disk space the Nix store is consuming (`just store-size`). If something
goes wrong, `just rollback` will switch back to the previous generation.

For editing, there are shortcuts that open the relevant files in Helix:

```bash
just ef         # edit the nix flake
just ed         # edit dotter configuration
just ez         # edit zshrc
just eh         # edit helix config
```

Finally, there are formatting and validation recipes. Before committing changes,
`just fmt` will format all Nix, shell, TOML, and JSON files, and `just check`
will run linters. The `just validate` recipe runs a custom dotfiles validator
(implementations exist in TypeScript, Rust, and Nushell for funzies—run `just validate all`
to benchmark them against each other).

The full list of recipes is extensive, but the aliases are designed to be
memorable: `b` for build, `u` for update, `d` for deploy, `f` for format, and so
on. When in doubt, `just health` will tell you if everything is wired up
correctly.
