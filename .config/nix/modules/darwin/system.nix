# macOS system preferences
#
# Declarative configuration for Dock, Finder, and other
# macOS settings normally configured in System Preferences.
{ username, ... }:

let
  userHome = "/Users/${username}";
in
{
  system.defaults = {
    # Dock
    dock = {
      autohide = false;
      mineffect = "scale";
      orientation = "right";
      persistent-apps = [
        "/Applications/Arc.app"
        "/Applications/Superhuman.app"
        "/Applications/Bear.app"
        "/Applications/Ghostty.app"
      ];
      wvous-tr-corner = 1;
      wvous-tl-corner = 1;
      wvous-br-corner = 1;
      wvous-bl-corner = 1;
      tilesize = 28;
      show-recents = false;
      show-process-indicators = true;
      persistent-others = [
        {
          folder = {
            path = "${userHome}/Downloads";
            arrangement = "date-added";
            displayas = "stack";
            showas = "automatic";
          };
        }
      ];
    };

    # Finder
    finder = {
      AppleShowAllExtensions = false;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      FXPreferredViewStyle = "Nlsv";
      FXEnableExtensionChangeWarning = false;
      FXDefaultSearchScope = "SCcf";
      CreateDesktop = false;
      _FXSortFoldersFirst = true;
    };

    # Login window
    loginwindow = {
      autoLoginUser = username;
    };

    # Miscellaneous
    menuExtraClock.ShowSeconds = true;
    screencapture.location = "${userHome}/Documents/screenshots";

    # Custom preferences (raw 'defaults write' for domains not exposed as options)
    CustomUserPreferences = {
      "com.apple.finder" = {
        ShowExternalHardDrivesOnDesktop = false;
        ShowHardDrivesOnDesktop = false;
        ShowMountedServersOnDesktop = false;
        ShowRemovableMediaOnDesktop = false;
        _FXSortFoldersFirst = true;
        FXDefaultSearchScope = "SCcf";
      };

      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };

      "com.apple.print.PrintingPrefs" = {
        "Quit When Finished" = true;
      };

      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        ScheduleFrequency = 1;
        AutomaticDownload = 1;
        CriticalUpdateInstall = 1;
      };
    };
  };
}
