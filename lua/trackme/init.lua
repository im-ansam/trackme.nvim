local config = require("trackme.config")

local M = {}

local started = false

function M.setup(opts)
	config.set(opts)
	if started then
		return
	end
	started = true

	local tracker = require("trackme.tracker")
	local storage = require("trackme.storage")
	tracker.start()

	local subcommands = {
		show = function()
			require("trackme.ui").open()
		end,
		flush = function()
			tracker.finalize_all()
			if storage.flush() then
				vim.notify("TrackMe: counts saved")
			end
		end,
		debug = function()
			tracker.set_debug(not tracker.debug())
			vim.notify("TrackMe debug signs " .. (tracker.debug() and "on (+ counted, ~ pending)" or "off"))
		end,
	}

	vim.api.nvim_create_user_command("TrackMe", function(cmd)
		local fn = subcommands[cmd.args ~= "" and cmd.args or "show"]
		if not fn then
			vim.notify("TrackMe: unknown subcommand " .. cmd.args, vim.log.levels.ERROR)
			return
		end
		fn()
	end, {
		nargs = "?",
		complete = function()
			return vim.tbl_keys(subcommands)
		end,
		desc = "Show hand-typed lines of code (subcommands: show, flush, debug)",
	})
end

return M
