# Dotfiles Management Commands
# Declarative macOS environment with nix-darwin + dotter

export FLAKE_DIR := env_var_or_default('XDG_CONFIG_HOME', env_var('HOME') + '/.config') + '/nix-darwin'
export DOTFILES_DIR := env_var('HOME') + '/.dotfiles'

# Default recipe shows available commands
[group('help')]
default:
    @just --list --unsorted

# Show all available recipes with descriptions
[group('help')]
help:
    @just --list

# ===== Deploy Operations =====

# Deploy dotfiles with dotter
[group('deploy')]
deploy:
    @echo "Deploying dotfiles..."
    dotter deploy -f -v -y
    @echo "✓ Dotfiles deployed"

alias d := deploy

# Deploy dotfiles to a specific target (useful for testing)
[group('deploy')]
deploy-to target:
    @echo "Deploying to {{ target }}..."
    dotter deploy -f -v -y --target {{ target }}

alias dt := deploy-to

# Dry run deployment (see what would change)
[group('deploy')]
deploy-dry:
    @echo "Performing dry run..."
    dotter deploy -v -y --dry-run

alias dd := deploy-dry

# Force deploy even if files haven't changed
[group('deploy')]
deploy-force:
    @echo "Force deploying all dotfiles..."
    dotter deploy -f -v -y --force
    @echo "✓ Force deployment complete"

alias df := deploy-force

# Deploy and reload shell
[group('deploy')]
deploy-reload: deploy
    @echo "Reloading shell configuration..."
    @exec zsh

alias dr := deploy-reload

# ===== System Operations =====

# Update nix-darwin flake and rebuild system
[group('system')]
update:
    @echo "Updating nix-darwin flake..."
    cd {{ FLAKE_DIR }} && nix flake update
    @echo "Rebuilding system..."
    darwin-rebuild switch --flake {{ FLAKE_DIR }}
    @echo "✓ System updated and rebuilt"

alias u := update

# Just rebuild system without updating flake
[group('system')]
rebuild:
    @echo "Rebuilding system..."
    darwin-rebuild switch --flake {{ FLAKE_DIR }}
    @echo "✓ System rebuilt"

alias r := rebuild

# Update flake.lock without rebuilding
[group('system')]
update-flake:
    @echo "Updating flake.lock..."
    cd {{ FLAKE_DIR }} && nix flake update
    @echo "✓ Flake updated"

alias uf := update-flake

# Show what would change without rebuilding
[group('system')]
rebuild-dry:
    darwin-rebuild build --flake {{ FLAKE_DIR }}

alias rd := rebuild-dry

# Full system update: flake + rebuild + deploy dotfiles
[group('system')]
full-update: update deploy
    @echo "✓ Full system update complete"

alias fu := full-update

# List nix-darwin generations
[group('system')]
generations:
    darwin-rebuild --list-generations

alias g := generations

# Rollback to previous generation
[group('system')]
rollback:
    @echo "Rolling back to previous generation..."
    darwin-rebuild --rollback
    @echo "✓ Rolled back"

alias rb := rollback

# Switch to specific generation
[group('system')]
switch-generation gen:
    @echo "Switching to generation {{ gen }}..."
    darwin-rebuild switch --flake {{ FLAKE_DIR }} --switch-generation {{ gen }}

alias sg := switch-generation

# ===== Maintenance Operations =====

# Run nix garbage collection
[group('maintenance')]
gc:
    @echo "Running garbage collection..."
    nix-collect-garbage -d
    @echo "✓ Garbage collection complete"

alias clean := gc

# Deep clean: gc + optimize store
[group('maintenance')]
deep-clean:
    @echo "Running deep clean..."
    nix-collect-garbage -d
    nix store optimise
    @echo "✓ Deep clean complete"

alias dc := deep-clean

# Delete old system generations (keeps last 5)
[group('maintenance')]
clean-generations:
    @echo "Deleting old generations (keeping last 5)..."
    sudo nix-env --delete-generations +5 --profile /nix/var/nix/profiles/system
    @echo "✓ Old generations cleaned"

