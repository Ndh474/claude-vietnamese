# Claude Code Vietnamese IME Fix

Fixes Vietnamese typing issues in Claude Code CLI (EVKey, UniKey, OpenKey, etc.).

Supported install types:
- npm package install (`cli.js`)
- binary install (`claude.exe`)

## Problem

Vietnamese IMEs send DEL (`0x7F`) to delete the previous character, then insert the new accented character.
In affected Claude Code builds, the DEL/backspace part is handled, but replacement text is not inserted correctly.

## Usage

### Apply patch

```powershell
.\ime-claude-code-fix.ps1
# or
.\ime-claude-code-fix.ps1 patch
```

### Detailed health check

```powershell
.\ime-claude-code-fix.ps1 check
```

`check` reports:
- patch status (`DA PATCH` / `CHUA PATCH`)
- whether vulnerable bug pattern still exists
- whether patch can be applied now
- write access to install directory
- backup count and latest backup
- SHA256 of current target file
- Claude Code version
- smoke test (`claude --help`)

### Restore original build

```powershell
.\ime-claude-code-fix.ps1 restore
```

## Notes For `claude.exe`

- The script patches `claude.exe` directly using known binary string patterns.
- A backup is created before patch:
  - `claude.exe.backup-<timestamp>`
- If you need to revert:
  - `.\ime-claude-code-fix.ps1 restore`

## After Patching

Restart Claude Code.

## After Updating Claude Code

Run patch again after each update:

```powershell
.\ime-claude-code-fix.ps1 check
.\ime-claude-code-fix.ps1 patch
.\ime-claude-code-fix.ps1 check
```

## Is It Safe To Run Multiple Times?

Yes.

- `patch` is idempotent: if marker already exists, it will skip and not patch again.
- `restore` uses the latest backup file and returns to original binary/source.
- Running `check` repeatedly is safe.

If `check` shows already patched, running `patch` again should not break Claude.

## Debugging New Versions (Pattern Moved / Changed)

If a new Claude version changes the code location or minified symbols, follow this flow.

### 1. Confirm target type and path

```powershell
Get-Command claude | Select-Object Name,Source,CommandType
```

- `claude.exe` => binary flow
- `.cmd/.ps1` wrapper + npm modules => `cli.js` flow

### 2. Run built-in diagnostics first

```powershell
.\ime-claude-code-fix.ps1 check
```

If patch status is not patched and bug pattern is not found, your version likely changed internals.

### 3. For npm (`cli.js`): find new IME handling block

Find candidate areas:

```powershell
$cli = "<path-to-cli.js>"
rg -n "backspace\\(|\\\\x7f|includes\\(\" $cli
```

Look for logic that:
- counts or matches `\x7f`
- performs backspace/delete operations
- returns early before inserting replacement text

Then update the `altPatterns` entries in `ime-claude-code-fix.ps1`:
- `Search`
- variable mappings (`Var`, `Input`, `Cursor`, `SetOffset`)

### 4. For binary (`claude.exe`): verify known old block still exists

```powershell
.\ime-claude-code-fix.ps1 check
```

Focus on:
- `Old cnt`
- `Marker cnt`

If `Old cnt` is `0` and `Marker cnt` is `0`, binary pattern changed.
You must update these constants in `ime-claude-code-fix.ps1`:
- `$EXE_OLD_BLOCK`
- `$EXE_NEW_CORE`

Important:
- `EXE_NEW_CORE.Length` must be less than or equal to `EXE_OLD_BLOCK.Length`
- script pads replacement to keep binary size stable

### 5. Safe test workflow before touching real install

1. Copy target file to a test file.
2. Patch test file first.
3. Verify it runs (`--version`, `--help`).
4. Patch real file only after test success.

Example smoke tests:

```powershell
claude --version
claude --help
```

### 6. Permission issues

If check shows write access denied, run patch from an elevated shell or allow elevated execution when prompted.

## Fix Logic (Summary)

Original buggy logic deletes old characters and returns too early.
Patch replays IME input as an ordered stream (delete/insert by event order) before returning.

## Version History

| Script version | Claude Code | Date       |
| -------------- | ----------- | ---------- |
| 2.1            | v2.1.39     | 2026-02-11 |
| 2.0            | v2.1.38     | 2026-02-10 |
| 1.1            | v2.1.11     | 2026-01-17 |
| 1.0            | v2.1.9      | 2026-01-16 |
