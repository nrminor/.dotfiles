require("csvview").setup({
	parser = {
		comments = { "#", "//" },
		delimiter = {
			ft = {
				csv = ",",
				tsv = "\t",
			},
			fallbacks = { ",", "\t", ";", "|", ":" },
		},
	},
	view = {
		display_mode = "border",
		sticky_header = {
			enabled = true,
		},
	},
	keymaps = {
		textobject_field_inner = { "if", mode = { "o", "x" } },
		textobject_field_outer = { "af", mode = { "o", "x" } },
	},
})
