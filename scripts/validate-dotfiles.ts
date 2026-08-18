#!/usr/bin/env nub

/**
 * Dotfiles Repository Validation Script (TypeScript Edition)
 *
 * A composable validation framework using a Rules API.
 * Each rule is a function that returns a validation result,
 * and rules can be easily composed together.
 */

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, readFileSync, statSync } from "node:fs";
import { delimiter, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { parse as parseToml } from "smol-toml";

const moduleDir = dirname(fileURLToPath(import.meta.url));

// ========================================================================
// TYPES
// ========================================================================

type Severity = "error" | "warning" | "info";

interface Issue {
  severity: Severity;
  message: string;
  file?: string;
  fixSuggestion?: string;
}

interface ValidationResult {
  ruleName: string;
  passed: boolean;
  issues: Issue[];
}

type Rule = () => ValidationResult;

interface Config {
  dotfilesDir: string;
  verbose: boolean;
  fixMode: boolean;
}

// ========================================================================
// ANSI COLORS
// ========================================================================

const Color = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
} as const;

const Symbols = {
  success: "✓",
  failure: "✗",
  warning: "⚠",
  info: "ℹ",
} as const;

// ========================================================================
// LOGGING HELPERS
// ========================================================================

function log(message: string, color: string = Color.reset): void {
  console.log(`${color}${message}${Color.reset}`);
}

function success(message: string): void {
  log(`${Symbols.success} ${message}`, Color.green);
}

function failure(message: string): void {
  log(`${Symbols.failure} ${message}`, Color.red);
}

function warning(message: string): void {
  log(`${Symbols.warning} ${message}`, Color.yellow);
}

function info(message: string): void {
  log(`${Symbols.info} ${message}`, Color.cyan);
}

function verbose(config: Config, message: string): void {
  if (config.verbose) {
    log(`  ${message}`, Color.blue);
  }
}

// ========================================================================
// UTILITIES
// ========================================================================

function isTrackedByGit(config: Config, filepath: string): boolean {
  try {
    execFileSync("git", ["ls-files", "--error-unmatch", "--", filepath], {
      cwd: config.dotfilesDir,
      stdio: "pipe",
    });
    return true;
  } catch {
    return false;
  }
}

function isIgnoredByGit(config: Config, filepath: string): boolean {
  try {
    const output = execFileSync("git", ["check-ignore", "--", filepath], {
      cwd: config.dotfilesDir,
      stdio: "pipe",
    });
    return output.toString().trim().length > 0;
  } catch {
    return false;
  }
}

