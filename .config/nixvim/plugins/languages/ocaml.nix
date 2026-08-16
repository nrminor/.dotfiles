{
  # OCaml LSP — assumes ocamllsp is on PATH via opam/switch env.
  # We intentionally do not pin via nixpkgs because ocamllsp must match
  # the project's compiler switch version.
  # If ocamllsp isn't available in PATH, LSP simply won't attach.
  plugins.lsp.servers.ocamllsp = {
    enable = true;
    package = null;
  };
}
