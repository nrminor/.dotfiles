{
  # OCaml LSP — assumes ocaml-lsp-server is on PATH via opam.
  # We don't install via nix because opam manages the toolchain
  # and ocamllsp needs to match the project's compiler version.
  # If ocamllsp isn't installed, nvim works fine — LSP just won't attach.
  plugins.lsp.servers.ocamllsp = {
    enable = true;
    package = null;
  };
}