alias cg := clean-generations

# Full cleanup: generations + gc + optimize
[group('maintenance')]
full-clean: clean-generations gc
    @echo "Optimizing nix store..."
    nix store optimise
    @echo "✓ Full cleanup complete"

alias fc := full-clean

# Check health of dotfiles setup
[group('maintenance')]
health:
    @echo "Checking dotfiles health..."
    @echo ""
    @echo "Dotfiles directory:"
    @test -d {{ DOTFILES_DIR }} && echo "  ✓ Found at {{ DOTFILES_DIR }}" || echo "  ✗ Missing!"
    @echo ""
    @echo "Nix-darwin flake:"
    @test -f {{ FLAKE_DIR }}/flake.nix && echo "  ✓ Found at {{ FLAKE_DIR }}" || echo "  ✗ Missing!"
    @echo ""
    @echo "Dotter configuration:"
    @test -f {{ DOTFILES_DIR }}/.dotter/global.toml && echo "  ✓ Found" || echo "  ✗ Missing!"
    @echo ""
    @echo "Key tools:"
    @command -v dotter >/dev/null && echo "  ✓ dotter" || echo "  ✗ dotter not found"
    @command -v nix >/dev/null && echo "  ✓ nix" || echo "  ✗ nix not found"
    @command -v darwin-rebuild >/dev/null && echo "  ✓ darwin-rebuild" || echo "  ✗ darwin-rebuild not found"
    @command -v hx >/dev/null && echo "  ✓ helix" || echo "  ✗ helix not found"
    @command -v zellij >/dev/null && echo "  ✓ zellij" || echo "  ✗ zellij not found"
    @command -v yazi >/dev/null && echo "  ✓ yazi" || echo "  ✗ yazi not found"
    @echo ""
    @echo "Flake status:"
    @cd {{ FLAKE_DIR }} && nix flake metadata 2>/dev/null | head -5 || echo "  ✗ Unable to read flake"

alias h := health

# Check for broken symlinks in home directory
[group('maintenance')]
check-links:
    @echo "Checking for broken symlinks..."
    @find ~ -maxdepth 3 -type l ! -exec test -e {} \; -print 2>/dev/null | head -20 || echo "No broken symlinks found"

alias cl := check-links

# Show disk usage of nix store
[group('maintenance')]
store-size:
    @echo "Nix store disk usage:"
    @du -sh /nix/store 2>/dev/null || echo "Unable to read nix store"
    @echo ""
    @echo "Largest store paths:"
    @nix path-info --all --json 2>/dev/null | jq -r '.[] | "\(.narSize)\t\(.path)"' | sort -rn | head -10 | numfmt --field=1 --to=iec-i 2>/dev/null || echo "Unable to analyze store"

alias ss := store-size

# ===== Development Operations =====

# Edit nix-darwin flake in Helix
[group('dev')]
edit-flake:
    hx {{ FLAKE_DIR }}/flake.nix

alias ef := edit-flake

# Edit dotter configuration
[group('dev')]
edit-dotter:
    hx {{ DOTFILES_DIR }}/.dotter/global.toml {{ DOTFILES_DIR }}/.dotter/macos.toml

alias ed := edit-dotter

# Edit this justfile
[group('dev')]
edit-just:
    hx {{ DOTFILES_DIR }}/justfile

alias ej := edit-just

# Edit zshrc
[group('dev')]
edit-zsh:
    hx {{ DOTFILES_DIR }}/.zshrc

alias ez := edit-zsh

# Edit Helix config
[group('dev')]
edit-helix:
    hx {{ DOTFILES_DIR }}/.config/helix/config.toml

alias eh := edit-helix

# Edit Ghostty config
[group('dev')]
edit-ghostty:
    hx {{ DOTFILES_DIR }}/.config/ghostty/config

alias egg := edit-ghostty

# Reload shell configuration without restarting
[group('dev')]
reload:
    @echo "Reloading shell..."
    @exec zsh

alias rl := reload

