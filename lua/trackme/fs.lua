-- Small file helpers: whole-file read, atomic write and a cross-process lock.
local uv = vim.uv

local M = {}

function M.read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

-- Write to a temp file and rename it over the target, so a crash or a
-- concurrent reader never sees a half-written file.
function M.write_atomic(path, content)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local tmp = string.format("%s.%d.tmp", path, uv.os_getpid())
	local f, err = io.open(tmp, "wb")
	if not f then
		return false, err
	end
	f:write(content)
	f:close()
	local ok, rename_err = uv.fs_rename(tmp, path)
	if not ok then
		os.remove(tmp)
		return false, rename_err
	end
	return true
end

-- Run fn while holding a lock directory next to `path` (mkdir is atomic).
-- A lock older than 10 seconds is treated as left over from a crash.
function M.with_lock(path, fn)
	local lock = path .. ".lock"
	vim.fn.mkdir(vim.fs.dirname(lock), "p")
	for _ = 1, 100 do
		if uv.fs_mkdir(lock, 448) then
			local ok, a, b = pcall(fn)
			uv.fs_rmdir(lock)
			if not ok then
				error(a)
			end
			return a, b
		end
		local stat = uv.fs_stat(lock)
		if stat and os.time() - stat.mtime.sec > 10 then
			uv.fs_rmdir(lock)
		else
			uv.sleep(20)
		end
	end
	return false, "could not acquire lock " .. lock
end

return M
