{
  extraFiles."flash-helix-word-jump.lua" = {
    source = ./flash.lua;
    target = "lua/user/flash.lua";
  };

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
      action = ''<cmd>lua require("user.flash").helix_word_jump()<cr>'';
      options = {
        desc = "Flash Helix-style word jump";
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
    {
      mode = "x";
      key = "S";
      action = ''<esc><cmd>lua MiniSurround.add("visual")<cr>'';
      options = {
        desc = "Surround visual selection";
      };
    }
  ];
}
