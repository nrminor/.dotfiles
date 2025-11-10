#!/usr/bin/env ocaml

#directory "+unix"

#load "unix.cma"

(** * Dotfiles Repository Validation Script (OCaml Edition) * * A composable
    validation framework using a Rules API. * Each rule is a function that
    returns a validation result, * and rules can be easily composed together. *)

(* ========================================================================= *)
(* TYPES *)
(* ========================================================================= *)

type severity = Error | Warning | Info

type issue = {
  severity : severity;
  message : string;
  file : string option;
  fix_suggestion : string option;
}

type validation_result = {
  rule_name : string;
  passed : bool;
  issues : issue list;
}

type rule = unit -> validation_result
type config = { dotfiles_dir : string; verbose : bool; fix_mode : bool }

(* ========================================================================= *)
(* ANSI COLORS *)
(* ========================================================================= *)

module Color = struct
  let reset = "\x1b[0m"
  let bold = "\x1b[1m"
  let red = "\x1b[31m"
  let green = "\x1b[32m"
  let yellow = "\x1b[33m"
  let blue = "\x1b[34m"
  let cyan = "\x1b[36m"
  let success = green ^ "✓" ^ reset
  let failure = red ^ "✗" ^ reset
  let warning = yellow ^ "⚠" ^ reset
  let info = cyan ^ "ℹ" ^ reset
end

(* ========================================================================= *)
(* UTILITIES *)
(* ========================================================================= *)

let read_file path =
  try
    let ic = open_in path in
    let rec read_lines acc =
      try
        let line = input_line ic in
        read_lines (line :: acc)
      with End_of_file ->
        close_in ic;
        List.rev acc
    in
    Some (read_lines [])
  with _ -> None

let file_exists path =
  try
    let _ = Unix.stat path in
    true
  with Unix.Unix_error _ -> false

let read_command cmd =
  try
    let ic = Unix.open_process_in cmd in
    let rec read_lines acc =
      try
        let line = input_line ic in
        read_lines (line :: acc)
      with End_of_file ->
        let _ = Unix.close_process_in ic in
        List.rev acc
    in
    read_lines []
  with _ -> []

let is_tracked_by_git config path =
  let cmd =
    Printf.sprintf "cd %s && git ls-files --error-unmatch %s 2>/dev/null"
      config.dotfiles_dir path
  in
  match read_command cmd with [] -> false | _ -> true

let is_ignored_by_git config path =
  let cmd =
    Printf.sprintf "cd %s && git check-ignore %s 2>/dev/null"
      config.dotfiles_dir path
  in
  match read_command cmd with [] -> false | _ -> true

let get_tracked_files config =
  let cmd = Printf.sprintf "cd %s && git ls-files" config.dotfiles_dir in
  read_command cmd

(* ========================================================================= *)
(* TOML PARSING (Simple) *)
(* ========================================================================= *)

module TomlParser = struct
  type value = String of string | Section of (string * value) list

  let parse_line line =
    let trimmed = String.trim line in
    if trimmed = "" || String.get trimmed 0 = '#' then None
    else if String.get trimmed 0 = '[' then
      (* Section header *)
      let len = String.length trimmed in
      let section_name = String.sub trimmed 1 (len - 2) in
      Some (`Section section_name)
    else
      (* Key-value pair *)
      try
        let eq_pos = String.index trimmed '=' in
        let key = String.trim (String.sub trimmed 0 eq_pos) in
        let value =
          String.trim
            (String.sub trimmed (eq_pos + 1)
               (String.length trimmed - eq_pos - 1))
        in
        (* Remove quotes from key and value *)
        let clean_str s =
          let s = String.trim s in
          if
            String.length s >= 2
            && String.get s 0 = '"'
            && String.get s (String.length s - 1) = '"'
          then String.sub s 1 (String.length s - 2)
          else s
        in
        Some (`KeyValue (clean_str key, clean_str value))
      with Not_found -> None

  let parse_toml lines =
    let rec parse_sections acc current_section lines =
      match lines with
      | [] -> acc
      | line :: rest -> (
          match parse_line line with
          | None -> parse_sections acc current_section rest
          | Some (`Section name) -> parse_sections acc (Some name) rest
          | Some (`KeyValue (k, v)) -> (
              match current_section with
              | None -> parse_sections acc None rest
              | Some section ->
                  let new_acc = (section, k, v) :: acc in
                  parse_sections new_acc current_section rest))
    in
    parse_sections [] None lines

  let extract_files toml_data =
    List.filter_map
      (fun (section, key, value) ->
        if
          String.contains section '.'
          && (String.sub section (String.length section - 6) 6 = ".files"
             || String.sub section (String.length section - 5) 5 = ".files")
        then
          let group = String.sub section 0 (String.index section '.') in
          Some (key, value, group)
        else None)
      toml_data
