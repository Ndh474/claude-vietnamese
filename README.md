# Claude Code Vietnamese IME Fix (EXE only)

Fixes Vietnamese typing issues in Claude Code CLI (EVKey, UniKey, OpenKey, etc.).

Supports: `claude.exe` binary only (no npm required).

## Problem

Vietnamese IMEs send DEL (`0x7F`) to delete the previous character, then insert the new accented character.
In affected Claude Code builds, the DEL/backspace part is handled, but replacement text is not inserted correctly.

## Usage

### Apply patch

```powershell
python ime-claude-code-fix.py
# or
python ime-claude-code-fix.py patch
```

### Detailed health check

```powershell
python ime-claude-code-fix.py check
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

```powershell
python ime-claude-code-fix.py restore
```

## How It Works

- The script patches `claude.exe` directly using known binary string patterns.
- If no known pattern matches, it uses a generic regex to auto-detect the buggy block.
- A backup is created before patch:
  - `claude.exe.backup-<timestamp>`
- If you need to revert:
  - `python ime-claude-code-fix.py restore`

## After Patching

Restart Claude Code.

## After Updating Claude Code

Run patch again after each update:

```powershell
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

```powershell
Get-Command claude | Select-Object Name,Source,CommandType
```

### 2. Run built-in diagnostics first

```powershell
python ime-claude-code-fix.py check
```

If patch status is not patched and bug pattern is not found (both known and generic = 0),
your version likely changed the internal structure significantly.

### 3. Find new IME handling block

The script has a **generic regex** that can auto-detect most minified variable name changes.
If even the generic detection fails, search for the pattern manually:

```powershell
$exe = "<path-to-claude.exe>"
$content = [System.IO.File]::ReadAllText($exe, [System.Text.Encoding]::GetEncoding("iso-8859-1"))
# Search for the buggy pattern structure
$idx = $content.IndexOf('backspace&&!')
# Extract surrounding context
$content.Substring([Math]::Max(0, $idx - 100), 500)
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

If check shows write access denied, run patch from an elevated shell.

## Fix Logic (Summary)

Original buggy logic deletes old characters and returns too early.
Patch replays IME input as an ordered stream (delete/insert by event order) before returning.

## Version History

| Script version | Claude Code | Date       |
| -------------- | ----------- | ---------- |
| 3.0            | v2.1.41     | 2026-02-13 |
| 2.1            | v2.1.39     | 2026-02-11 |
| 2.0            | v2.1.38     | 2026-02-10 |
| 1.1            | v2.1.11     | 2026-01-17 |
| 1.0            | v2.1.9      | 2026-01-16 |
