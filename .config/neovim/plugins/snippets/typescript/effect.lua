-- args is a table, where 1 is the text in Placeholder 1, 2 the text in
-- placeholder 2,...
local function copy(args)
	return args[1][1]
end

return {
	s({ trig = "ss", name = "Effect Service", desc = "Create an Effect Service using Effect.Service" }, {
		t("export class "),
		i(1),
		t(" extends Effect.Service<"),
		f(copy, 1),
		t('>()("'),
		d(2, function(args)
			return sn(nil, { i(1, args[1][1]) })
		end, { 1 }),
		t('", {'),
		t({ "", "\t" }),
		i(3),
		t({ "", "}) {}" }),
	}),

	s({ trig = "fn", name = "Effect Fn", desc = "Create an Effect.fn" }, {
		t({ "Effect.fn(", i(1), ")(", "" }),
		t("\t"),
		i(2),
		t({ "", ")" }),
	}),

	s({ trig = "gg", name = "Effect Gen", desc = "Create an Effect generator" }, {
		t({ "Effect.gen(function*() {", "" }),
		t("\t"),
		i(1),
		t({ "", "})" }),
	}),

	s({ trig = "yy", name = "Yield", desc = "Create a yield statement" }, {
		t({ "yield* " }),
		i(1),
	}),

	s({ trig = "internal", name = "Internal Annotation", desc = "Annotate a TypeScript export as internal" }, {
		t({ "/** @internal */" }),
	}),
}
