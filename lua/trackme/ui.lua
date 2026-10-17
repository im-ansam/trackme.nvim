-- :TrackMe window: today, this week and this month, by language.
local storage = require("trackme.storage")
local tracker = require("trackme.tracker")

local M = {}

local DAY = 24 * 60 * 60

local function add_counts(into, loc)
	for lang, n in pairs(loc or {}) do
		into[lang] = (into[lang] or 0) + n
	end
end

-- Monday-to-Sunday dates of the current week
local function week_days(now)
	local wday = tonumber(os.date("%w", now)) -- 0 = Sunday
	local monday = now - ((wday + 6) % 7) * DAY
	local days = {}
	for i = 0, 6 do
		table.insert(days, monday + i * DAY)
	end
	return days
end

local function section(lines, title, counts)
	local langs = {}
	for lang, n in pairs(counts) do
		if lang ~= "total" then
			table.insert(langs, { lang, n })
		end
	end
	table.sort(langs, function(a, b)
		return a[2] == b[2] and a[1] < b[1] or a[2] > b[2]
	end)
	-- Pad by display width: the titles contain multi-byte characters
	local pad = string.rep(" ", math.max(1, 31 - vim.fn.strdisplaywidth(title)))
	table.insert(lines, string.format("%s%s%6d", title, pad, counts.total or 0))
	if #langs == 0 then
		table.insert(lines, "  (nothing yet)")
	end
	for _, l in ipairs(langs) do
		table.insert(lines, string.format("  %-28s %6d", l[1], l[2]))
	end
	table.insert(lines, "")
end

function M.summary()
	tracker.finalize_all()
	storage.flush()
	local daily, monthly = storage.read()
	local now = os.time()

	local today = {}
	add_counts(today, (daily[storage.day_key(now)] or {}).lines_of_code)

	local week = {}
	local days = week_days(now)
	for _, t in ipairs(days) do
		add_counts(week, (daily[storage.day_key(t)] or {}).lines_of_code)
	end

	local month = {}
	add_counts(month, (monthly[storage.month_key(now)] or {}).lines_of_code)

	local lines = {}
	section(lines, "Today · " .. storage.day_key(now), today)
	section(
		lines,
		string.format("This week · %s – %s", os.date("%m/%d", days[1]), os.date("%m/%d", days[7])),
		week
	)
	section(lines, "This month · " .. storage.month_key(now), month)
	return lines
end

function M.open()
	local lines = M.summary()
	local text = vim.deepcopy(lines)
	table.insert(lines, "y copy · q close")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	local width = 40
	local height = #lines
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " TrackMe · lines of code ",
		title_pos = "center",
	})

	local hl_ns = vim.api.nvim_create_namespace("trackme_ui")
	for i, line in ipairs(lines) do
		if line:match("^%S") then
			local group = i == #lines and "Comment" or "Title"
			vim.hl.range(buf, hl_ns, group, { i - 1, 0 }, { i - 1, -1 })
		end
	end

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "y", function()
		while text[#text] == "" do
			table.remove(text)
		end
		vim.fn.setreg("+", table.concat(text, "\n"))
		vim.notify("TrackMe: summary copied to clipboard")
		close()
	end, { buffer = buf, nowait = true })
end

return M