end

(* ========================================================================= *)
(* VALIDATION RULES *)
(* ========================================================================= *)

module Rules = struct
  (* Rule: Dotter config files exist *)
  let dotter_configs_exist config : validation_result =
    let global_toml =
      Filename.concat
        (Filename.concat config.dotfiles_dir ".dotter")
        "global.toml"
    in

    let issues = [] in
    let issues =
      if not (file_exists global_toml) then
        {
          severity = Error;
          message = "Dotter global.toml not found";
          file = Some global_toml;
          fix_suggestion = None;
        }
        :: issues
      else issues
    in

    {
      rule_name = "Dotter configuration files exist";
      passed = issues = [];
      issues;
    }

  (* Rule: All files referenced in dotter config exist and are tracked *)
  let dotter_files_tracked config : validation_result =
    let global_toml =
      Filename.concat
        (Filename.concat config.dotfiles_dir ".dotter")
        "global.toml"
    in
    let macos_toml =
      Filename.concat
        (Filename.concat config.dotfiles_dir ".dotter")
        "macos.toml"
    in

    let parse_config path =
      match read_file path with
      | None -> []
      | Some lines ->
          let toml_data = TomlParser.parse_toml lines in
          TomlParser.extract_files toml_data
    in

    let global_files =
      if file_exists global_toml then parse_config global_toml else []
    in
    let macos_files =
      if file_exists macos_toml then parse_config macos_toml else []
    in
    let all_files = global_files @ macos_files in

    if config.verbose then
      Printf.printf "%sℹ Found %d files referenced in dotter configs%s\n"
        Color.cyan (List.length all_files) Color.reset;

    let check_file issues (source, _, group) =
      let filepath = Filename.concat config.dotfiles_dir source in
      if not (file_exists filepath) then
        {
          severity = Error;
          message = Printf.sprintf "File missing: %s (from %s)" source group;
          file = Some source;
          fix_suggestion = None;
        }
        :: issues
      else if not (is_tracked_by_git config source) then
        if is_ignored_by_git config source then
          {
            severity = Error;
            message =
              Printf.sprintf "File ignored by git: %s (from %s)" source group;
            file = Some source;
            fix_suggestion =
              Some (Printf.sprintf "Add to .gitignore: !%s" source);
          }
          :: issues
        else
          {
            severity = Warning;
            message =
              Printf.sprintf "File not tracked: %s (from %s)" source group;
            file = Some source;
            fix_suggestion = Some (Printf.sprintf "Run: git add %s" source);
          }
          :: issues
      else issues
    in

    let issues = List.fold_left check_file [] all_files in

    {
      rule_name = "Dotter files exist and are tracked";
      passed = List.for_all (fun i -> i.severity = Warning) issues;
      issues = List.rev issues;
    }

  (* Rule: No broken symlinks *)
  let no_broken_symlinks config : validation_result =
    let tracked = get_tracked_files config in
    let check_symlink file =
      let path = Filename.concat config.dotfiles_dir file in
      try
        let stats = Unix.lstat path in
        if stats.Unix.st_kind = Unix.S_LNK then
          try
            let _ = Unix.stat path in
            None
          with Unix.Unix_error _ ->
            Some
              {
                severity = Error;
                message = Printf.sprintf "Broken symlink: %s" file;
                file = Some file;
                fix_suggestion = None;
              }
        else None
      with Unix.Unix_error _ -> None
    in
    let issues = List.filter_map check_symlink tracked in
    { rule_name = "No broken symlinks"; passed = issues = []; issues }

  (* Rule: TOML files are valid *)
  let toml_files_valid config : validation_result =
    let tracked = get_tracked_files config in
    let toml_files =
      List.filter (fun f -> Filename.check_suffix f ".toml") tracked
    in

    let check_toml file =
      let path = Filename.concat config.dotfiles_dir file in
      match read_file path with
      | None ->
          Some
            {
              severity = Error;
              message = Printf.sprintf "Cannot read TOML file: %s" file;
              file = Some file;
              fix_suggestion = None;
            }
      | Some lines -> (
          (* Basic validation - just try to parse *)
          try
            let _ = TomlParser.parse_toml lines in
            None
          with e ->
            Some
              {
                severity = Error;
                message = Printf.sprintf "Invalid TOML syntax: %s" file;
                file = Some file;
                fix_suggestion = None;
              })
    in

    let issues = List.filter_map check_toml toml_files in
    {
      rule_name =
        Printf.sprintf "All %d TOML files are valid" (List.length toml_files);
      passed = issues = [];
      issues;
    }

