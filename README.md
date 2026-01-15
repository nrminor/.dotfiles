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
See all installed packages starting
[here](https://github.com/nrminor/.dotfiles/blob/2be595fadbd191db1105c6b63ee6c23c25d0df79/.config/nix-darwin/flake.nix#L43)
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

First, assuming you've fired up a Terminal window on a new apple computer, we
first need these dotfiles, which include a Nix flake:

```bash
git clone https://github.com/nrminor/.dotfiles.git ~/.dotfiles
```

Next, we'll install NixOS:

```bash
sh <(curl -L https://nixos.org/nix/install)
```

And finally, we'll run the installer:

```bash
nix run nix-darwin  -- switch --flake ~/.dotfiles/.config/nix-darwin#starter
```

That's it! And to apply any changes to the OS that have been committed to this
repo, run:

```bash
darwin-rebuild switch --flake ~/.config/nix-darwin
```

All said, this setup is very peculiar to me and should be expected to change
frequently. Use at your own risk—or, use as a starting point for your own NixOS
journey!
