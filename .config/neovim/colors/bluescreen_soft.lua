-- Softer variant of the Strudel bluescreen theme.

local palette = {
  background = "#0A1C86",
  lineBackground = "#0A1C86",
  foreground = "#F5F7FF",
  muted = "#98A6E5",
  caret = "#FFFFFF",
  selection = "#2B4FAD",
  selectionMatch = "#20409B",
  lineHighlight = "#102A98",
  gutterBackground = "#0A1C86",
  gutterForeground = "#7387D8",
}

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "bluescreen_soft"
vim.o.background = "dark"

local set = vim.api.nvim_set_hl

set(0, "Normal", { fg = palette.foreground, bg = palette.background })
set(0, "NormalNC", { fg = palette.foreground, bg = palette.background })
set(0, "NormalFloat", { fg = palette.foreground, bg = palette.background })
set(0, "FloatBorder", { fg = palette.gutterForeground, bg = palette.background })
set(0, "LineNr", { fg = palette.gutterForeground, bg = palette.gutterBackground })
set(0, "CursorLineNr", { fg = palette.foreground, bg = palette.gutterBackground, bold = true })
set(0, "SignColumn", { fg = palette.gutterForeground, bg = palette.gutterBackground })
set(0, "FoldColumn", { fg = palette.gutterForeground, bg = palette.gutterBackground })
set(0, "CursorLine", { bg = palette.lineHighlight })
set(0, "ColorColumn", { bg = palette.lineBackground })
set(0, "Visual", { bg = palette.selection })
set(0, "Search", { fg = palette.foreground, bg = palette.selection })
set(0, "IncSearch", { fg = palette.foreground, bg = palette.selection })
set(0, "CurSearch", { fg = palette.foreground, bg = palette.selection })
set(0, "MatchParen", { fg = palette.foreground, bg = palette.selectionMatch, underline = true })
set(0, "Pmenu", { fg = palette.foreground, bg = palette.background })
set(0, "PmenuSel", { fg = palette.foreground, bg = palette.selection })
set(0, "WinSeparator", { fg = palette.gutterForeground, bg = palette.background })
set(0, "VertSplit", { fg = palette.gutterForeground, bg = palette.background })
set(0, "NonText", { fg = palette.muted, bg = palette.background })
set(0, "Whitespace", { fg = palette.muted, bg = palette.background })
set(0, "SpecialKey", { fg = palette.muted, bg = palette.background })

local monochrome = {
  "Comment",
  "Constant",
  "String",
  "Character",
  "Number",
  "Boolean",
  "Float",
  "Identifier",
  "Function",
  "Statement",
  "Conditional",
  "Repeat",
  "Label",
  "Operator",
  "Keyword",
  "Exception",
  "PreProc",
  "Include",
  "Define",
  "Macro",
  "PreCondit",
  "Type",
  "StorageClass",
  "Structure",
  "Typedef",
  "Special",
  "SpecialChar",
  "Tag",
  "Delimiter",
  "SpecialComment",
  "Debug",
  "Title",
  "Underlined",
  "Todo",
  "@attribute",
  "@boolean",
  "@character",
  "@comment",
  "@constant",
  "@constructor",
  "@function",
  "@keyword",
  "@label",
  "@number",
  "@operator",
  "@parameter",
  "@property",
  "@punctuation",
  "@string",
  "@tag",
  "@text",
  "@type",
  "@variable",
}

for _, group in ipairs(monochrome) do
  set(0, group, { fg = palette.foreground, bg = palette.background })
end
