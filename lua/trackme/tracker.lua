-- Counts hand-typed lines.
--
-- * A character counts as typed only when it is inserted by a key that came
--   at least BURST_NS after the previous key, and the key after it also comes
--   at least BURST_NS later. Real keystrokes are milliseconds apart; text from
--   <C-r>, `.`, count repeats and unbracketed terminal pastes is processed
--   microseconds apart. Macros are excluded with reg_executing(). (vim.on_key's
--   `typed` argument can't be used: it is empty for every key while nvim-cmp
--   is active.) `p` and bracketed pastes never trigger InsertCharPre at all.
--   A line only needs one such character to count.
-- * A line typed on gets a "pending" extmark. When the user leaves the line,
--   leaves insert mode or saves, pending lines with content become
--   "counted" (one count each) and keep an extmark, which follows the line
--   when lines are added or removed above it. Typing on a counted line
--   again doesn't count.
-- * A counted line that is deleted goes to a per-buffer graveyard keyed by
--   its text, so retyping the same line doesn't count it twice, and a
--   formatter replacing lines doesn't lose them.
-- * On save, fingerprints of counted lines are stored per file; when the
--   file is opened again those lines are marked counted.
local config = require("trackme.config")
local history = require("trackme.history")
local languages = require("trackme.languages")
local storage = require("trackme.storage")

local api = vim.api
local M = {}

local ns = api.nvim_create_namespace("trackme")
local bufs = {} -- per-buffer state
local BURST_NS = 3 * 1000 * 1000 -- keys closer together than 3 ms aren't typed
local KS_EXTRA = "\128\253" -- internal keys: events, <Cmd>, <Plug>, <Ignore>, ...
local last_typed -- key the user pressed, consumed by the next InsertCharPre
local last_key_time = 0
local provisional -- pending mark created by the last key, until the next key confirms it
local debug = false

-- Lines are identified by their text without any whitespace, so a line
-- reformatted by a formatter (`x=1` -> `x = 1`, re-indented) is still
-- recognised as the same counted line.
local function line_key(text)
	return (text:gsub("%s+", ""))
end

local function trackable(buf)
	return api.nvim_buf_is_valid(buf)
		and vim.bo[buf].buftype == ""
		and api.nvim_buf_get_name(buf) ~= ""
		and not vim.tbl_contains(config.options.exclude_filetypes, vim.bo[buf].filetype)
end

local function state(buf)
	if not bufs[buf] then
		-- pending[id] = true, counted[id] = line key, graveyard[text] = n
		bufs[buf] = { pending = {}, counted = {}, graveyard = {}, dirty = false }
	end
	return bufs[buf]
end

-- Counted marks are invalidated when their line is deleted. Pending marks
-- aren't: they only live while the line is being typed on, and the first
-- edit of an empty buffer replaces line 1, which would invalidate them.
-- Pending marks have left gravity so text typed at column 0 doesn't push
-- them along with the cursor (and onto the next line on <Enter>). Counted
-- marks have right gravity so they move down with their text when <Enter>
-- is pressed at the start of the line.
local function set_mark(buf, row, kind, id)
	local counted = kind == "counted"
	local opts = { id = id, invalidate = counted, right_gravity = counted }
	if debug then
		opts.sign_text = kind == "counted" and "+" or "~"
		opts.sign_hl_group = kind == "counted" and "DiagnosticOk" or "DiagnosticWarn"
	end
	return api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
end

-- Is there a valid mark from `set` on this row?
local function row_has(buf, row, set)
	for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })) do
		if set[m[1]] and not m[4].invalid then
			return true
		end
	end
	return false
end

local function on_insert_char()
	local typed = last_typed
	last_typed = nil
	local buf = api.nvim_get_current_buf()
	local char = vim.v.char
	if typed ~= char or vim.fn.reg_executing() ~= "" or not char:find("%S") or not trackable(buf) then
		return
	end
	local s = state(buf)
	local row = api.nvim_win_get_cursor(0)[1] - 1
	if row_has(buf, row, s.counted) or row_has(buf, row, s.pending) then
		return
	end
	local id = set_mark(buf, row, "pending")
	s.pending[id] = true
	provisional = { buf = buf, id = id }
end

-- Called for every key: decides whether the key was typed by a person.
local function on_key(key)
	if key:sub(1, 2) == KS_EXTRA then
		return
	end
	local now = vim.uv.hrtime()
	local typed = now - last_key_time >= BURST_NS
	last_key_time = now

	-- The previous key was followed too quickly: it was part of a burst
	-- (e.g. the first character of an unbracketed paste), so undo its mark.
	if provisional and not typed then
		local s = bufs[provisional.buf]
		if s and s.pending[provisional.id] and api.nvim_buf_is_valid(provisional.buf) then
			s.pending[provisional.id] = nil
			api.nvim_buf_del_extmark(provisional.buf, ns, provisional.id)
		end
	end
	provisional = nil

	local mode = api.nvim_get_mode().mode:sub(1, 1)
	last_typed = typed and (mode == "i" or mode == "R") and key or nil
end

