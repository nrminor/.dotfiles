{
  description = "Development environment for dotfiles management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core dotfiles tools
            just
            nushell
            dotter
            pre-commit

            # Nix tooling
            nixd
            nixfmt-rfc-style
            nil

            # Formatters for various languages
            shfmt # Bash formatting
            jq # JSON formatting
            taplo # TOML formatting
            # Note: KDL doesn't have a standard formatter yet, but we can add one if it emerges

            # Linters
            shellcheck # Bash linting
            statix # Nix linting

            # JavaScript/TypeScript development (minimal setup)
            nodejs # Required to run typescript-language-server
            nodePackages.typescript-language-server # LSP for IDE features
            biome # Formatting & linting (standalone binary)

            # Rust development
            rustc # Rust compiler
            cargo # Rust package manager
            rust-analyzer # Rust LSP server
            rustfmt # Rust formatter
            clippy # Rust linter

            # Language servers for Helix
            just-lsp # Justfile LSP

            # Scripting and benchmarking
            bun # Fast JS/TS runtime
            rust-script # Run Rust files as scripts
            hyperfine # Command-line benchmarking

            # Utilities
            git
            ripgrep
            fd
          ];

          shellHook = ''
            echo "Dotfiles development environment loaded"
            echo ""
            echo "First-time setup:"
            echo "  pre-commit install    - Install git hooks (run once)"
            echo "  just install-hooks    - Same as above"
            echo ""
            echo "Available commands:"
            echo "  just          - Run dotfiles management tasks"
            echo "  dotter        - Deploy dotfiles"
            echo "  nixfmt        - Format Nix files"
            echo "  shfmt         - Format shell scripts"
            echo "  shellcheck    - Lint shell scripts"
            echo "  taplo         - Format TOML files"
            echo "  jq            - Format JSON files"
            echo "  biome         - Format/lint JS/TS"
            echo "  bun           - Run JS/TS scripts"
            echo "  hyperfine     - Benchmark commands"
            echo "  pre-commit    - Manage git hooks"
            echo "                ...and more!"
            echo ""
          '';
        };
      }
    );
}
