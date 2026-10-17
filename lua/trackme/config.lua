local M = {}

M.defaults = {
	-- Where the daily/monthly counts are written (base64-encoded JSON,
	-- same format as the TrackMe VS Code extension).
	data_dir = vim.fn.stdpath("data") .. "/trackme",
	-- Fingerprints of counted lines per file, so reopening a file doesn't
	-- count its lines again.
	history_file = vim.fn.stdpath("state") .. "/trackme/history.json",
	-- How often pending counts are written to disk (ms). Counts are also
	-- written when Neovim exits.
	flush_interval = 60 * 1000,
	-- Filetypes that are never tracked.
	exclude_filetypes = {
		"gitcommit",
		"gitrebase",
		"help",
		"lazy",
		"mason",
		"neo-tree",
		"TelescopePrompt",
		"toggleterm",
	},
	-- Extra filetype -> language name mappings (override the built-in ones).
	languages = {},
}

M.options = vim.deepcopy(M.defaults)

function M.set(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