# Show flake inputs and their versions
[group('dev')]
show-inputs:
    @echo "Flake inputs:"
    @cd {{ FLAKE_DIR }} && nix flake metadata --json | jq -r '.locks.nodes | to_entries[] | select(.value.locked) | "\(.key): \(.value.locked.rev // .value.locked.narHash)"'

alias si := show-inputs

# Update specific flake input
[group('dev')]
update-input input:
    @echo "Updating {{ input }}..."
    cd {{ FLAKE_DIR }} && nix flake lock --update-input {{ input }}
    @echo "✓ {{ input }} updated"

alias ui := update-input

# ===== Formatting & Linting =====

# Format all Nix files in dotfiles
[group('format')]
fmt-nix:
    @echo "Formatting Nix files..."
    @find {{ DOTFILES_DIR }} -name "*.nix" -type f -exec nixfmt {} \;
    @echo "✓ Nix files formatted"

alias fn := fmt-nix

# Format all shell scripts
[group('format')]
fmt-shell:
    @echo "Formatting shell scripts..."
    @find {{ DOTFILES_DIR }} -name "*.sh" -o -name ".zshrc" -o -name ".zprofile" -o -name ".zshenv" -o -name ".direnvrc" | xargs -I {} shfmt -w -i 0 -ci {}
    @echo "✓ Shell files formatted"

alias fs := fmt-shell

# Format all TOML files
[group('format')]
fmt-toml:
    @echo "Formatting TOML files..."
    @find {{ DOTFILES_DIR }} -name "*.toml" -type f -exec taplo format {} \;
    @echo "✓ TOML files formatted"

alias ft := fmt-toml

# Format all JSON files
[group('format')]
fmt-json:
    @echo "Formatting JSON files..."
    @find {{ DOTFILES_DIR }} -name "*.json" -o -name "*.jsonc" -type f -exec sh -c 'jq --indent 2 . "{}" > "{}.tmp" && mv "{}.tmp" "{}"' \;
    @echo "✓ JSON files formatted"

alias fj := fmt-json

# Format all KDL files
[group('format')]
fmt-kdl:
    @echo "Checking KDL files..."
    @echo "Note: KDL formatting not yet implemented (no standard formatter available)"
    @find {{ DOTFILES_DIR }} -name "*.kdl" -type f

alias fk := fmt-kdl

# Format all supported file types
[group('format')]
fmt: fmt-nix fmt-shell fmt-toml fmt-json
    @echo "✓ All files formatted"

alias f := fmt

# Lint shell scripts with shellcheck
[group('lint')]
lint-shell:
    @echo "Linting shell scripts..."
    @find {{ DOTFILES_DIR }} -name "*.sh" -type f -exec shellcheck {} \;
    @echo "✓ Shell scripts checked"

alias ls := lint-shell

# Lint Nix files with statix
[group('lint')]
lint-nix:
    @echo "Linting Nix files..."
    @find {{ DOTFILES_DIR }} -name "*.nix" -type f -exec statix check {} \; || echo "Note: statix not available in current environment"

alias ln := lint-nix

# Check nix flake for issues
[group('lint')]
check-flake:
    @echo "Checking nix flake..."
    cd {{ FLAKE_DIR }} && nix flake check

alias cf := check-flake

# Run all checks
[group('lint')]
check: lint-shell check-flake
    @echo "✓ All checks passed"

alias c := check

# ===== Quick Operations =====

# Quick edit and deploy workflow
[group('quick')]
qed file: && deploy
    hx {{ DOTFILES_DIR }}/{{ file }}

# Quick system rebuild (most common operation)
[group('quick')]
q: rebuild

# Quick edit zshrc and reload
[group('quick')]
qz: edit-zsh reload

# Quick edit flake and rebuild
[group('quick')]
qf: edit-flake rebuild

# Quick format and check
[group('quick')]
qc: fmt check

# ===== Information =====

