{
  extraFiles = {
    "markdown/injections.scm" = {
      source = ./queries/markdown/injections.scm;
      target = "after/queries/markdown/injections.scm";
    };
    "markdown/highlights.scm" = {
      source = ./queries/markdown/highlights.scm;
      target = "after/queries/markdown/highlights.scm";
    };
    "markdown/textobjects.scm" = {
      source = ./queries/markdown/textobjects.scm;
      target = "after/queries/markdown/textobjects.scm";
    };
  };

  filetype = {
    extension = {
      mdx = "mdx";
    };
  };

  plugins.treesitter.languageRegister = {
    "markdown" = "mdx";
  };
}
