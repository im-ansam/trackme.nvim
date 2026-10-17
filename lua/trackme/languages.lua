local config = require("trackme.config")

local M = {}

-- Neovim filetype -> VS Code language id, so counts line up with data
-- written by the TrackMe VS Code extension. Filetypes not listed here are
-- used as-is (most are already the same: python, lua, typescript, ...).
local vscode_ids = {
	[""] = "plaintext",
	text = "plaintext",
	sh = "shellscript",
	bash = "shellscript",
	zsh = "shellscript",
	cs = "csharp",
	objc = "objective-c",
	objcpp = "objective-cpp",
	make = "makefile",
	jproperties = "properties",
	tex = "latex",
	plaintex = "latex",
	gitconfig = "git-config",
	ps1 = "powershell",
	dosbatch = "bat",
	sshconfig = "ssh_config",
}

function M.name(filetype)
	return config.options.languages[filetype] or vscode_ids[filetype] or filetype
end

return M