function getTrackedFiles(config: Config): string[] {
  try {
    const output = execFileSync("git", ["ls-files"], {
      cwd: config.dotfilesDir,
      stdio: "pipe",
    });
    return output.toString().trim().split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

function isBrokenSymlink(filepath: string): boolean {
  let stats;

  try {
    stats = lstatSync(filepath);
  } catch {
    return false;
  }

  if (!stats.isSymbolicLink()) {
    return false;
  }

  try {
    statSync(filepath);
    return false;
  } catch {
    return true;
  }
}

// ========================================================================
// MISE DOTFILE DECLARATIONS
// ========================================================================

interface DotfileDeclaration {
  target: string;
  source?: string;
  mode?: string;
  exclude: string[];
  problems: string[];
  configFile: string;
}

interface ParsedMiseConfig {
  dotfiles?: Record<string, unknown>;
  bootstrap?: {
    repos?: Record<string, unknown>;
  };
}

function miseConfigPaths(config: Config): string[] {
  return [
    join(config.dotfilesDir, ".config", "mise", "config.toml"),
    join(config.dotfilesDir, ".config", "mise", "config.linux.toml"),
    join(config.dotfilesDir, ".config", "mise", "config.macos.toml"),
  ];
}

function readMiseConfig(filepath: string): ParsedMiseConfig {
  return parseToml(readFileSync(filepath, "utf-8")) as ParsedMiseConfig;
}

function extractDotfileDeclarations(config: Config): DotfileDeclaration[] {
  return miseConfigPaths(config).flatMap((configFile) => {
    const parsed = readMiseConfig(configFile);
    return Object.entries(parsed.dotfiles ?? {}).map(([target, value]) => {
      if (typeof value === "string") {
        return {
          target,
          source: value,
          exclude: [],
          problems: value.length > 0 ? [] : ["source must not be empty"],
          configFile,
        };
      }

      if (typeof value === "object" && value !== null) {
        const entry = value as Record<string, unknown>;
        const problems: string[] = [];
        const source = typeof entry.source === "string" ? entry.source : undefined;
        const mode = typeof entry.mode === "string" ? entry.mode : undefined;
        const exclude = Array.isArray(entry.exclude)
          ? entry.exclude.filter((item): item is string => typeof item === "string")
          : [];

        if (!source) problems.push("source must be a non-empty string");
        if ("content" in entry) problems.push("content entries are not supported here");
        if ("mode" in entry && !mode) problems.push("mode must be a string");
        if (mode && !["symlink", "symlink-each", "copy", "template"].includes(mode)) {
          problems.push(`unsupported mode: ${mode}`);
        }
        if (
          "exclude" in entry &&
          (!Array.isArray(entry.exclude) || exclude.length !== entry.exclude.length)
        ) {
          problems.push("exclude must be a list of strings");
        }

        return {
          target,
          source,
          mode,
          exclude,
          problems,
          configFile,
        };
      }

      return {
        target,
        exclude: [],
        problems: ["declaration must be a source string or table"],
        configFile,
      };
    });
  });
}

function expandHome(filepath: string): string {
  const home = process.env.HOME;
  if (!home || (filepath !== "~" && !filepath.startsWith("~/"))) {
    return filepath;
  }
  return filepath === "~" ? home : join(home, filepath.slice(2));
}

function normalizeTarget(target: string): string {
  return resolve(expandHome(target));
}

function resolveSource(declaration: DotfileDeclaration): string | undefined {
  if (!declaration.source) return undefined;
  if (declaration.source === "~/.dotfiles") return resolveRoot(declaration);
  if (declaration.source.startsWith("~/.dotfiles/")) {
    return join(
      resolveRoot(declaration),
      declaration.source.slice("~/.dotfiles/".length)
    );
  }
  const expanded = expandHome(declaration.source);
  return resolve(
    isAbsolute(expanded) ? expanded : join(dirname(declaration.configFile), expanded)
  );
}

function resolveRoot(declaration: DotfileDeclaration): string {
  return resolve(declaration.configFile, "..", "..", "..");
}

function isWithin(parent: string, child: string): boolean {
  const pathFromParent = relative(resolve(parent), resolve(child));
  return (
    pathFromParent === "" ||
    (!pathFromParent.startsWith(`..${sep}`) && pathFromParent !== "..")
  );
}

function bootstrapRepoRoots(config: Config): string[] {
  return miseConfigPaths(config).flatMap((configFile) => {
    const parsed = readMiseConfig(configFile);
    return Object.keys(parsed.bootstrap?.repos ?? {}).map(normalizeTarget);
  });
}

function collectFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? collectFiles(path) : [path];
  });
}

// ========================================================================
// VALIDATION RULES
// ========================================================================