# Show system information
[group('info')]
sysinfo:
    @echo "System Information"
    @echo "=================="
    @echo ""
    @echo "Hostname: $(hostname)"
    @echo "macOS: $(sw_vers -productVersion)"
    @echo "Architecture: $(uname -m)"
    @echo ""
    @echo "Nix version:"
    @nix --version
    @echo ""
    @echo "Current generation:"
    @darwin-rebuild --list-generations | tail -1
    @echo ""
    @echo "Dotfiles:"
    @cd {{ DOTFILES_DIR }} && git log -1 --format="  Last commit: %h - %s (%cr)" 2>/dev/null || echo "  Not a git repository"

alias info := sysinfo
alias i := sysinfo

# Show installed packages from nix
[group('info')]
packages:
    @echo "Installed nix packages:"
    @nix-env -q

alias pkgs := packages

# Search for a package in nixpkgs
[group('info')]
search query:
    @echo "Searching for: {{ query }}"
    @nix search nixpkgs {{ query }}

# Show what's in the current nix-darwin generation
[group('info')]
show-generation:
    @darwin-rebuild --list-generations | tail -1

alias gen := show-generation

# ===== Backup Operations =====

# Backup current dotfiles before deploying
[group('backup')]
backup:
    @echo "Creating backup..."
    @mkdir -p ~/dotfiles_backups
    @tar -czf ~/dotfiles_backups/dotfiles_$(date +%Y%m%d_%H%M%S).tar.gz -C ~ \
        .zshrc .zprofile .zshenv .gitconfig .config/helix .config/ghostty .config/zellij .config/yazi 2>/dev/null || true
    @echo "✓ Backup created in ~/dotfiles_backups"

alias bk := backup

