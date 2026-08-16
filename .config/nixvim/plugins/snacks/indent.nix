{
  plugins.snacks.settings.indent = {
    enabled = true;
    indent = {
      enabled = false;
    };

    scope = {
      # enabled = false;
      hl = "Comment";
    };

    chunk = {
      enabled = true;
      only_current = true;
      char = {
        arrow = "─";
        corner_top = "╭";
        corner_bottom = "╰";
      };
      hl = "Comment";
    };
  };
}
