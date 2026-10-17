# trackme.nvim

Counts the lines of code you **type by hand** in Neovim, per language, per day
and per month. Pasted, generated and repeated text doesn't count, and a line
is only ever counted once.

The data is stored in the same format as the TrackMe VS Code extension, so
both editors can feed the same numbers.

## What counts

A line counts once, when it has at least one non-whitespace character that you
typed, and you leave the line, leave insert mode or save.

| Action | Counted? |
|---|---|
| Typing a new line | Yes, once |
| Typing more on a line that was already counted | No |
| Typing on an existing line that was never counted (e.g. a pasted line) | Yes, once |
| Pasting (terminal paste, `p`, `P`, `<C-r>` register insert) | No |
| Macros (`@q`), `.` repeat, count repeats (`3ihi`) | No |
| Completion or snippet text | No (the characters you typed before accepting still count the line) |
| Blank or whitespace-only lines | No |
| Deleting a counted line and typing the same text again | No |
| Undo / redo | No |
| Lines reformatted by a formatter (`x=1` → `x = 1`) | Stay counted, not counted again |
| Reopening a file later and typing on lines counted before | No |
| Terminal, help, git commit, neo-tree and other special buffers | Not tracked |

How typed keys are told apart from replayed text: real keystrokes arrive
milliseconds apart, while pastes, registers and repeats are processed
microseconds apart. If Neovim freezes while you type (a slow LSP, for
example), keys typed during the freeze can be treated as pasted; a line only
needs one typed character to count, so this rarely matters.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "im-ansam/trackme.nvim",
  lazy = false,
  opts = {},
}
```

Requires Neovim 0.11 or later.

## Usage

| Command | |
|---|---|
| `:TrackMe` | Show today, this week and this month by language (`y` copies the summary, `q` closes) |
| `:TrackMe flush` | Write pending counts to disk now (also done every minute and on exit) |
| `:TrackMe debug` | Toggle gutter signs: `+` counted line, `~` line being typed |

## Configuration

Defaults:

```lua
require("trackme").setup({
  -- Daily and monthly counts (base64-encoded JSON, VS Code TrackMe format)
  data_dir = vim.fn.stdpath("data") .. "/trackme",
  -- Fingerprints (SHA-256, never the code itself) of counted lines per file
  history_file = vim.fn.stdpath("state") .. "/trackme/history.json",
  -- How often pending counts are written (ms)
  flush_interval = 60 * 1000,
  -- Filetypes that are never tracked
  exclude_filetypes = { "gitcommit", "gitrebase", "help", "lazy", "mason", "neo-tree", "TelescopePrompt", "toggleterm" },
  -- Extra filetype -> language name mappings
  languages = {},
})
```

Filetypes are saved under VS Code's language names where they differ
(`sh`/`bash`/`zsh` → `shellscript`, `text` → `plaintext`, `cs` → `csharp`, …).

## Data format

`daily-progress-tracker.json.b64` and `monthly-progress-tracker.json.b64` in
`data_dir` contain base64-encoded JSON:

```json
{
    "10/17/2026": {
        "lines_of_code": {
            "total": 42,
            "python": 30,
            "lua": 12
        }
    }
}
```

Daily keys are `MM/DD/YYYY`, monthly keys are `YYYY-Mon` (e.g. `2026-Oct`).
Files are re-read and updated under a lock before every write, so several
Neovim instances can write to them at once.

## License

MIT