const Rules = {
  /**
   * Rule: Mise configuration files exist and enable platform loading
   */
  miseConfigsValid: (config: Config): ValidationResult => {
    const miserc = join(config.dotfilesDir, ".config", "miserc.toml");
    const requiredFiles = [...miseConfigPaths(config), miserc];
    const issues: Issue[] = [];

    for (const filepath of requiredFiles) {
      const repoPath = relative(config.dotfilesDir, filepath);
      if (!existsSync(filepath)) {
        issues.push({
          severity: "error",
          message: `Required mise configuration missing: ${repoPath}`,
          file: repoPath,
        });
      } else if (!isTrackedByGit(config, repoPath)) {
        issues.push({
          severity: "error",
          message: `Required mise configuration is not tracked: ${repoPath}`,
          file: repoPath,
          fixSuggestion: `Run: jj file track ${repoPath}`,
        });
      }
    }

    if (existsSync(miserc)) {
      try {
        const settings = parseToml(readFileSync(miserc, "utf-8")) as Record<
          string,
          unknown
        >;
        if (settings.auto_env !== true) {
          issues.push({
            severity: "error",
            message: ".config/miserc.toml must set auto_env = true",
            file: ".config/miserc.toml",
          });
        }
      } catch (error) {
        issues.push({
          severity: "error",
          message: `Unable to parse .config/miserc.toml: ${String(error)}`,
          file: ".config/miserc.toml",
        });
      }
    }

    return {
      ruleName: "Mise dotfile configuration is present and tracked",
      passed: issues.length === 0,
      issues,
    };
  },

  /** Rule: Declarations use the narrow, supported mise shape. */
  miseDeclarationsValid: (config: Config): ValidationResult => {
    const issues: Issue[] = [];
    try {
      for (const declaration of extractDotfileDeclarations(config)) {
        if (!(declaration.target.startsWith("~/") || isAbsolute(declaration.target))) {
          declaration.problems.push("target must be absolute or start with ~/");
        }
        for (const problem of declaration.problems) {
          issues.push({
            severity: "error",
            message: `Invalid mise dotfile declaration for ${declaration.target}: ${problem}`,
            file: relative(config.dotfilesDir, declaration.configFile),
          });
        }
      }

      for (const configFile of miseConfigPaths(config)) {
        const repos = readMiseConfig(configFile).bootstrap?.repos ?? {};
        for (const [target, value] of Object.entries(repos)) {
          const entry =
            typeof value === "object" && value !== null
              ? (value as Record<string, unknown>)
              : {};
          if (typeof entry.url !== "string" || entry.url.length === 0) {
            issues.push({
              severity: "error",
              message: `bootstrap.repos entry requires a non-empty url: ${target}`,
              file: relative(config.dotfilesDir, configFile),
            });
          }
          if ("ref" in entry && typeof entry.ref !== "string") {
            issues.push({
              severity: "error",
              message: `bootstrap.repos ref must be a string: ${target}`,
              file: relative(config.dotfilesDir, configFile),
            });
          }
        }
      }
    } catch (error) {
      issues.push({
        severity: "error",
        message: `Unable to validate mise declarations: ${String(error)}`,
      });
    }

    return {
      ruleName: "Mise declarations use supported shapes",
      passed: issues.length === 0,
      issues,
    };
  },

  /**
   * Rule: Local dotfile sources exist and are tracked
   */
  miseSourcesTracked: (config: Config): ValidationResult => {
    const issues: Issue[] = [];
    let declarations: DotfileDeclaration[] = [];

    try {
      declarations = extractDotfileDeclarations(config);
    } catch (error) {
      issues.push({
        severity: "error",
        message: `Unable to parse mise dotfile declarations: ${String(error)}`,
      });
    }

    if (config.verbose) {
      info(`Found ${declarations.length} mise dotfile declarations`);
    }

    for (const declaration of declarations) {
      const sourcePath = resolveSource(declaration);
      if (!sourcePath) {
        continue;
      }

      if (!isWithin(config.dotfilesDir, sourcePath)) continue;

      const repoPath = relative(config.dotfilesDir, sourcePath);

      if (!existsSync(sourcePath)) {
        issues.push({
          severity: "error",
          message: `Local dotfile source missing: ${repoPath}`,
          file: repoPath,
        });
        continue;
      }

      const sourceFiles = lstatSync(sourcePath).isDirectory()
        ? collectFiles(sourcePath).map((filepath) => relative(config.dotfilesDir, filepath))
        : [repoPath];

      for (const sourceFile of sourceFiles) {
        if (isTrackedByGit(config, sourceFile)) continue;
        if (isIgnoredByGit(config, sourceFile)) {
          issues.push({
            severity: "error",
            message: `Local dotfile source is ignored: ${sourceFile}`,
            file: sourceFile,
            fixSuggestion: `Add an allowlist entry for ${sourceFile}`,
          });
        } else {
          issues.push({
            severity: "error",
            message: `Local dotfile source is not tracked: ${sourceFile}`,
            file: sourceFile,
            fixSuggestion: `Run: jj file track ${sourceFile}`,
          });
        }
      }
    }

    return {
      ruleName: "Mise local dotfile sources exist and are tracked",
      passed: issues.length === 0,
      issues,
    };
  },

  /** Rule: No target is declared more than once across shared/platform config. */
  miseTargetsUnique: (config: Config): ValidationResult => {
    const issues: Issue[] = [];
    const seen = new Map<string, DotfileDeclaration>();

    try {
      for (const declaration of extractDotfileDeclarations(config)) {
        const normalized = normalizeTarget(declaration.target);
        const previous = seen.get(normalized);
        if (previous) {
          issues.push({
            severity: "error",
            message: `Duplicate mise dotfile target: ${declaration.target}`,
            file: `${relative(config.dotfilesDir, previous.configFile)} and ${relative(config.dotfilesDir, declaration.configFile)}`,
          });
        } else {
          seen.set(normalized, declaration);
        }
      }
    } catch (error) {
      issues.push({
        severity: "error",
        message: `Unable to inspect mise dotfile targets: ${String(error)}`,
      });
    }

    return {
      ruleName: "Mise dotfile targets are unique",
      passed: issues.length === 0,
      issues,
    };
  },

  /** Rule: Mutable OpenCode commands come from bootstrap-managed repositories. */
  opencodeCommandsExternal: (config: Config): ValidationResult => {
    const issues: Issue[] = [];
    const commandTarget = normalizeTarget("~/.config/opencode/command");
    const vendoredCommands = getTrackedFiles(config).filter((filepath) =>
      filepath.startsWith(".config/opencode/command/")
    );

    for (const filepath of vendoredCommands) {
      issues.push({
        severity: "error",
        message: "Mutable OpenCode commands must not be stored in this repository",
        file: filepath,
      });
    }

    try {
      const repoRoots = bootstrapRepoRoots(config);
      const declarations = extractDotfileDeclarations(config);
      for (const declaration of declarations) {
        const target = normalizeTarget(declaration.target);
        if (!isWithin(commandTarget, target)) continue;

        const source = resolveSource(declaration);
        if (!source || isWithin(config.dotfilesDir, source)) {
          issues.push({
            severity: "error",
            message: `OpenCode command target must use an external source: ${declaration.target}`,
            file: relative(config.dotfilesDir, declaration.configFile),
          });
        } else if (!repoRoots.some((repoRoot) => isWithin(repoRoot, source))) {
          issues.push({
            severity: "error",
            message: `OpenCode command source is not provided by bootstrap.repos: ${declaration.source}`,
            file: relative(config.dotfilesDir, declaration.configFile),
          });
        }
      }

      for (const parent of declarations.filter(
        (declaration) => declaration.mode === "symlink-each"
      )) {
        const parentTarget = normalizeTarget(parent.target);
        for (const child of declarations) {
          const childTarget = normalizeTarget(child.target);
          if (childTarget === parentTarget || !isWithin(parentTarget, childTarget)) continue;
          const childPath = relative(parentTarget, childTarget);
          const reserved = parent.exclude.some(
            (pattern) => childPath === pattern || childPath.startsWith(`${pattern}${sep}`)
          );
          if (!reserved) {
            issues.push({
              severity: "error",
              message: `symlink-each target ${parent.target} must exclude child declaration ${child.target}`,
              file: relative(config.dotfilesDir, parent.configFile),
            });
          }
        }
      }

      const staticOpenCode = declarations.find(
        (declaration) => normalizeTarget(declaration.target) === normalizeTarget("~/.config/opencode")
      );
      for (const required of ["command", "plugin"]) {
        if (!staticOpenCode?.exclude.includes(required)) {
          issues.push({
            severity: "error",
            message: `~/.config/opencode symlink-each must exclude ${required}`,
            file: ".config/mise/config.toml",
          });
        }
      }
    } catch (error) {
      issues.push({
        severity: "error",
        message: `Unable to validate OpenCode command ownership: ${String(error)}`,
      });
    }

    return {
      ruleName: "OpenCode commands use external bootstrap repositories",
      passed: issues.length === 0,
      issues,
    };
  },

  /** Rule: Mise can produce a machine-readable bootstrap plan. */
  miseBootstrapPlanValid: (config: Config): ValidationResult => {
    const issues: Issue[] = [];
    const result = spawnSync(
      "mise",
      ["bootstrap", "plan", "--json", "--detailed-exitcode"],
      {
        cwd: config.dotfilesDir,
        encoding: "utf-8",
        env: {
          ...process.env,
          MISE_GLOBAL_CONFIG_FILE: miseConfigPaths(config)[0],
          MISE_GLOBAL_CONFIG_ROOT: config.dotfilesDir,
          MISE_TRUSTED_CONFIG_PATHS: [
            process.env.MISE_TRUSTED_CONFIG_PATHS,
            config.dotfilesDir,
          ]
            .filter(Boolean)
            .join(delimiter),
        },
      }
    );

    if (result.status !== 0 && result.status !== 2) {
      issues.push({
        severity: "error",
        message: `mise bootstrap plan --json failed: ${result.stderr.trim()}`,
      });
    } else {
      try {
        JSON.parse(result.stdout);
      } catch (error) {
        issues.push({
          severity: "error",
          message: `mise bootstrap plan --json returned invalid JSON: ${String(error)}`,
        });
      }
    }

    return {
      ruleName: "Mise bootstrap plan succeeds",
      passed: issues.length === 0,
      issues,
    };
  },

  /**
   * Rule: No broken symlinks
   */
  noBrokenSymlinks: (config: Config): ValidationResult => {
    const tracked = getTrackedFiles(config);
    const issues: Issue[] = [];

    for (const file of tracked) {
      const path = join(config.dotfilesDir, file);
      if (isBrokenSymlink(path)) {
        issues.push({
          severity: "error",
          message: `Broken symlink: ${file}`,
          file,
        });
      }
    }

    return {
      ruleName: "No broken symlinks",
      passed: issues.length === 0,
      issues,
    };
  },

  /**
   * Rule: TOML files are valid
   */
  tomlFilesValid: (config: Config): ValidationResult => {
    const tracked = getTrackedFiles(config);
    const tomlFiles = tracked.filter(
      (f) => f.endsWith(".toml") && existsSync(join(config.dotfilesDir, f))
    );
    const issues: Issue[] = [];

    for (const file of tomlFiles) {
      const path = join(config.dotfilesDir, file);
      try {
        parseToml(readFileSync(path, "utf-8"));
      } catch {
        issues.push({
          severity: "error",
          message: `Invalid TOML syntax: ${file}`,
          file,
        });
      }
    }

    return {
      ruleName: `All ${tomlFiles.length} TOML files are valid`,
      passed: issues.length === 0,
      issues,
    };
  },

  /**
   * Rule: JSON files are valid (supports JSONC)
   */
  jsonFilesValid: (config: Config): ValidationResult => {
    const tracked = getTrackedFiles(config);
    const jsonFiles = tracked.filter(
      (f) =>
        (f.endsWith(".json") || f.endsWith(".jsonc")) &&
        existsSync(join(config.dotfilesDir, f))
    );
    const issues: Issue[] = [];

    for (const file of jsonFiles) {
      const path = join(config.dotfilesDir, file);
      try {
        let content = readFileSync(path, "utf-8");

        const supportsComments =
          file.endsWith(".jsonc") || file.startsWith(".config/zed/");

        if (supportsComments) {
          const lines = content.split("\n");
          const filtered = lines.filter((line) => {
            const trimmed = line.trim();
            return !trimmed.startsWith("//");
          });
          content = filtered.join("\n");

          content = content.replace(/\s*\/\/[^\n]*$/gm, "");
          content = content.replace(/\/\*[\s\S]*?\*\//g, "");
          content = content.replace(/,(\s*[}\]])/g, "$1");
        }

        JSON.parse(content);
      } catch {
        if (!file.endsWith(".jsonc")) {
          issues.push({
            severity: "error",
            message: `Invalid JSON syntax: ${file}`,
            file,
          });
        }
      }
    }

    return {
      ruleName: `All ${jsonFiles.length} JSON files are valid`,
      passed: issues.length === 0,
      issues,
    };
  },
};