end

(* ========================================================================= *)
(* RULE COMPOSITION *)
(* ========================================================================= *)

module Validator = struct
  let run_rule config rule =
    if config.verbose then
      Printf.printf "%sChecking: %s%s\n" Color.blue "..." Color.reset;
    rule ()

  let run_rules config rules = List.map (fun rule -> run_rule config rule) rules

  let print_result result =
    let status_icon = if result.passed then Color.success else Color.failure in
    Printf.printf "%s %s\n" status_icon result.rule_name;

    List.iter
      (fun issue ->
        let icon =
          match issue.severity with
          | Error -> Color.failure
          | Warning -> Color.warning
          | Info -> Color.info
        in
        let file_str =
          match issue.file with
          | Some f -> Printf.sprintf " (%s)" f
          | None -> ""
        in
        Printf.printf "  %s %s%s\n" icon issue.message file_str;

        match issue.fix_suggestion with
        | Some suggestion ->
            Printf.printf "    %s%s%s\n" Color.cyan suggestion Color.reset
        | None -> ())
      result.issues

  let summarize results config =
    Printf.printf "\n%s%s%s\n" Color.bold (String.make 60 '=') Color.reset;

    let total_issues =
      List.fold_left (fun acc r -> acc + List.length r.issues) 0 results
    in
    let errors =
      List.fold_left
        (fun acc r ->
          acc + List.length (List.filter (fun i -> i.severity = Error) r.issues))
        0 results
    in
    let warnings = total_issues - errors in

    if errors > 0 then begin
      Printf.printf
        "%s Validation failed: %d issue(s) found (%d errors, %d warnings)%s\n"
        Color.failure total_issues errors warnings Color.reset;

      if config.fix_mode then begin
        Printf.printf "\n%sFix suggestions:%s\n\n" Color.bold Color.reset;
        List.iter
          (fun result ->
            List.iter
              (fun issue ->
                match issue.fix_suggestion with
                | Some suggestion ->
                    Printf.printf "%s%s%s\n" Color.green suggestion Color.reset
                | None -> ())
              result.issues)
          results
      end;
      1
    end
    else if warnings > 0 then begin
      Printf.printf "%s Validation completed with %d warning(s)%s\n"
        Color.warning warnings Color.reset;
      0
    end
    else begin
      Printf.printf "%s All validations passed!%s\n" Color.success Color.reset;
      0
    end
end

(* ========================================================================= *)
(* MAIN *)
(* ========================================================================= *)

let () =
  let verbose = ref false in
  let fix_mode = ref false in
  let show_help = ref false in

  let args = Array.to_list Sys.argv in
  List.iter
    (fun arg ->
      match arg with
      | "-v" | "--verbose" -> verbose := true
      | "-f" | "--fix" -> fix_mode := true
      | "-h" | "--help" -> show_help := true
      | _ -> ())
    (List.tl args);

  if !show_help then begin
    Printf.printf "Usage: validate-dotfiles.ml [options]\n\n";
    Printf.printf "Options:\n";
    Printf.printf "  -f, --fix       Show fix suggestions\n";
    Printf.printf "  -v, --verbose   Show detailed output\n";
    Printf.printf "  -h, --help      Show this help message\n\n";
    Printf.printf "Exit codes:\n";
    Printf.printf "  0 - All validations passed\n";
    Printf.printf "  1 - Validation failures found\n";
    Printf.printf "  2 - Critical error\n";
    exit 0
  end;

  let dotfiles_dir =
    try Sys.getenv "DOTFILES_DIR"
    with Not_found ->
      let home = Sys.getenv "HOME" in
      Filename.concat home ".dotfiles"
  in

  let config =
    { dotfiles_dir; verbose = !verbose; fix_mode = !fix_mode }
  in

  Printf.printf "\n%sValidating dotfiles repository...%s\n\n" Color.bold
    Color.reset;

  (* Define all validation rules *)
  let rules =
    [
      (fun () -> Rules.dotter_configs_exist config);
      (fun () -> Rules.dotter_files_tracked config);
      (fun () -> Rules.no_broken_symlinks config);
      (fun () -> Rules.toml_files_valid config);
    ]
  in

  (* Run all rules and collect results *)
  let results = Validator.run_rules config rules in

  (* Print each result *)
  List.iter Validator.print_result results;

  (* Summarize and exit with appropriate code *)
  let exit_code = Validator.summarize results config in
  exit exit_code
