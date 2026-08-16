vim.cmd.packadd("LuaSnip")
vim.cmd.packadd("blink.cmp")
vim.cmd.packadd("nvim-treesitter")
vim.cmd.packadd("nvim-treesitter-textobjects")
vim.cmd.packadd("nvim-ts-autotag")
vim.cmd.packadd("Comment.nvim")
vim.cmd.packadd("nvim-autopairs")

local luasnip = require("luasnip")
luasnip.config.setup({ updateevents = "TextChanged,TextChangedI" })
require("luasnip.loaders.from_lua").lazy_load({ paths = vim.fn.stdpath("config") .. "/snippets" })

vim.api.nvim_create_autocmd("ModeChanged", {
	desc = "Leave snippet on mode change",
	callback = function()
		local event = vim.v.event
		local current_node = luasnip.session.current_nodes[vim.api.nvim_get_current_buf()]
		if
			((event.old_mode == "s" and event.new_mode == "n") or event.old_mode == "i")
			and current_node
			and not luasnip.session.jump_active
		then
			luasnip.unlink_current()
		end
	end,
})

require("blink.cmp").setup({
	appearance = { nerd_font_variant = "mono" },
	completion = {
		list = { selection = { preselect = false } },
		documentation = { auto_show = true, auto_show_delay_ms = 100 },
		trigger = { show_in_snippet = false },
	},
	fuzzy = { implementation = "prefer_rust" },
	keymap = {
		preset = "default",
		["<CR>"] = { "accept", "fallback" },
		["<C-j>"] = { "scroll_documentation_down", "fallback" },
		["<C-k>"] = { "scroll_documentation_up", "fallback" },
		["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
		["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
	},
	signature = { enabled = true },
	snippets = { preset = "luasnip" },
	sources = {
		default = { "lsp", "buffer", "snippets", "path" },
		providers = {
			lsp = { score_offset = 4 },
			snippets = {
				score_offset = 5,
				should_show_items = function(context)
					return context.trigger.initial_kind ~= "manual"
						and context.trigger.initial_kind ~= "trigger_character"
				end,
			},
		},
	},
})

require("nvim-treesitter").setup()
vim.treesitter.language.register("markdown", "mdx")
vim.treesitter.language.register("groovy", "nextflow")
vim.api.nvim_create_autocmd("FileType", {
	pattern = "*",
	callback = function(event)
		if pcall(vim.treesitter.start, event.buf) then
			vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end
	end,
})

local textobject_select = require("nvim-treesitter-textobjects.select")
local selection_mappings = {
	aa = "@parameter.outer",
	ia = "@parameter.inner",
	af = "@function.outer",
	["if"] = "@function.inner",
	ac = "@class.outer",
	ic = "@class.inner",
	ii = "@conditional.inner",
	ai = "@conditional.outer",
	il = "@loop.inner",
	al = "@loop.outer",
	at = "@comment.outer",
}

for key, query in pairs(selection_mappings) do
	vim.keymap.set({ "x", "o" }, key, function()
		textobject_select.select_textobject(query, "textobjects")
	end, { desc = "Select " .. query })
end

local textobject_move = require("nvim-treesitter-textobjects.move")
local movement_mappings = {
	["]m"] = { query = "@function.outer", method = "goto_next_start" },
	["]]"] = { query = "@class.outer", method = "goto_next_start" },
	["]M"] = { query = "@function.outer", method = "goto_next_end" },
	["]["] = { query = "@class.outer", method = "goto_next_end" },
	["[m"] = { query = "@function.outer", method = "goto_previous_start" },
	["[["] = { query = "@class.outer", method = "goto_previous_start" },
	["[M"] = { query = "@function.outer", method = "goto_previous_end" },
	["[]"] = { query = "@class.outer", method = "goto_previous_end" },
}

for key, mapping in pairs(movement_mappings) do
	vim.keymap.set({ "n", "x", "o" }, key, function()
		textobject_move[mapping.method](mapping.query, "textobjects")
	end, { desc = mapping.method .. " " .. mapping.query })
end

require("nvim-ts-autotag").setup()
require("Comment").setup()
require("nvim-autopairs").setup({ check_ts = true })