# List all backups
[group('backup')]
list-backups:
    @echo "Available backups:"
    @ls -lht ~/dotfiles_backups/*.tar.gz 2>/dev/null || echo "No backups found"

alias lb := list-backups

# Restore from most recent backup
[group('backup')]
restore:
    @echo "⚠️  This will restore from the most recent backup"
    @echo "Current dotfiles will be overwritten!"
    @read -p "Continue? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 1
    @latest=$$(ls -t ~/dotfiles_backups/*.tar.gz 2>/dev/null | head -1) && \
        [ -n "$$latest" ] && tar -xzf $$latest -C ~ && echo "✓ Restored from $$latest" || echo "No backups found"

# ===== Validation =====

# Validate dotfiles repository
[group('validation')]
validate:
    @echo "Validating dotfiles..."
    bun run {{ DOTFILES_DIR }}/scripts/validate-dotfiles.ts

alias v := validate

# Validate dotfiles with verbose output
[group('validation')]
validate-verbose:
    @echo "Validating dotfiles (verbose)..."
    bun run {{ DOTFILES_DIR }}/scripts/validate-dotfiles.ts --verbose

alias vv := validate-verbose

# Validate dotfiles and show fix suggestions
[group('validation')]
validate-fix:
    @echo "Validating dotfiles with fix suggestions..."
    bun run {{ DOTFILES_DIR }}/scripts/validate-dotfiles.ts --fix

alias vf := validate-fix

# Validate nix-darwin flake builds correctly
[group('validation')]
validate-flake:
    @echo "Validating nix-darwin configuration..."
    @cd {{ FLAKE_DIR }} && nix flake check
    @echo "Building configuration..."
    @darwin-rebuild build --flake {{ FLAKE_DIR }}
    @echo "✓ Flake validation passed"

alias vfl := validate-flake

# Install pre-commit hooks (run once per clone)
[group('dev')]
install-hooks:
    @echo "Installing pre-commit hooks..."
    pre-commit install
    @echo "✓ Git hooks installed"
    @echo ""
    @echo "Hooks will now run automatically on 'git commit'"
    @echo "To skip hooks: git commit --no-verify"

alias ih := install-hooks

# Run all pre-commit hooks on all files
[group('validation')]
pre-commit-all:
    @echo "Running pre-commit on all files..."
    pre-commit run --all-files

alias pca := pre-commit-all

# Update pre-commit hook versions
[group('dev')]
update-hooks:
    @echo "Updating pre-commit hook versions..."
    pre-commit autoupdate
    @echo "✓ Hooks updated"

alias uh := update-hooks

# Uninstall pre-commit hooks
[group('dev')]
uninstall-hooks:
    @echo "Uninstalling pre-commit hooks..."
    pre-commit uninstall
    @echo "✓ Git hooks uninstalled"

# Manual pre-commit checks (old recipe, kept for compatibility)
[group('validation')]
pre-commit: validate check fmt
    @echo ""
    @echo "✓ Manual pre-commit checks passed"
    @echo ""
    @echo "Tip: Install automatic hooks with 'just install-hooks'"

alias pc := pre-commit

# ===== Performance & Benchmarking =====

# Benchmark shell startup time (zsh)
[group('perf')]
bench-shell:
    @echo "Benchmarking zsh startup time..."
    @hyperfine --warmup 3 --runs 10 'zsh -i -c exit'

alias bs := bench-shell

# Benchmark shell startup with detailed breakdown
[group('perf')]
bench-shell-verbose:
    @echo "Benchmarking zsh startup with profiling..."
    @echo "Running 10 iterations..."
    @hyperfine --warmup 3 --runs 10 --export-markdown /tmp/shell-bench.md 'zsh -i -c exit'
    @echo ""
    @echo "Results saved to /tmp/shell-bench.md"
    @cat /tmp/shell-bench.md

alias bsv := bench-shell-verbose

# Compare shell startup: current vs minimal config
[group('perf')]
bench-shell-compare:
    @echo "Comparing shell startup times..."
    @echo "Current config vs minimal zsh..."
    @hyperfine --warmup 3 --runs 10 \
        --command-name "current" 'zsh -i -c exit' \
        --command-name "minimal" 'zsh --no-rcs -c exit'

alias bsc := bench-shell-compare

# Profile zsh startup to identify slow components
[group('perf')]
profile-shell:
    @echo "Profiling zsh startup (results in /tmp/zsh-profile.log)..."
    @zsh -i -c 'zprof' 2>&1 | tee /tmp/zsh-profile.log
    @echo ""
    @echo "Add 'zmodload zsh/zprof' to top of .zshrc and 'zprof' to bottom for detailed profiling"

alias ps := profile-shell

# Benchmark dotter deployment
[group('perf')]
bench-deploy:
    @echo "Benchmarking dotter deployment..."
    @hyperfine --warmup 2 --runs 5 'dotter deploy -f -y'

alias bd := bench-deploy

# Benchmark nix-darwin rebuild
[group('perf')]
bench-rebuild:
    @echo "Benchmarking darwin-rebuild (this will take a while)..."
    @hyperfine --warmup 1 --runs 3 'darwin-rebuild build --flake {{ FLAKE_DIR }}'

alias br := bench-rebuild

# Run all performance benchmarks
[group('perf')]
bench-all: bench-shell bench-deploy
    @echo "✓ All benchmarks complete"

alias ba := bench-all

# ===== Easter Egg =====

# Check network connectivity
[group('dev')]
[private]
network-check:
    @echo "Checking network connectivity..."
    @sleep 1
    @echo "Testing DNS resolution..."
    @sleep 1
    @echo "Verifying packet routing..."
    @sleep 1
    @echo "Connection established!"
    @sleep 1
    @open "https://www.youtube.com/watch?v=XhzpxjuwZy0"

alias net := network-check
alias jump := network-check

# ===== Common Aliases =====
# Semantic aliases

alias update-all := full-update
alias deploy-all := deploy
alias clean-all := full-clean
alias rebuild-system := rebuild
alias edit-config := edit-flake
alias show-health := health
alias format := fmt
alias lint := check

# Workflow shortcuts

alias build := rebuild
alias deploy-and-reload := deploy-reload
alias quick := q

# Common typos

alias depoly := deploy
alias deplyo := deploy
alias udpate := update
alias updat := update
alias rebulid := rebuild
alias rebiuld := rebuild
alias heatlh := health
alias helath := health
alias clen := gc
alias clearn := gc
alias fromat := fmt
alias fomrat := fmt

# Ultra-short for power users

alias e := edit-flake
alias b := rebuild
alias t := health
