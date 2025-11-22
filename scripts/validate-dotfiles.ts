#!/usr/bin/env bun

/**
 * Dotfiles Repository Validation Script (TypeScript Edition)
 *
 * A composable validation framework using a Rules API.
 * Each rule is a function that returns a validation result,
 * and rules can be easily composed together.
 */

import { execSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";

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
		execSync(`git ls-files --error-unmatch "${filepath}"`, {
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
		const output = execSync(`git check-ignore "${filepath}"`, {
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
		const output = execSync("git ls-files", {
			cwd: config.dotfilesDir,
			stdio: "pipe",
		});
		return output.toString().trim().split("\n").filter(Boolean);
	} catch {
		return [];
	}
}

function isBrokenSymlink(filepath: string): boolean {
	try {
		const stats = lstatSync(filepath);
		if (stats.isSymbolicLink()) {
			statSync(filepath);
			return false;
		}
		return false;
	} catch {
		return true;
	}
}

// ========================================================================
// TOML PARSING (Simple)
// ========================================================================

// Type for parsed TOML data
// Structure: { section: { subsection: { key: value } } } or { section: { key: value } }
interface TomlData {
	[section: string]: Record<string, string | Record<string, string>>;
}

interface DotterFile {
	source: string;
	target: string;
	group: string;
}

function parseToml(filepath: string): TomlData {
	const content = readFileSync(filepath, "utf-8");
	const lines = content.split("\n");
	// Use Record with explicit any for dynamic TOML structure
	const sections: Record<string, Record<string, unknown>> = {};
	let currentSection: string | null = null;
	let currentSubsection: string | null = null;

	for (const line of lines) {
		const trimmed = line.trim();

		if (!trimmed || trimmed.startsWith("#")) continue;

		const sectionMatch = trimmed.match(/^\[([^\]]+)\]$/);
		if (sectionMatch) {
			const parts = sectionMatch[1].split(".");
			currentSection = parts[0];
			currentSubsection = parts.length > 1 ? parts[1] : null;

			if (!sections[currentSection]) {
				sections[currentSection] = {};
			}
			if (currentSubsection && !sections[currentSection][currentSubsection]) {
				sections[currentSection][currentSubsection] = {};
			}
			continue;
		}

		const kvMatch = trimmed.match(/^"?([^"=]+)"?\s*=\s*"([^"]+)"$/);
		if (kvMatch && currentSection) {
			const [, key, value] = kvMatch;
			if (currentSubsection) {
				// Ensure nested structure exists
				const subsectionData = sections[currentSection][currentSubsection] as
					| Record<string, string>
					| undefined;
				if (!subsectionData || typeof subsectionData !== "object") {
					sections[currentSection][currentSubsection] = {};
				}
				(sections[currentSection][currentSubsection] as Record<string, string>)[
					key
				] = value;
			} else {
				sections[currentSection][key] = value;
			}
		}
	}

	// Single type assertion at the end
	return sections as TomlData;
}

function extractDotterFiles(tomlData: TomlData): DotterFile[] {
	const files: DotterFile[] = [];

	for (const [group, subsections] of Object.entries(tomlData)) {
		// Comprehensive type guard
		if (
			typeof subsections === "object" &&
			subsections !== null &&
			"files" in subsections &&
			typeof subsections.files === "object" &&
			subsections.files !== null
		) {
			const filesSection = subsections.files as Record<string, string>;
			for (const [sourceFile, targetPath] of Object.entries(filesSection)) {
				files.push({
					source: sourceFile,
					target: targetPath,
					group,
				});
			}
		}
	}

	return files;
}

// ========================================================================
// VALIDATION RULES
// ========================================================================

const Rules = {
	/**
	 * Rule: Dotter configuration files exist
	 */
	dotterConfigsExist: (config: Config): ValidationResult => {
		const globalToml = join(config.dotfilesDir, ".dotter", "global.toml");

		const issues: Issue[] = [];

		if (!existsSync(globalToml)) {
			issues.push({
				severity: "error",
				message: "Dotter global.toml not found",
				file: globalToml,
			});
		}

		return {
			ruleName: "Dotter configuration files exist",
			passed: issues.length === 0,
			issues,
		};
	},

	/**
	 * Rule: All files referenced in dotter config exist and are tracked
	 */
	dotterFilesTracked: (config: Config): ValidationResult => {
		const globalToml = join(config.dotfilesDir, ".dotter", "global.toml");
		const macosToml = join(config.dotfilesDir, ".dotter", "macos.toml");

		const parseConfig = (path: string): DotterFile[] => {
			if (!existsSync(path)) return [];
			try {
				const tomlData = parseToml(path);
				return extractDotterFiles(tomlData);
			} catch {
				return [];
			}
		};

		const globalFiles = parseConfig(globalToml);
		const macosFiles = parseConfig(macosToml);
		const allFiles = [...globalFiles, ...macosFiles];

		if (config.verbose) {
			info(`Found ${allFiles.length} files referenced in dotter configs`);
		}

		const issues: Issue[] = [];

		for (const { source, group } of allFiles) {
			const filepath = join(config.dotfilesDir, source);

			if (!existsSync(filepath)) {
				issues.push({
					severity: "error",
					message: `File missing: ${source} (from ${group})`,
					file: source,
				});
				continue;
			}

			if (!isTrackedByGit(config, source)) {
				if (isIgnoredByGit(config, source)) {
					issues.push({
						severity: "error",
						message: `File ignored by git: ${source} (from ${group})`,
						file: source,
						fixSuggestion: `Add to .gitignore: !${source}`,
					});
				} else {
					issues.push({
						severity: "warning",
						message: `File not tracked: ${source} (from ${group})`,
						file: source,
						fixSuggestion: `Run: git add ${source}`,
					});
				}
			}
		}

		return {
			ruleName: "Dotter files exist and are tracked",
			passed: issues.every((i) => i.severity === "warning"),
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
		const tomlFiles = tracked.filter((f) => f.endsWith(".toml"));
		const issues: Issue[] = [];

		for (const file of tomlFiles) {
			const path = join(config.dotfilesDir, file);
			try {
				parseToml(path);
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
			(f) => f.endsWith(".json") || f.endsWith(".jsonc"),
		);
		const issues: Issue[] = [];

		for (const file of jsonFiles) {
			const path = join(config.dotfilesDir, file);
			try {
				let content = readFileSync(path, "utf-8");

				const hasComments = /\/\/|\/\*/.test(content);

				if (file.endsWith(".jsonc") || hasComments) {
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
			0,
		);
		const warnings = totalIssues - errors;

		if (errors > 0) {
			failure(
				`Validation failed: ${totalIssues} issue(s) found (${errors} errors, ${warnings} warnings)`,
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
		process.env.DOTFILES_DIR || resolve(import.meta.dir, "..");

	const config: Config = {
		dotfilesDir,
		verbose: values.verbose || false,
		fixMode: values.fix || false,
	};

	log(`\n${Color.bold}Validating dotfiles repository...${Color.reset}\n`);

	// Define all validation rules
	const rules: Rule[] = [
		() => Rules.dotterConfigsExist(config),
		() => Rules.dotterFilesTracked(config),
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
