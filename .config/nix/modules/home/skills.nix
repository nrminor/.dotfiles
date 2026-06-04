# Claude/OpenCode skills from multiple sources
#
# Home Manager owns static AI assets:
#   - ~/.claude/skills/*
#   - ~/.config/opencode/skills/*
#   - ~/.config/opencode/command/*
#
# Dotter owns frequently edited OpenCode config and agents, but not skills or
# commands. Keep this module intentionally boring: Nix declares source -> target
# links, while richer ownership/invariant checks belong in validation scripts.
#
# Upstreams:
#   - anthropics/skills (official Anthropic skills)
#   - mattpocock/skills (curated engineering/productivity skills)
#   - pbakaus/impeccable (OpenCode frontend design skill)
#   - uditgoenka/autoresearch (OpenCode autoresearch skill and commands)
#
# K-Dense scientific skills were previously managed here via a flake input:
#
#   kdense-scientific-skills = {
#     url = "github:K-Dense-AI/claude-scientific-skills";
#     flake = false;
#   };
#
# To reintroduce them, add that input back to .config/nix/flake.nix and add an
# explicit set of Home Manager mappings below, or a small wholesale helper if the
# intended policy is to install all K-Dense skills.
#
# Do not silently merge it with Anthropic skills; that upstream has historically
# overlapped with Anthropic skills such as docx, pdf, pptx, and xlsx.
{ inputs, lib, ... }:

let
  link = source: { inherit source; };

  # .config/ from the repository root, relative to this file.
  configDir = ../../..;

  anthropicSkills =
    let
      root = "${inputs.anthropic-skills}/skills";
      contents = builtins.readDir root;
      skillDirs = lib.filterAttrs (_: type: type == "directory") contents;
    in
    lib.mapAttrs' (
      name: _: lib.nameValuePair ".claude/skills/${name}" (link "${root}/${name}")
    ) skillDirs;

  explicitFiles = {
    # Matt Pocock skills. These intentionally replace local vendored copies.
    ".claude/skills/grill-me" = link "${inputs.matt-pocock-skills}/skills/productivity/grill-me";
    ".claude/skills/handoff" = link "${inputs.matt-pocock-skills}/skills/productivity/handoff";
    ".claude/skills/tdd" = link "${inputs.matt-pocock-skills}/skills/engineering/tdd";
    ".claude/skills/grill-with-docs" =
      link "${inputs.matt-pocock-skills}/skills/engineering/grill-with-docs";
    ".claude/skills/improve-codebase-architecture" =
      link "${inputs.matt-pocock-skills}/skills/engineering/improve-codebase-architecture";

    # Local personal Claude skills.
    ".claude/skills/allocations" = link "${configDir}/.claude/skills/allocations";
    ".claude/skills/back-of-envelope" = link "${configDir}/.claude/skills/back-of-envelope";
    ".claude/skills/codebase-searcher" = link "${configDir}/.claude/skills/codebase-searcher";
    ".claude/skills/design-an-interface" = link "${configDir}/.claude/skills/design-an-interface";
    ".claude/skills/design-engineering" = link "${configDir}/.claude/skills/design-engineering";
    ".claude/skills/duckdb" = link "${configDir}/.claude/skills/duckdb";
    ".claude/skills/effect-ts" = link "${configDir}/.claude/skills/effect-ts";
    ".claude/skills/jj" = link "${configDir}/.claude/skills/jj";
    ".claude/skills/local-ci" = link "${configDir}/.claude/skills/local-ci";
    ".claude/skills/logging" = link "${configDir}/.claude/skills/logging";
    ".claude/skills/prd" = link "${configDir}/.claude/skills/prd";
    ".claude/skills/ralph" = link "${configDir}/.claude/skills/ralph";
    ".claude/skills/request-refactor-plan" = link "${configDir}/.claude/skills/request-refactor-plan";
    ".claude/skills/self-doubt" = link "${configDir}/.claude/skills/self-doubt";
    ".claude/skills/tigerstyle" = link "${configDir}/.claude/skills/tigerstyle";
    ".claude/skills/typst" = link "${configDir}/.claude/skills/typst";
    ".claude/skills/ubiquitous-language" = link "${configDir}/.claude/skills/ubiquitous-language";

    # OpenCode-specific skills.
    ".config/opencode/skills/impeccable" = link "${inputs.impeccable}/.opencode/skills/impeccable";
    ".config/opencode/skills/autoresearch" =
      link "${inputs.autoresearch}/.opencode/skills/autoresearch";

    # Local OpenCode commands.
    ".config/opencode/command/complete-next-task.md" =
      link "${configDir}/opencode/command/complete-next-task.md";
    ".config/opencode/command/describe-commit.md" =
      link "${configDir}/opencode/command/describe-commit.md";
    ".config/opencode/command/index-knowledge.md" =
      link "${configDir}/opencode/command/index-knowledge.md";
    ".config/opencode/command/query.md" = link "${configDir}/opencode/command/query.md";
    ".config/opencode/command/run-multiphase-review.md" =
      link "${configDir}/opencode/command/run-multiphase-review.md";
    ".config/opencode/command/tidy-commit-graph.md" =
      link "${configDir}/opencode/command/tidy-commit-graph.md";
    ".config/opencode/command/update-working-document.md" =
      link "${configDir}/opencode/command/update-working-document.md";

    # Autoresearch OpenCode commands.
    ".config/opencode/command/autoresearch.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch.md";
    ".config/opencode/command/autoresearch_debug.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_debug.md";
    ".config/opencode/command/autoresearch_evals.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_evals.md";
    ".config/opencode/command/autoresearch_fix.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_fix.md";
    ".config/opencode/command/autoresearch_improve.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_improve.md";
    ".config/opencode/command/autoresearch_learn.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_learn.md";
    ".config/opencode/command/autoresearch_plan.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_plan.md";
    ".config/opencode/command/autoresearch_predict.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_predict.md";
    ".config/opencode/command/autoresearch_probe.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_probe.md";
    ".config/opencode/command/autoresearch_reason.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_reason.md";
    ".config/opencode/command/autoresearch_scenario.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_scenario.md";
    ".config/opencode/command/autoresearch_security.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_security.md";
    ".config/opencode/command/autoresearch_ship.md" =
      link "${inputs.autoresearch}/.opencode/commands/autoresearch_ship.md";
  };
in
{
  home.file = lib.mkMerge [
    anthropicSkills
    explicitFiles
  ];
}