-- Turn pending lines into counted ones and refresh counted lines.
function M.finalize(buf)
	local s = bufs[buf]
	if not s or not api.nvim_buf_is_valid(buf) then
		return
	end
	local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
	local marks = {}
	for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
		marks[m[1]] = m
	end

	-- Counted lines: track their current text; deleted ones go to the graveyard
	for id, text in pairs(s.counted) do
		local m = marks[id]
		if not m or m[4].invalid then
			s.graveyard[text] = (s.graveyard[text] or 0) + 1
			s.graveyard_changed = true
			s.counted[id] = nil
			s.dirty = true
			if m then
				api.nvim_buf_del_extmark(buf, ns, id)
			end
		else
			local now = line_key(lines[m[2] + 1] or "")
			if now ~= "" and now ~= text then
				s.counted[id] = now
				s.dirty = true
			end
		end
	end

	-- Pending lines: count the ones that have content
	local lang = languages.name(vim.bo[buf].filetype)
	for id in pairs(s.pending) do
		local m = marks[id]
		s.pending[id] = nil
		if m then
			api.nvim_buf_del_extmark(buf, ns, id)
		end
		if m and not m[4].invalid then
			local row = m[2]
			local text = line_key(lines[row + 1] or "")
			if text ~= "" and not row_has(buf, row, s.counted) then
				if (s.graveyard[text] or 0) > 0 then
					s.graveyard[text] = s.graveyard[text] - 1
				else
					storage.add(lang, 1)
				end
				s.counted[set_mark(buf, row, "counted")] = text
				s.dirty = true
			end
		end
	end

	-- A counted line whose mark was dropped but whose text is still in the
	-- buffer (a formatter or :%s replaced the line) is still counted.
	if s.graveyard_changed then
		s.graveyard_changed = false
		local marked = {}
		for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			if s.counted[m[1]] and not m[4].invalid then
				marked[m[2]] = true
			end
		end
		for i, line in ipairs(lines) do
			local text = line_key(line)
			if not marked[i - 1] and (s.graveyard[text] or 0) > 0 then
				s.graveyard[text] = s.graveyard[text] - 1
				s.counted[set_mark(buf, i - 1, "counted")] = text
			end
		end
	end
end

function M.finalize_all()
	for buf in pairs(bufs) do
		M.finalize(buf)
	end
end

-- Save fingerprints of this buffer's counted lines.
function M.save_history(buf)
	local s = bufs[buf]
	if not s or not api.nvim_buf_is_valid(buf) then
		return
	end
	M.finalize(buf)
	if not s.dirty then
		return
	end
	local fps = {}
	for _, text in pairs(s.counted) do
		local fp = history.fingerprint(text)
		fps[fp] = (fps[fp] or 0) + 1
	end
	history.set(api.nvim_buf_get_name(buf), fps)
	s.dirty = false
end

-- Mark lines of a freshly read buffer that were counted in earlier sessions.
local function load_history(buf)
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	bufs[buf] = nil
	if not trackable(buf) then
		return
	end
	local fps = history.get(api.nvim_buf_get_name(buf))
	if not next(fps) then
		return
	end
	local s = state(buf)
	for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local text = line_key(line)
		if text ~= "" then
			local fp = history.fingerprint(text)
			if (fps[fp] or 0) > 0 then
				fps[fp] = fps[fp] - 1
				s.counted[set_mark(buf, i - 1, "counted")] = text
			end
		end
	end
end

function M.set_debug(on)
	debug = on
	for buf, s in pairs(bufs) do
		if api.nvim_buf_is_valid(buf) then
			for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
				if not m[4].invalid then
					set_mark(buf, m[2], s.counted[m[1]] and "counted" or "pending", m[1])
				end
			end
		end
	end
end

function M.debug()
	return debug
end

-- Counted lines in a buffer (for tests and :TrackMe debug)
function M.counted_rows(buf)
	local rows = {}
	local s = bufs[buf]
	if s then
		for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			if s.counted[m[1]] and not m[4].invalid then
				table.insert(rows, m[2] + 1)
			end
		end
	end
	return rows
end

function M.start()
	vim.on_key(on_key, ns)

	local group = api.nvim_create_augroup("trackme", { clear = true })
	api.nvim_create_autocmd("InsertCharPre", { group = group, callback = on_insert_char })
	api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = function(ev)
			local row = api.nvim_win_get_cursor(0)[1]
			if vim.b[ev.buf].trackme_row ~= row then
				vim.b[ev.buf].trackme_row = row
				M.finalize(ev.buf)
			end
		end,
	})
	api.nvim_create_autocmd({ "InsertEnter" }, {
		group = group,
		callback = function(ev)
			vim.b[ev.buf].trackme_row = api.nvim_win_get_cursor(0)[1]
		end,
	})
	api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
		group = group,
		callback = function(ev)
			M.finalize(ev.buf)
		end,
	})
	api.nvim_create_autocmd("BufReadPost", {
		group = group,
		callback = function(ev)
			load_history(ev.buf)
		end,
	})
	api.nvim_create_autocmd({ "BufWritePost", "BufUnload" }, {
		group = group,
		callback = function(ev)
			M.save_history(ev.buf)
			if ev.event == "BufUnload" then
				bufs[ev.buf] = nil
			end
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for buf in pairs(bufs) do
				M.save_history(buf)
			end
			storage.flush()
		end,
	})

	-- Buffers already open when the plugin starts
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_loaded(buf) then
			load_history(buf)
		end
	end

	local timer = vim.uv.new_timer()
	timer:start(
		config.options.flush_interval,
		config.options.flush_interval,
		vim.schedule_wrap(function()
			M.finalize_all()
			storage.flush()
		end)
	)
end

return M
