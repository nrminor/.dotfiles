#!/usr/bin/env rust-script
//! Dotfiles Repository Validation Script (Rust Edition)
//!
//! A composable validation framework using a Rules API.
//! Each rule is a function that returns a validation result,
//! and rules can be easily composed together.
//!
//! ```cargo
//! [dependencies]
//! anyhow = "1.0"
//! clap = { version = "4.5", features = ["derive"] }
//! toml = "0.8"
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! ```

use anyhow::{Context, Result};
use clap::Parser;

use std::{
    collections::HashSet,
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

// ============================================================================
// TYPES
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Severity {
    Error,
    Warning,
}

#[derive(Debug, Clone)]
struct Issue {
    severity: Severity,
    message: String,
    file: Option<String>,
    fix_suggestion: Option<String>,
}

impl Issue {
    fn new(severity: Severity, message: impl Into<String>) -> Self {
        Self {
            severity,
            message: message.into(),
            file: None,
            fix_suggestion: None,
        }
    }

    fn with_file(mut self, file: impl Into<String>) -> Self {
        self.file = Some(file.into());
        self
    }

    fn with_fix(mut self, fix: impl Into<String>) -> Self {
        self.fix_suggestion = Some(fix.into());
        self
    }
}

#[derive(Debug)]
struct ValidationResult {
    rule_name: String,
    passed: bool,
    issues: Vec<Issue>,
}

impl ValidationResult {
    fn new(rule_name: impl Into<String>, passed: bool, issues: Vec<Issue>) -> Self {
        Self {
            rule_name: rule_name.into(),
            passed,
            issues,
        }
    }
}

#[derive(Debug, Clone)]
struct Config {
    dotfiles_dir: PathBuf,
    verbose: bool,
    fix_mode: bool,
}

// ============================================================================
// ANSI COLORS
// ============================================================================

struct Color;

impl Color {
    const RESET: &'static str = "\x1b[0m";
    const BOLD: &'static str = "\x1b[1m";
    const RED: &'static str = "\x1b[31m";
    const GREEN: &'static str = "\x1b[32m";
    const YELLOW: &'static str = "\x1b[33m";
    const BLUE: &'static str = "\x1b[34m";
    const CYAN: &'static str = "\x1b[36m";
}

struct Symbols;

impl Symbols {
    const SUCCESS: &'static str = "✓";
    const FAILURE: &'static str = "✗";
    const WARNING: &'static str = "⚠";
    const INFO: &'static str = "ℹ";
}

// ============================================================================
// LOGGING HELPERS
// ============================================================================

fn log(message: &str, color: &str) {
    println!("{}{}{}", color, message, Color::RESET);
}

fn success(message: &str) {
    log(&format!("{} {}", Symbols::SUCCESS, message), Color::GREEN);
}

fn failure(message: &str) {
    log(&format!("{} {}", Symbols::FAILURE, message), Color::RED);
}

fn warning(message: &str) {
    log(&format!("{} {}", Symbols::WARNING, message), Color::YELLOW);
}

fn info(message: &str) {
    log(&format!("{} {}", Symbols::INFO, message), Color::CYAN);
}

fn verbose(config: &Config, message: &str) {
    if config.verbose {
        println!("{}  {}{}", Color::BLUE, message, Color::RESET);
    }
}

// ============================================================================
// UTILITIES
// ============================================================================

fn is_tracked_by_git(config: &Config, filepath: &str) -> bool {
    Command::new("git")
        .args(["ls-files", "--error-unmatch", filepath])
        .current_dir(&config.dotfiles_dir)
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn is_ignored_by_git(config: &Config, filepath: &str) -> bool {
    Command::new("git")
        .args(["check-ignore", filepath])
        .current_dir(&config.dotfiles_dir)
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn get_tracked_files(config: &Config) -> Result<Vec<String>> {
    let output = Command::new("git")
        .args(["ls-files"])
        .current_dir(&config.dotfiles_dir)
        .output()
        .context("Failed to run git ls-files")?;

    if !output.status.success() {
        return Ok(Vec::new());
    }

    let files = String::from_utf8(output.stdout)
        .context("Invalid UTF-8 in git output")?
        .lines()
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect();

    Ok(files)
}

fn is_broken_symlink(path: &Path) -> bool {
    if let Ok(metadata) = std::fs::symlink_metadata(path) {
        if metadata.file_type().is_symlink() {
            return std::fs::metadata(path).is_err();
        }
    }
    false
}

// ============================================================================
// VALIDATION RULES
// ============================================================================

fn dotter_configs_exist(config: &Config) -> ValidationResult {
    let global_toml = config.dotfiles_dir.join(".dotter/global.toml");
    let mut issues = Vec::new();

    if !global_toml.exists() {
        issues.push(
            Issue::new(Severity::Error, "Dotter global.toml not found")
                .with_file(global_toml.display().to_string()),
        );
    }

    ValidationResult::new(
        "Dotter configuration files exist",
        issues.is_empty(),
        issues,
    )
}

fn dotter_files_tracked(config: &Config) -> Result<ValidationResult> {
    let global_toml = config.dotfiles_dir.join(".dotter/global.toml");
    let macos_toml = config.dotfiles_dir.join(".dotter/macos.toml");

    let mut all_files = HashSet::new();

    // Parse TOML files to extract referenced files
    for toml_path in [global_toml, macos_toml] {
        if !toml_path.exists() {
            continue;
        }

        let content = fs::read_to_string(&toml_path)
            .with_context(|| format!("Failed to read {}", toml_path.display()))?;

        let doc: toml::Value = toml::from_str(&content)
            .with_context(|| format!("Failed to parse {}", toml_path.display()))?;

        if let Some(table) = doc.as_table() {
            for (_, value) in table {
                if let Some(files) = value.get("files") {
                    if let Some(files_table) = files.as_table() {
                        for (source, _) in files_table {
                            all_files.insert(source.clone());
                        }
                    }
                }
            }
        }
    }

    if config.verbose {
        info(&format!(
            "Found {} files referenced in dotter configs",
            all_files.len()
        ));
    }

    let mut issues = Vec::new();

    for source in &all_files {
        let filepath = config.dotfiles_dir.join(source);

        if !filepath.exists() {
            issues.push(
                Issue::new(Severity::Error, format!("File missing: {}", source))
                    .with_file(source.clone()),
            );
            continue;
        }

        if !is_tracked_by_git(config, source) {
            if is_ignored_by_git(config, source) {
                issues.push(
                    Issue::new(Severity::Error, format!("File ignored by git: {}", source))
                        .with_file(source.clone())
                        .with_fix(format!("Add to .gitignore: !{}", source)),
                );
            } else {
                issues.push(
                    Issue::new(Severity::Warning, format!("File not tracked: {}", source))
                        .with_file(source.clone())
                        .with_fix(format!("Run: git add {}", source)),
                );
            }
        }
    }

    let passed = issues.iter().all(|i| i.severity == Severity::Warning);
    Ok(ValidationResult::new(
        "Dotter files exist and are tracked",
        passed,
        issues,
    ))
}

fn no_broken_symlinks(config: &Config) -> Result<ValidationResult> {
    let tracked = get_tracked_files(config)?;
    let mut issues = Vec::new();

    for file in tracked {
        let path = config.dotfiles_dir.join(&file);
        if is_broken_symlink(&path) {
            issues.push(
                Issue::new(Severity::Error, format!("Broken symlink: {}", file)).with_file(file),
            );
        }
    }

    Ok(ValidationResult::new(
        "No broken symlinks",
        issues.is_empty(),
        issues,
    ))
}

fn toml_files_valid(config: &Config) -> Result<ValidationResult> {
    let tracked = get_tracked_files(config)?;
    let toml_files: Vec<_> = tracked.iter().filter(|f| f.ends_with(".toml")).collect();
    let mut issues = Vec::new();

    for file in &toml_files {
        let path = config.dotfiles_dir.join(file);
        if let Ok(content) = fs::read_to_string(&path) {
            if toml::from_str::<toml::Value>(&content).is_err() {
                issues.push(
                    Issue::new(Severity::Error, format!("Invalid TOML syntax: {}", file))
                        .with_file((*file).clone()),
                );
            }
        }
    }

    Ok(ValidationResult::new(
        format!("All {} TOML files are valid", toml_files.len()),
        issues.is_empty(),
        issues,
    ))
}

fn json_files_valid(config: &Config) -> Result<ValidationResult> {
    let tracked = get_tracked_files(config)?;
    let json_files: Vec<_> = tracked
        .iter()
        .filter(|f| f.ends_with(".json") || f.ends_with(".jsonc"))
        .collect();
    let mut issues = Vec::new();

    for file in &json_files {
        // Skip JSONC files and Zed config files (which allow comments)
        if file.ends_with(".jsonc") || file.contains("/.config/zed/") {
            continue;
        }

        let path = config.dotfiles_dir.join(file);
        if let Ok(content) = fs::read_to_string(&path) {
            if serde_json::from_str::<serde_json::Value>(&content).is_err() {
                issues.push(
                    Issue::new(Severity::Error, format!("Invalid JSON syntax: {}", file))
                        .with_file((*file).clone()),
                );
            }
        }
    }

    Ok(ValidationResult::new(
        format!("All {} JSON files are valid", json_files.len()),
        issues.is_empty(),
        issues,
    ))
}

// ============================================================================
// VALIDATOR
// ============================================================================

struct Validator {
    config: Config,
}

impl Validator {
    fn new(config: Config) -> Self {
        Self { config }
    }

    fn run_rules(&self) -> Result<Vec<ValidationResult>> {
        let rules: Vec<fn(&Config) -> Result<ValidationResult>> = vec![
            |c| Ok(dotter_configs_exist(c)),
            |c| dotter_files_tracked(c),
            |c| no_broken_symlinks(c),
            |c| toml_files_valid(c),
            |c| json_files_valid(c),
        ];

        let mut results = Vec::new();
        for rule in rules {
            if self.config.verbose {
                verbose(&self.config, "Checking...");
            }
            results.push(rule(&self.config)?);
        }

        Ok(results)
    }

    fn print_result(&self, result: &ValidationResult) {
        if result.passed {
            success(&result.rule_name);
        } else {
            failure(&result.rule_name);
        }

        for issue in &result.issues {
            let file_str = issue
                .file
                .as_ref()
                .map(|f| format!(" ({})", f))
                .unwrap_or_default();
            let message = format!("  {}{}", issue.message, file_str);

            match issue.severity {
                Severity::Error => failure(&message),
                Severity::Warning => warning(&message),
            }

            if let Some(fix) = &issue.fix_suggestion {
                info(&format!("    {}", fix));
            }
        }
    }

    fn summarize(&self, results: &[ValidationResult]) -> i32 {
        println!("\n{}{}{}", Color::BOLD, "=".repeat(60), Color::RESET);

        let total_issues: usize = results.iter().map(|r| r.issues.len()).sum();
        let errors: usize = results
            .iter()
            .flat_map(|r| &r.issues)
            .filter(|i| i.severity == Severity::Error)
            .count();
        let warnings = total_issues - errors;

        if errors > 0 {
            failure(&format!(
                "Validation failed: {} issue(s) found ({} errors, {} warnings)",
                total_issues, errors, warnings
            ));

            if self.config.fix_mode {
                println!("\n{}Fix suggestions:{}\n", Color::BOLD, Color::RESET);

                let ignored_files: Vec<_> = results
                    .iter()
                    .flat_map(|r| &r.issues)
                    .filter(|i| {
                        i.fix_suggestion
                            .as_ref()
                            .map(|s| s.contains(".gitignore"))
                            .unwrap_or(false)
                    })
                    .filter_map(|i| i.file.as_ref())
                    .collect();

                if !ignored_files.is_empty() {
                    info("Add these lines to .gitignore:");
                    for file in ignored_files {
                        success(&format!("  !{}", file));
                    }
                    println!();
                }

                let untracked_files: Vec<_> = results
                    .iter()
                    .flat_map(|r| &r.issues)
                    .filter(|i| {
                        i.fix_suggestion
                            .as_ref()
                            .map(|s| s.contains("git add"))
                            .unwrap_or(false)
                    })
                    .filter_map(|i| i.file.as_ref())
                    .collect();

                if !untracked_files.is_empty() {
                    info("Run this command to track files:");
                    let files_str: Vec<String> =
                        untracked_files.iter().map(|s| s.to_string()).collect();
                    success(&format!("  git add {}", files_str.join(" ")));
                    println!();
                }
            }

            1
        } else if warnings > 0 {
            warning(&format!(
                "Validation completed with {} warning(s)",
                warnings
            ));
            0
        } else {
            success("All validations passed!\n");
            0
        }
    }
}

// ============================================================================
// CLI
// ============================================================================

#[derive(Parser)]
#[command(name = "validate-dotfiles")]
#[command(about = "Validate dotfiles repository structure and configuration")]
struct Cli {
    /// Show fix suggestions
    #[arg(short, long)]
    fix: bool,

    /// Show detailed output
    #[arg(short, long)]
    verbose: bool,
}

// ============================================================================
// MAIN
// ============================================================================

fn main() -> Result<()> {
    let cli = Cli::parse();

    let dotfiles_dir = env::var("DOTFILES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::current_dir().expect("Failed to get current directory"));

    let config = Config {
        dotfiles_dir,
        verbose: cli.verbose,
        fix_mode: cli.fix,
    };

    println!(
        "\n{}Validating dotfiles repository...{}\n",
        Color::BOLD,
        Color::RESET
    );

    let validator = Validator::new(config);
    let results = validator.run_rules()?;

    for result in &results {
        validator.print_result(result);
    }

    let exit_code = validator.summarize(&results);
    std::process::exit(exit_code);
}
