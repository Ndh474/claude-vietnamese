# Claude Code Vietnamese IME Fix

Fixes Vietnamese typing issues in Claude Code CLI (EVKey, UniKey, OpenKey, etc.).

Supports: `claude.exe` (Windows) and `claude` (Linux) binaries (no npm required).

## Problem

Vietnamese IMEs send DEL (`0x7F`) to delete the previous character, then insert the new accented character.
In affected Claude Code builds, the DEL/backspace part is handled, but replacement text is not inserted correctly.

## Usage

### Apply patch

```bash
# Windows (PowerShell)
python ime-claude-code-fix.py
python ime-claude-code-fix.py patch

# Linux
python3 ime-claude-code-fix.py
python3 ime-claude-code-fix.py patch
# If permission denied:
sudo python3 ime-claude-code-fix.py patch
```

### Detailed health check

```bash
python ime-claude-code-fix.py check  # or python3 on Linux
```

`check` reports:

- patch status (`PATCHED` / `NOT PATCHED`)
- whether vulnerable bug pattern still exists
- whether patch can be applied now
- write access to install directory
- backup count and latest backup
- SHA256 of current target file
- Claude Code version
- smoke test (`claude --help`)

### Restore original build

```bash
python ime-claude-code-fix.py restore  # or python3 on Linux
```

## How It Works

- The script auto-detects the OS and searches for the correct binary.
- It patches the claude binary directly using known string patterns.
- If no known pattern matches, it uses a generic regex to auto-detect the buggy block.
- A backup is created before patch:
  - Windows: `claude.exe.backup-<timestamp>`
  - Linux: `claude.backup-<timestamp>`
- If you need to revert:
  - `python ime-claude-code-fix.py restore`

## After Patching

Restart Claude Code.

## After Updating Claude Code

Run patch again after each update:

```bash
python ime-claude-code-fix.py check
python ime-claude-code-fix.py patch
python ime-claude-code-fix.py check
```

## Is It Safe To Run Multiple Times?

Yes.

- `patch` is idempotent: if marker already exists, it will skip and not patch again.
- `restore` uses the latest backup file and returns to original binary.
- Running `check` repeatedly is safe.

If `check` shows already patched, running `patch` again should not break Claude.

## Debugging New Versions (Pattern Moved / Changed)

If a new Claude version changes the code location or minified symbols, follow this flow.

### 1. Confirm target path

```bash
# Windows (PowerShell)
Get-Command claude | Select-Object Name,Source,CommandType

# Linux
which claude
file $(which claude)
```

### 2. Run built-in diagnostics first

```bash
python ime-claude-code-fix.py check  # or python3 on Linux
```

If patch status is not patched and bug pattern is not found (both known and generic = 0),
your version likely changed the internal structure significantly.

### 3. Find new IME handling block

The script has a **generic regex** that can auto-detect most minified variable name changes.
If even the generic detection fails, search for the pattern manually:

```bash
# Windows (PowerShell)
$exe = "<path-to-claude.exe>"
$content = [System.IO.File]::ReadAllText($exe, [System.Text.Encoding]::GetEncoding("iso-8859-1"))
$idx = $content.IndexOf('backspace&&!')
$content.Substring([Math]::Max(0, $idx - 100), 500)

# Linux
exe="$(which claude)"
strings "$exe" | grep -A2 'backspace&&!'
# or for full context:
python3 -c "
import sys
c = open('$exe','rb').read().decode('latin-1')
i = c.find('backspace&&!')
print(c[max(0,i-100):i+400])
"
```

Look for logic that:

- counts or matches `\x7f`
- performs backspace/delete operations
- returns early before inserting replacement text

Then add a new entry to the `EXE_PATTERNS` list in `ime-claude-code-fix.py`.

Important:

- `new` length must be ≤ `old` length
- Script pads replacement with spaces to keep binary size stable

### 4. Safe test workflow

1. Copy `claude.exe` to a test file.
2. Patch test file first.
3. Verify it runs (`--version`, `--help`).
4. Patch real file only after test success.

### 5. Permission issues

If check shows write access denied:

- **Windows**: Run patch from an elevated shell (Run as Administrator).
- **Linux**: Use `sudo python3 ime-claude-code-fix.py patch`.

## Fix Logic (Summary)

Original buggy logic deletes old characters and returns too early.
Patch replays IME input as an ordered stream (delete/insert by event order) before returning.

## Version History

| Script version | Claude Code | Date       |
| -------------- | ----------- | ---------- |
| 5.0            | v2.1.71     | 2026-03-08 |
| 4.0            | v2.1.49     | 2026-02-20 |
| 3.0            | v2.1.41     | 2026-02-13 |
| 2.1            | v2.1.39     | 2026-02-11 |
| 2.0            | v2.1.38     | 2026-02-10 |
| 1.1            | v2.1.11     | 2026-01-17 |
| 1.0            | v2.1.9      | 2026-01-16 |
