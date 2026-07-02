local Flash = require("flash")

local M = {}

local exit_flash_on_enter = {
	["<cr>"] = function(state)
		state:restore()
		return false
	end,
}

local function two_char_label(opts)
	return {
		{ opts.match.label1, "FlashLabel" },
		{ opts.match.label2, "FlashLabel" },
	}
end

function M.helix_word_jump()
	Flash.jump({
		actions = exit_flash_on_enter,
		pattern = [[\<]],
		search = {
			mode = "search",
		},
		label = {
			after = false,
			before = { 0, 0 },
			format = two_char_label,
			uppercase = false,
		},
		labeler = function(matches, state)
			local labels = state:labels()
			local label_count = #labels
			local max_labeled_matches = label_count * label_count

			for index, match in ipairs(matches) do
				if index > max_labeled_matches then
					match.label = false
				else
					match.label1 = labels[math.floor((index - 1) / label_count) + 1]
					match.label2 = labels[((index - 1) % label_count) + 1]
					match.label = match.label1
				end
			end
		end,
		action = function(match, state)
			state:hide()

			Flash.jump({
				actions = exit_flash_on_enter,
				search = {
					max_length = 0,
				},
				highlight = {
					matches = false,
				},
				label = {
					after = false,
					before = { 0, 0 },
					format = two_char_label,
					uppercase = false,
				},
				matcher = function(win)
					return vim.tbl_filter(function(candidate)
						return candidate.label == match.label and candidate.win == win
					end, state.results)
				end,
				labeler = function(matches)
					for _, candidate in ipairs(matches) do
						candidate.label = candidate.label2
					end
				end,
			})
		end,
	})
end

return M
