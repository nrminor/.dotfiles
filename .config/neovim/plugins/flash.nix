{
  plugins.flash = {
    enable = true;
    settings = {
      # Use lowercase labels for easier typing
      labels = "asdfghjklqwertyuiopzxcvbnm";
      modes = {
        # Disable flash in search mode (keep normal / and ? behavior)
        search.enabled = false;
      };
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<cr>";
      action = ''<cmd>lua require("flash").jump()<cr>'';
      options = {
        desc = "Flash jump (goto word)";
      };
    }
    {
      mode = "n";
      key = "S";
      action = ''<cmd>lua require("flash").treesitter()<cr>'';
      options = {
        desc = "Flash treesitter select";
      };
    }
  ];
}
