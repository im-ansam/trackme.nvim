-- Daily and monthly line counts, stored like the TrackMe VS Code extension:
-- base64 of JSON { "<period>": { "lines_of_code": { "<lang>": n, "total": n } } }
-- with daily periods "MM/DD/YYYY" and monthly periods "YYYY-Mon".
local config = require("trackme.config")
local fs = require("trackme.fs")

local M = {}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local MONTH_INDEX = {}
for i, name in ipairs(MONTHS) do
	MONTH_INDEX[name] = i
end

-- Counts not yet written to disk: pending[day_key][lang] = n
local pending = {}

function M.day_key(time)
	return os.date("%m/%d/%Y", time)
end

function M.month_key(time)
	return os.date("%Y-", time) .. MONTHS[tonumber(os.date("%m", time))]
end

local function month_of_day(day)
	local m, _, y = day:match("^(%d+)/(%d+)/(%d+)$")
	return y .. "-" .. MONTHS[tonumber(m)]
end

local function paths()
	local dir = config.options.data_dir
	return dir .. "/daily-progress-tracker.json.b64", dir .. "/monthly-progress-tracker.json.b64"
end

function M.add(lang, n)
	local day = M.day_key()
	pending[day] = pending[day] or {}
	pending[day][lang] = (pending[day][lang] or 0) + n
end

function M.has_pending()
	return next(pending) ~= nil
end

-- Pending counts (for display before they are flushed)
function M.pending()
	return pending
end

-- Sort keys for periods so the file stays in date order.
local function period_sort_key(key)
	local m, d, y = key:match("^(%d+)/(%d+)/(%d+)$")
	if m then
		return string.format("%04d%02d%02d", y, m, d)
	end
	local yy, mon = key:match("^(%d+)%-(%a+)$")
	if yy and MONTH_INDEX[mon] then
		return string.format("%04d%02d00", yy, MONTH_INDEX[mon])
	end
	return key
end

local function sorted_keys(tbl, depth)
	local keys = vim.tbl_keys(tbl)
	table.sort(keys, function(a, b)
		if depth == 1 then
			return period_sort_key(a) < period_sort_key(b)
		end
		-- "total" first, then languages by count
		if a == "total" or b == "total" then
			return a == "total"
		end
		local va, vb = tbl[a], tbl[b]
		if type(va) == "number" and type(vb) == "number" and va ~= vb then
			return va > vb
		end
		return a < b
	end)
	return keys
end

-- Pretty JSON with 4-space indentation (like JSON.stringify(data, null, 4)).
local function encode(value, depth)
	depth = depth or 1
	if type(value) ~= "table" then
		if type(value) == "number" and value == math.floor(value) then
			return string.format("%d", value)
		end
		return vim.json.encode(value)
	end
	local keys = sorted_keys(value, depth)
	if #keys == 0 then
		return "{}"
	end
	local indent = string.rep("    ", depth)
	local parts = {}
	for _, k in ipairs(keys) do
		table.insert(parts, indent .. vim.json.encode(k) .. ": " .. encode(value[k], depth + 1))
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep("    ", depth - 1) .. "}"
end

-- Returns the decoded table, {} for a missing file, or nil + error for a
-- file that exists but can't be decoded (it is then never overwritten).
local function read_data(path)
	local content = fs.read(path)
	if not content or vim.trim(content) == "" then
		return {}
	end
	local ok, json = pcall(vim.base64.decode, vim.trim(content))
	if not ok then
		return nil, "invalid base64 in " .. path
	end
	local ok2, data = pcall(vim.json.decode, json)
	if not ok2 or type(data) ~= "table" then
		return nil, "invalid JSON in " .. path
	end
	return data
end

local function add_to(data, period, lang, n)
	data[period] = data[period] or {}
	local loc = data[period].lines_of_code or {}
	data[period].lines_of_code = loc
	loc[lang] = (loc[lang] or 0) + n
	loc.total = (loc.total or 0) + n
end

-- Write pending counts into the data files. Re-reads the files under a
-- lock right before writing, so other Neovim instances' counts are kept.
function M.flush()
	if not M.has_pending() then
		return true
	end
	local daily_path, monthly_path = paths()
	local ok, err = fs.with_lock(daily_path, function()
		local daily, e1 = read_data(daily_path)
		local monthly, e2 = read_data(monthly_path)
		if not daily or not monthly then
			return false, e1 or e2
		end
		for day, langs in pairs(pending) do
			for lang, n in pairs(langs) do
				add_to(daily, day, lang, n)
				add_to(monthly, month_of_day(day), lang, n)
			end
		end
		local w1, we1 = fs.write_atomic(daily_path, vim.base64.encode(encode(daily)))
		if not w1 then
			return false, we1
		end
		local w2, we2 = fs.write_atomic(monthly_path, vim.base64.encode(encode(monthly)))
		if not w2 then
			return false, we2
		end
		return true
	end)
	if ok then
		pending = {}
	else
		vim.notify("TrackMe: could not save counts: " .. tostring(err), vim.log.levels.ERROR)
	end
	return ok
end

-- Read both data files (without pending counts).
function M.read()
	local daily_path, monthly_path = paths()
	return read_data(daily_path) or {}, read_data(monthly_path) or {}
end

M._encode = encode

return M
