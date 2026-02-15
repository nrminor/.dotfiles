# Claude/OpenCode skills from multiple upstreams
#
# Dynamically discovers and links all skills from upstream repositories
# to ~/.claude/skills/. Custom skills (duckdb, typst, etc.) are managed
# separately by Dotter.
#
# Skills are linked individually so that Dotter can add custom skills
# to the same directory without conflicts.
#
# Upstreams:
#   - anthropics/skills (official Anthropic skills)
#   - K-Dense-AI/claude-scientific-skills (scientific/bioinformatics skills)
{ inputs, lib, ... }:

let
  # Skills to exclude (e.g. promotional content)
  excludeSkills = [
    "offer-k-dense-web"
  ];

  # Helper function to get skill directories from a source path
  getSkillDirs =
    source:
    let
      contents = builtins.readDir source;
    in
    builtins.filter (name: contents.${name} == "directory" && !(builtins.elem name excludeSkills)) (
      builtins.attrNames contents
    );

  # Helper function to generate home.file entries from a skills source
  mkSkillFiles =
    source:
    builtins.listToAttrs (
      map (name: {
        name = ".claude/skills/${name}";
        value = {
          source = "${source}/${name}";
        };
      }) (getSkillDirs source)
    );

  # Anthropic official skills (in 'skills/' subdirectory)
  anthropicSkills = mkSkillFiles "${inputs.anthropic-skills}/skills";

  # K-Dense scientific skills (in 'scientific-skills/' subdirectory)
  kdenseSkills = mkSkillFiles "${inputs.kdense-scientific-skills}/scientific-skills";

in
{
  # Merge all skill sources (later entries override earlier on conflict)
  home.file = anthropicSkills // kdenseSkills;
}
