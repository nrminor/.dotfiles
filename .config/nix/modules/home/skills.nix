# Claude/OpenCode skills from Anthropic
#
# Dynamically discovers and links all skills from the anthropic-skills
# flake input to ~/.claude/skills/. Custom skills (duckdb, typst, etc.)
# are managed separately by Dotter.
#
# Skills are linked individually so that Dotter can add custom skills
# to the same directory without conflicts.
{ inputs, lib, ... }:

let
  # Path to the skills directory in the anthropic-skills repo
  skillsSource = "${inputs.anthropic-skills}/skills";

  # Read the directory contents and filter to only directories
  skillsDir = builtins.readDir skillsSource;
  skillNames = builtins.filter (name: skillsDir.${name} == "directory") (
    builtins.attrNames skillsDir
  );

  # Generate home.file entries for each skill
  skillFiles = builtins.listToAttrs (
    map (name: {
      name = ".claude/skills/${name}";
      value = {
        source = "${skillsSource}/${name}";
      };
    }) skillNames
  );
in
{
  home.file = skillFiles;
}