// ========================================================================
// RULE COMPOSITION & EXECUTION
// ========================================================================

class Validator {
  private config: Config;

  constructor(config: Config) {
    this.config = config;
  }

  /**
   * Run a single rule
   */
  runRule(rule: Rule): ValidationResult {
    if (this.config.verbose) {
      verbose(this.config, "Checking...");
    }
    return rule();
  }

  /**
   * Run multiple rules and collect results
   */
  runRules(rules: Rule[]): ValidationResult[] {
    return rules.map((rule) => this.runRule(rule));
  }

  /**
   * Print a validation result
   */
  printResult(result: ValidationResult): void {
    // Use helper functions for clean, semantic logging
    if (result.passed) {
      success(result.ruleName);
    } else {
      failure(result.ruleName);
    }

    for (const issue of result.issues) {
      const fileStr = issue.file ? ` (${issue.file})` : "";
      const message = `  ${issue.message}${fileStr}`;

      // Use appropriate helper based on severity
      if (issue.severity === "error") {
        failure(message);
      } else if (issue.severity === "warning") {
        warning(message);
      } else {
        info(message);
      }

      if (issue.fixSuggestion) {
        info(`    ${issue.fixSuggestion}`);
      }
    }
  }

  /**
   * Summarize results and return exit code
   */
  summarize(results: ValidationResult[]): number {
    log(`\n${Color.bold}${"=".repeat(60)}${Color.reset}`);

    const totalIssues = results.reduce((acc, r) => acc + r.issues.length, 0);
    const errors = results.reduce(
      (acc, r) => acc + r.issues.filter((i) => i.severity === "error").length,
      0
    );
    const warnings = totalIssues - errors;

    if (errors > 0) {
      failure(
        `Validation failed: ${totalIssues} issue(s) found (${errors} errors, ${warnings} warnings)`
      );

      if (this.config.fixMode) {
        log(`\n${Color.bold}Fix suggestions:${Color.reset}\n`);

        const ignoredFiles = results
          .flatMap((r) => r.issues)
          .filter((i) => i.fixSuggestion?.includes(".gitignore"))
          .map((i) => i.file)
          .filter(Boolean) as string[];

        if (ignoredFiles.length > 0) {
          info("Add these lines to .gitignore:");
          for (const file of ignoredFiles) {
            success(`  !${file}`);
          }
          log("");
        }

        const untrackedFiles = results
          .flatMap((r) => r.issues)
          .filter((i) => i.fixSuggestion?.includes("git add"))
          .map((i) => i.file)
          .filter(Boolean) as string[];

        if (untrackedFiles.length > 0) {
          info("Run this command to track files:");
          success(`  git add ${untrackedFiles.join(" ")}`);
          log("");
        }
      }

      return 1;
    } else if (warnings > 0) {
      warning(`Validation completed with ${warnings} warning(s)`);
      return 0;
    } else {
      success("All validations passed!\n");
      return 0;
    }
  }
}

