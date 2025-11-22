#!/usr/bin/env runhaskell

{-# LANGUAGE RecordWildCards #-}

{-
  Dotfiles Repository Validation Script (Haskell Edition)

  A composable validation framework using a Rules API.
  Each rule is a function that returns a validation result,
  and rules can be easily composed together.
-}

import           Control.Exception  (SomeException, catch)
import           Control.Monad      (filterM, forM, forM_, unless, when)
import           Data.Char          (isSpace)
import           Data.List          (isInfixOf, isPrefixOf, isSuffixOf)
import           Data.Maybe         (fromMaybe, mapMaybe)
import           System.Directory   (doesFileExist, getModificationTime,
                                     listDirectory)
import           System.Environment (getArgs, lookupEnv)
import           System.Exit        (ExitCode (..), exitWith)
import           System.FilePath    (takeExtension, (</>))
import           System.Process     (readProcess, readProcessWithExitCode)

-- ========================================================================
-- TYPES
-- ========================================================================

data Severity = Error | Warning | Info
  deriving (Show, Eq)

data Issue = Issue
  { issueSeverity      :: Severity
  , issueMessage       :: String
  , issueFile          :: Maybe String
  , issueFixSuggestion :: Maybe String
  } deriving Show

data ValidationResult = ValidationResult
  { ruleName :: String
  , passed   :: Bool
  , issues   :: [Issue]
  } deriving Show

type Rule = IO ValidationResult

data Config = Config
  { dotfilesDir :: FilePath
  , verbose     :: Bool
  , fixMode     :: Bool
  } deriving Show

-- ========================================================================
-- ANSI COLORS
-- ========================================================================

data Color = Reset | Bold | Red | Green | Yellow | Blue | Cyan

colorCode :: Color -> String
colorCode Reset  = "\x1b[0m"
colorCode Bold   = "\x1b[1m"
colorCode Red    = "\x1b[31m"
colorCode Green  = "\x1b[32m"
colorCode Yellow = "\x1b[33m"
colorCode Blue   = "\x1b[34m"
colorCode Cyan   = "\x1b[36m"

withColor :: Color -> String -> String
withColor c s = colorCode c ++ s ++ colorCode Reset

-- ========================================================================
-- LOGGING HELPERS
-- ========================================================================

success :: String -> IO ()
success msg = putStrLn $ withColor Green ("✓ " ++ msg)

failure :: String -> IO ()
failure msg = putStrLn $ withColor Red ("✗ " ++ msg)

warning :: String -> IO ()
warning msg = putStrLn $ withColor Yellow ("⚠ " ++ msg)

info :: String -> IO ()
info msg = putStrLn $ withColor Cyan ("ℹ " ++ msg)

verboseLog :: Config -> String -> IO ()
verboseLog Config{..} msg = when verbose $ putStrLn $ withColor Blue ("  " ++ msg)

-- ========================================================================
-- UTILITIES
-- ========================================================================

trim :: String -> String
trim = f . f where f = reverse . dropWhile isSpace

runGitCommand :: Config -> String -> IO (Maybe String)
runGitCommand Config{..} cmd = do
  (exitCode, stdout, _) <- readProcessWithExitCode "sh" ["-c", "cd " ++ dotfilesDir ++ " && " ++ cmd] ""
  case exitCode of
    ExitSuccess -> return $ Just (trim stdout)
    _           -> return Nothing

isTrackedByGit :: Config -> FilePath -> IO Bool
isTrackedByGit config path = do
  result <- runGitCommand config $ "git ls-files --error-unmatch " ++ path ++ " 2>/dev/null"
  return $ maybe False (not . null) result

isIgnoredByGit :: Config -> FilePath -> IO Bool
isIgnoredByGit config path = do
  result <- runGitCommand config $ "git check-ignore " ++ path ++ " 2>/dev/null"
  return $ maybe False (not . null) result

getTrackedFiles :: Config -> IO [FilePath]
getTrackedFiles config = do
  result <- runGitCommand config "git ls-files"
  return $ maybe [] lines result

isBrokenSymlink :: FilePath -> IO Bool
isBrokenSymlink path = do
  exists <- doesFileExist path
  return (not exists)

-- ========================================================================
-- TOML PARSING (Simple)
-- ========================================================================

data TomlSection = TomlSection
  { sectionName    :: String
  , sectionEntries :: [(String, String)]
  } deriving Show

parseTomlLine :: String -> Maybe (Either String (String, String))
parseTomlLine line
  | null trimmed || "#" `isPrefixOf` trimmed = Nothing
  | "[" `isPrefixOf` trimmed && "]" `isSuffixOf` trimmed =
      -- Extract section name by dropping first '[' and last ']'
      case trimmed of
        ('[':rest) -> case reverse rest of
                        (']':revName) -> Just . Left $ reverse revName
                        _             -> Nothing
        _ -> Nothing
  | "=" `isInfixOf` trimmed =
      let (key, rest) = break (== '=') trimmed
          value = dropWhile (== '=') rest
      in Just . Right $ (cleanQuotes $ trim key, cleanQuotes $ trim value)
  | otherwise = Nothing
  where
    trimmed = trim line
    cleanQuotes s = case s of
      ('"':rest) -> case reverse rest of
                      ('"':revBody) -> reverse revBody
                      _             -> s
      _ -> s

parseToml :: FilePath -> IO [(String, String, String)]
parseToml path = do
  content <- readFile path
  let ls = lines content
      parsed = mapMaybe parseTomlLine ls
  return $ extractFiles parsed [] Nothing
  where
    extractFiles [] acc _ = acc
    extractFiles (Left section : rest) acc _ = extractFiles rest acc (Just section)
    extractFiles (Right (k, v) : rest) acc (Just sect)
      | ".files" `isSuffixOf` sect =
          let group = takeWhile (/= '.') sect
          in extractFiles rest ((k, v, group) : acc) (Just sect)
      | otherwise = extractFiles rest acc (Just sect)
    extractFiles (_ : rest) acc Nothing = extractFiles rest acc Nothing

-- ========================================================================
-- VALIDATION RULES
-- ========================================================================

-- Rule: Dotter configuration files exist
dotterConfigsExist :: Config -> Rule
dotterConfigsExist config@Config{..} = do
  let globalToml = dotfilesDir </> ".dotter" </> "global.toml"
  exists <- doesFileExist globalToml

  let issues = if exists then [] else
        [Issue Error "Dotter global.toml not found" (Just globalToml) Nothing]

  return $ ValidationResult "Dotter configuration files exist" (null issues) issues

-- Rule: All files referenced in dotter config exist and are tracked
dotterFilesTracked :: Config -> Rule
dotterFilesTracked config@Config{..} = do
  let globalToml = dotfilesDir </> ".dotter" </> "global.toml"
      macosToml  = dotfilesDir </> ".dotter" </> "macos.toml"

  globalFiles <- parseToml globalToml `catch` (\(_ :: SomeException) -> return [])
  macosExists <- doesFileExist macosToml
  macosFiles <- if macosExists
                then parseToml macosToml `catch` (\(_ :: SomeException) -> return [])
                else return []

  let allFiles = globalFiles ++ macosFiles

  when verbose $ info $ "Found " ++ show (length allFiles) ++ " files referenced in dotter configs"

  issues <- fmap concat $ forM allFiles $ \(source, _, group) -> do
    let filepath = dotfilesDir </> source
    exists <- doesFileExist filepath
    if not exists then
      return [Issue Error ("File missing: " ++ source ++ " (from " ++ group ++ ")")
                    (Just source) Nothing]
    else do
      tracked <- isTrackedByGit config source
      if not tracked then do
        ignored <- isIgnoredByGit config source
        if ignored then
          return [Issue Error ("File ignored by git: " ++ source ++ " (from " ++ group ++ ")")
                       (Just source) (Just $ "Add to .gitignore: !" ++ source)]
        else
          return [Issue Warning ("File not tracked: " ++ source ++ " (from " ++ group ++ ")")
                       (Just source) (Just $ "Run: git add " ++ source)]
      else return []

  let onlyErrors = filter (\i -> issueSeverity i == Error) issues
  return $ ValidationResult "Dotter files exist and are tracked" (null onlyErrors) issues

-- Rule: No broken symlinks
noBrokenSymlinks :: Config -> Rule
noBrokenSymlinks config@Config{..} = do
  tracked <- getTrackedFiles config
  issues <- fmap concat $ forM tracked $ \file -> do
    let path = dotfilesDir </> file
    broken <- isBrokenSymlink path `catch` (\(_ :: SomeException) -> return False)
    return $ if broken
      then [Issue Error ("Broken symlink: " ++ file) (Just file) Nothing]
      else []

  return $ ValidationResult "No broken symlinks" (null issues) issues

-- Rule: TOML files are valid
tomlFilesValid :: Config -> Rule
tomlFilesValid config@Config{..} = do
  tracked <- getTrackedFiles config
  let tomlFiles = filter (".toml" `isSuffixOf`) tracked

  issues <- fmap concat $ forM tomlFiles $ \file -> do
    let path = dotfilesDir </> file
    result <- (parseToml path >> return Nothing) `catch`
              (\(_ :: SomeException) -> return $ Just file)
    case result of
      Nothing -> return []
      Just f  -> return [Issue Error ("Invalid TOML syntax: " ++ f) (Just f) Nothing]

  return $ ValidationResult ("All " ++ show (length tomlFiles) ++ " TOML files are valid")
                           (null issues) issues

-- ========================================================================
-- RULE COMPOSITION & EXECUTION
-- ========================================================================

runRule :: Config -> Rule -> IO ValidationResult
runRule config rule = do
  verboseLog config "Checking..."
  rule

runRules :: Config -> [Rule] -> IO [ValidationResult]
runRules config = mapM (runRule config)

printResult :: ValidationResult -> IO ()
printResult ValidationResult{..} = do
  let statusIcon = if passed then withColor Green "✓" else withColor Red "✗"
  putStrLn $ statusIcon ++ " " ++ ruleName

  forM_ issues $ \Issue{..} -> do
    let icon = case issueSeverity of
                 Error   -> withColor Red "✗"
                 Warning -> withColor Yellow "⚠"
                 Info    -> withColor Cyan "ℹ"
        fileStr = maybe "" (\f -> " (" ++ f ++ ")") issueFile
    putStrLn $ "  " ++ icon ++ " " ++ issueMessage ++ fileStr
    case issueFixSuggestion of
      Just suggestion -> putStrLn $ "    " ++ withColor Cyan suggestion
      Nothing         -> return ()

summarize :: Config -> [ValidationResult] -> IO Int
summarize Config{..} results = do
  putStrLn $ "\n" ++ withColor Bold (replicate 60 '=')

  let totalIssues = sum $ map (length . issues) results
      errors = length $ filter (\i -> issueSeverity i == Error) $ concatMap issues results
      warnings = totalIssues - errors

  if errors > 0 then do
    putStrLn $ withColor Red $ "✗ Validation failed: " ++ show totalIssues ++
               " issue(s) found (" ++ show errors ++ " errors, " ++ show warnings ++ " warnings)"

    when fixMode $ do
      putStrLn $ "\n" ++ withColor Bold "🔧 Fix suggestions:" ++ "\n"

      let ignoredFiles = [f | Issue _ _ (Just f) (Just s) <- concatMap issues results,
                             ".gitignore" `isInfixOf` s]
      unless (null ignoredFiles) $ do
        putStrLn $ withColor Cyan "Add these lines to .gitignore:"
        forM_ ignoredFiles $ \f -> putStrLn $ withColor Green $ "  !" ++ f
        putStrLn ""

      let untrackedFiles = [f | Issue _ _ (Just f) (Just s) <- concatMap issues results,
                               "git add" `isInfixOf` s]
      unless (null untrackedFiles) $ do
        putStrLn $ withColor Cyan "Run this command to track files:"
        putStrLn $ withColor Green $ "  git add " ++ unwords untrackedFiles
        putStrLn ""

    return 1
  else if warnings > 0 then do
    putStrLn $ withColor Yellow $ "⚠ Validation completed with " ++ show warnings ++ " warning(s)"
    return 0
  else do
    putStrLn $ withColor Green "✓ All validations passed!\n"
    return 0

-- ========================================================================
-- MAIN
-- ========================================================================

parseArgs :: [String] -> (Bool, Bool, Bool)
parseArgs args = (hasArg "help", hasArg "verbose", hasArg "fix")
  where
    hasArg opt = any (\a -> a == "-" ++ take 1 opt || a == "--" ++ opt) args

main :: IO ()
main = do
  args <- getArgs
  let (showHelp, isVerbose, showFix) = parseArgs args

  when showHelp $ do
    putStrLn "\nUsage: validate-dotfiles.hs [options]\n"
    putStrLn "Options:"
    putStrLn "  -f, --fix       Show fix suggestions"
    putStrLn "  -v, --verbose   Show detailed output"
    putStrLn "  -h, --help      Show this help message\n"
    putStrLn "Exit codes:"
    putStrLn "  0 - All validations passed"
    putStrLn "  1 - Validation failures found"
    putStrLn "  2 - Critical error\n"
    exitWith ExitSuccess

  dotfilesDirEnv <- lookupEnv "DOTFILES_DIR"
  homeDir <- lookupEnv "HOME"
  let dotfilesPath = fromMaybe (fromMaybe "." homeDir ++ "/.dotfiles") dotfilesDirEnv

  let config = Config
        { dotfilesDir = dotfilesPath
        , verbose = isVerbose
        , fixMode = showFix
        }

  putStrLn $ "\n" ++ withColor Bold "Validating dotfiles repository..." ++ "\n"

  -- Define all validation rules
  let rules =
        [ dotterConfigsExist config
        , dotterFilesTracked config
        , noBrokenSymlinks config
        , tomlFilesValid config
        ]

  -- Run all rules and collect results
  results <- runRules config rules

  -- Print each result
  mapM_ printResult results

  -- Summarize and exit with appropriate code
  exitCode <- summarize config results
  exitWith $ if exitCode == 0 then ExitSuccess else ExitFailure exitCode
