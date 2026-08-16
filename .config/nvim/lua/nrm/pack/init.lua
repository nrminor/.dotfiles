local specs = require("nrm.pack.specs")

local parser_languages = { "lua", "typescript" }
local maintenance_kinds = { install = true, update = true }

local function activate(change)
	if not change.active then
		vim.cmd.packadd(change.spec.name)
	end
end

vim.api.nvim_create_autocmd("PackChanged", {
	desc = "Maintain native Neovim plugin artifacts",
	callback = function(event)
		local change = event.data
		if not maintenance_kinds[change.kind] then
			return
		end

		if change.spec.name == "fff" then
			activate(change)
			require("fff.download").download_or_build_binary()
		elseif change.spec.name == "nvim-treesitter" then
			activate(change)
			local treesitter = require("nvim-treesitter")
			local task = change.kind == "install" and treesitter.install(parser_languages) or treesitter.update()
			if task:wait(300000) ~= true then
				error("Tree-sitter parser maintenance failed")
			end
		end
	end,
})

vim.pack.add(specs, { confirm = false, load = false })