// ========================================================================
// MAIN
// ========================================================================

async function main() {
  const { values } = parseArgs({
    options: {
      fix: { type: "boolean", short: "f", default: false },
      verbose: { type: "boolean", short: "v", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
  });

  if (values.help) {
    console.log(`
Usage: validate-dotfiles.ts [options]

Options:
  -f, --fix       Show fix suggestions
  -v, --verbose   Show detailed output
  -h, --help      Show this help message

Exit codes:
  0 - All validations passed
  1 - Validation failures found
  2 - Critical error
`);
    process.exit(0);
  }

  const dotfilesDir =
    process.env.DOTFILES_DIR || resolve(moduleDir, "..");

  const config: Config = {
    dotfilesDir,
    verbose: values.verbose || false,
    fixMode: values.fix || false,
  };

  log(`\n${Color.bold}Validating dotfiles repository...${Color.reset}\n`);

  // Define all validation rules
  const rules: Rule[] = [
    () => Rules.miseConfigsValid(config),
    () => Rules.miseDeclarationsValid(config),
    () => Rules.miseSourcesTracked(config),
    () => Rules.miseTargetsUnique(config),
    () => Rules.opencodeCommandsExternal(config),
    () => Rules.miseBootstrapPlanValid(config),
    () => Rules.noBrokenSymlinks(config),
    () => Rules.tomlFilesValid(config),
    () => Rules.jsonFilesValid(config),
  ];

  // Create validator and run rules
  const validator = new Validator(config);
  const results = validator.runRules(rules);

  // Print each result
  for (const result of results) {
    validator.printResult(result);
  }

  // Summarize and exit
  const exitCode = validator.summarize(results);
  process.exit(exitCode);
}

main();
