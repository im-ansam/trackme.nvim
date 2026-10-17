-- Per-file history of counted lines, so reopening a file and typing on a
-- line that was already counted doesn't count it again. Only SHA-256
-- fingerprints of the (trimmed) line text are stored, never the code.
local config = require("trackme.config")
local fs = require("trackme.fs")

local M = {}

function M.fingerprint(key)
	return vim.fn.sha256(key):sub(1, 20)
end

local function read_all()
	local content = fs.read(config.options.history_file)
	if not content or content == "" then
		return {}
	end
	local ok, data = pcall(vim.json.decode, content)
	return ok and type(data) == "table" and data or {}
end

-- Multiset of fingerprints for a file: { [fingerprint] = count }
function M.get(path)
	return read_all()[path] or {}
end

function M.set(path, fingerprints)
	local file = config.options.history_file
	fs.with_lock(file, function()
		local all = read_all()
		all[path] = next(fingerprints) and fingerprints or nil
		return fs.write_atomic(file, vim.json.encode(all))
	end)
end

return M
