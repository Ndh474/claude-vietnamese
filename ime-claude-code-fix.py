#!/usr/bin/env python3
"""
Claude Code Vietnamese IME Fix (EXE only)

Fixes Vietnamese typing issues in Claude Code CLI (EVKey, UniKey, OpenKey, etc.)
Supports: claude.exe binary only (no npm)
"""

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

try:
    import psutil
except ImportError:
    psutil = None

# =============================================================================
# Constants
# =============================================================================

EXE_PATCH_MARKER = "/*PHTV_EXE*/"

# Each pattern entry:
#   - "version": human label
#   - "old": exact string found in the original binary
#   - "new": replacement string (must be <= len(old); script pads with spaces)
#
# To add support for a new version, append a new entry here.
# Use the debugging guide in README.md to find the new pattern.

EXE_PATTERNS = [
    {
        "version": "v2.1.41",
        "old": 'if(!HH.backspace&&!HH.delete&&$H.includes("\\x7F")){let fH=($H.match(/\\x7f/g)||[]).length,YH=h;for(let FH=0;FH<fH;FH++)YH=YH.deleteTokenBefore()??YH.backspace();if(!h.equals(YH)){if(h.text!==YH.text)$(YH.text);O(YH.offset)}iRH(),nRH();return}',
        "new": 'if(!HH.backspace&&!HH.delete&&$H.includes("\\x7F")){let YH=h;for(let FH of $H)YH="\\x08\\x7f".includes(FH)?YH.deleteTokenBefore()??YH.backspace():YH.insert(FH);if(!h.equals(YH)){$(YH.text);O(YH.offset)}/*PHTV_EXE*/iRH(),nRH();return}',
    },
    {
        "version": "v2.1.39",
        "old": 'if(!MH.backspace&&!MH.delete&&s.includes("\\x7F")){let UH=(s.match(/\\x7f/g)||[]).length,FH=h;for(let ZH=0;ZH<UH;ZH++)FH=FH.deleteTokenBefore()??FH.backspace();if(!h.equals(FH)){if(h.text!==FH.text)$(FH.text);O(FH.offset)}TRH(),QRH();return}',
        "new": 'if(!MH.backspace&&!MH.delete&&s.includes("\\x7F")){let FH=h;for(let ZH of s)FH="\\x08\\x7f".includes(ZH)?FH.deleteTokenBefore()??FH.backspace():FH.insert(ZH);if(!h.equals(FH)){$(FH.text);O(FH.offset)}/*PHTV_EXE*/TRH(),QRH();return}',
    },
    {
        "version": "v2.1.38",
        "old": 'if(!XH.backspace&&!XH.delete&&s.includes("\\x7F")){let UH=(s.match(/\\x7f/g)||[]).length,GH=h;for(let YH=0;YH<UH;YH++)GH=GH.deleteTokenBefore()??GH.backspace();if(!h.equals(GH)){if(h.text!==GH.text)$(GH.text);O(GH.offset)}IRH(),fRH();return}',
        "new": 'if(!XH.backspace&&!XH.delete&&s.includes("\\x7F")){let GH=h;for(let YH of s)GH="\\x08\\x7f".includes(YH)?GH.deleteTokenBefore()??GH.backspace():GH.insert(YH);if(!h.equals(GH)){$(GH.text);O(GH.offset)}/*PHTV_EXE*/IRH(),fRH();return}',
    },
]

# Generic regex to auto-detect unknown versions
# Matches the buggy pattern structure regardless of variable names
GENERIC_OLD_RE = re.compile(
    r'if\(!([A-Za-z$_]\w*)\.backspace&&!\1\.delete&&([A-Za-z$_]\w*)\.includes\("\\x7F"\)\)'
    r'\{let \w+=\(\2\.match\(/\\x7f/g\)\|\|\[\]\)\.length,(\w+)=h;'
    r'for\(let (\w+)=0;\4<\w+;\4\+\+\)\3=\3\.deleteTokenBefore\(\)\?\?\3\.backspace\(\);'
    r'if\(!h\.equals\(\3\)\)\{if\(h\.text!==\3\.text\)\$\(\3\.text\);O\(\3\.offset\)\}'
    r'(\w+\(\),\w+\(\));return\}'
)


# =============================================================================
# Console output helpers
# =============================================================================

class Colors:
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    RESET = "\033[0m"


def print_color(text: str, color: str = Colors.RESET, end: str = "\n"):
    print(f"{color}{text}{Colors.RESET}", end=end)


def print_header():
    print()
    print_color("=" * 60, Colors.CYAN)
    print_color("  Claude Code Vietnamese IME Fix (EXE only)", Colors.CYAN)
    print_color("  Fix Vietnamese typing issues in Claude Code CLI", Colors.CYAN)
    print_color("=" * 60, Colors.CYAN)
    print()


# =============================================================================
# Process management
# =============================================================================

def get_claude_processes() -> list:
    """Find all running Claude Code processes."""
    if psutil is None:
        return []

    processes = []
    for proc in psutil.process_iter(["pid", "name", "cmdline"]):
        try:
            name = proc.info["name"].lower()
            if name == "claude.exe" or name == "claude":
                processes.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    return processes


def stop_claude_processes(force: bool = False) -> bool:
    """Stop all Claude Code processes with user confirmation."""
    processes = get_claude_processes()

    if not processes:
        return True

    print()
    print_color("! Detected running Claude Code processes:", Colors.YELLOW)
    for proc in processes:
        print(f"   - {proc.info['name']} (PID: {proc.pid})")
    print()

    if not force:
        print_color("? This action will CLOSE ALL running Claude Code sessions.", Colors.YELLOW)
        print_color("  Any unsaved work will be lost!", Colors.RED)
        print()
        confirm = input("  Do you want to continue? (y/N): ").strip().lower()

        if confirm != "y":
            print_color("-> Cancelled. Please close Claude Code manually and try again.", Colors.CYAN)
            return False

    print_color("-> Closing Claude Code processes...", Colors.YELLOW)
    for proc in processes:
        try:
            proc.terminate()
            proc.wait(timeout=3)
            print(f"   Closed: {proc.info['name']} (PID: {proc.pid})")
        except Exception:
            try:
                proc.kill()
                print(f"   Force killed: {proc.info['name']} (PID: {proc.pid})")
            except Exception:
                print_color(f"   Failed to close: {proc.info['name']} (PID: {proc.pid})", Colors.RED)

    # Verify
    remaining = get_claude_processes()
    if remaining:
        print_color("X Some Claude processes are still running. Please close them manually.", Colors.RED)
        return False

    print_color("   All Claude Code processes closed.", Colors.GREEN)
    return True


# =============================================================================
# Claude EXE detection
# =============================================================================

def find_claude_exe() -> Path | None:
    """Find claude.exe binary. Checks PATH first, then common locations."""
    # 1. Check PATH
    result = shutil.which("claude")
    if result:
        p = Path(result)
        if p.suffix.lower() == ".exe" and p.exists():
            return p

    # 2. Common install locations
    home = Path.home()
    candidates = [
        home / ".local" / "bin" / "claude.exe",
        home / "AppData" / "Local" / "Programs" / "claude" / "claude.exe",
        home / "AppData" / "Local" / "claude" / "claude.exe",
        Path("C:/Program Files/Claude/claude.exe"),
        Path("C:/Program Files (x86)/Claude/claude.exe"),
    ]

    for path in candidates:
        if path.exists():
            return path

    return None


def get_claude_version() -> str:
    """Get Claude Code version."""
    try:
        result = subprocess.run(["claude", "--version"], capture_output=True, text=True, timeout=10)
        return result.stdout.strip().split("\n")[0] if result.returncode == 0 else "unknown"
    except Exception:
        return "unknown"


# =============================================================================
# Patch detection
# =============================================================================

def is_exe_patched(path: Path) -> bool:
    """Check if exe is already patched."""
    content = path.read_bytes().decode("latin-1")
    return EXE_PATCH_MARKER in content


# =============================================================================
# Generic pattern detection for unknown versions
# =============================================================================

def try_generic_patch(content: str) -> tuple[str, str, str] | None:
    """
    Try to find and build a patch for an unknown version using regex.
    Returns (old_block, new_block, version_label) or None.
    """
    match = GENERIC_OLD_RE.search(content)
    if not match:
        return None

    old_block = match.group(0)
    # Extract variable names from the match
    guard_var = match.group(1)   # e.g. HH
    input_var = match.group(2)   # e.g. $H
    cursor_var = match.group(3)  # e.g. YH
    loop_var = match.group(4)    # e.g. FH
    tail_calls = match.group(5)  # e.g. iRH(),nRH()

    # Build replacement: iterate chars instead of counting deletes
    inner = let_block(cursor_var, loop_var, input_var, tail_calls)
    new_block = (
        f'if(!{guard_var}.backspace&&!{guard_var}.delete&&{input_var}.includes("\\x7F"))'
        f'{{{inner}}}'
    )

    if len(new_block) > len(old_block):
        return None  # can't fit

    return (old_block, new_block, "auto-detected")


def let_block(cursor_var: str, loop_var: str, input_var: str, tail_calls: str) -> str:
    """Build the inner let block for the fix."""
    return (
        f'let {cursor_var}=h;'
        f'for(let {loop_var} of {input_var})'
        f'{cursor_var}="\\x08\\x7f".includes({loop_var})?'
        f'{cursor_var}.deleteTokenBefore()??{cursor_var}.backspace():'
        f'{cursor_var}.insert({loop_var});'
        f'if(!h.equals({cursor_var}))'
        f'{{$({cursor_var}.text);O({cursor_var}.offset)}}'
        f'{EXE_PATCH_MARKER}{tail_calls};return'
    )


# =============================================================================
# Patching
# =============================================================================

def create_backup(path: Path) -> Path:
    """Create timestamped backup."""
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = path.with_suffix(f"{path.suffix}.backup-{timestamp}")
    shutil.copy2(path, backup_path)
    return backup_path


def patch_exe(path: Path) -> bool:
    """Patch exe file."""
    content = path.read_bytes().decode("latin-1")

    # Check already patched
    total_old = sum(content.count(p["old"]) for p in EXE_PATTERNS)
    marker_count = content.count(EXE_PATCH_MARKER)

    if total_old == 0 and marker_count > 0:
        print_color("   Already patched.", Colors.GREEN)
        return True

    # Try known patterns first
    patched_content = content
    matched = []

    for pattern in EXE_PATTERNS:
        if len(pattern["new"]) > len(pattern["old"]):
            print_color(f"X Internal error: patch payload longer than original ({pattern['version']}).", Colors.RED)
            return False

        count = patched_content.count(pattern["old"])
        if count == 0:
            continue

        new_block = pattern["new"] + " " * (len(pattern["old"]) - len(pattern["new"]))
        patched_content = patched_content.replace(pattern["old"], new_block)
        matched.append(f"{pattern['version']}:{count}")

    # If no known patterns matched, try generic detection
    if not matched:
        result = try_generic_patch(content)
        if result:
            old_block, new_block, version_label = result
            count = content.count(old_block)
            if count > 0:
                padded = new_block + " " * (len(old_block) - len(new_block))
                patched_content = patched_content.replace(old_block, padded)
                matched.append(f"{version_label}:{count}")
                print_color(f"   Auto-detected new pattern ({count} occurrence(s))", Colors.YELLOW)

    if not matched:
        print_color("   Pattern not found in binary.", Colors.RED)
        print("   Code structure may have changed in newer version.")
        print("   See README.md 'Debugging New Versions' for how to update patterns.")
        return False

    # Create backup before writing
    print_color("-> Creating backup...", Colors.YELLOW)
    backup_path = create_backup(path)
    print(f"   Backup: {backup_path}")

    print_color("-> Applying binary patch...", Colors.YELLOW)

    # Write
    path.write_bytes(patched_content.encode("latin-1"))

    # Verify
    verify_content = path.read_bytes().decode("latin-1")
    remaining_old = sum(verify_content.count(p["old"]) for p in EXE_PATTERNS)
    # Also check generic
    if GENERIC_OLD_RE.search(verify_content):
        remaining_old += 1
    new_marker_count = verify_content.count(EXE_PATCH_MARKER)

    if remaining_old == 0 and new_marker_count > 0:
        print(f"   Patched block(s): {', '.join(matched)}")
        return True

    print_color("-> Patch failed, restoring...", Colors.YELLOW)
    shutil.copy2(backup_path, path)
    return False


# =============================================================================
# Restore
# =============================================================================

def find_latest_backup(path: Path) -> Path | None:
    """Find the latest backup file."""
    pattern = f"{path.name}.backup-*"
    backups = sorted(path.parent.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return backups[0] if backups else None


def restore(path: Path) -> bool:
    """Restore from backup."""
    backup = find_latest_backup(path)

    if not backup:
        print_color("X Backup file not found.", Colors.RED)
        print("  You can reinstall Claude Code to restore the original binary.")
        return False

    print_color("-> Restoring from backup...", Colors.YELLOW)
    print(f"   Backup: {backup}")

    shutil.copy2(backup, path)
    backup.unlink()

    print_color("OK Claude Code restored to original.", Colors.GREEN)
    return True


# =============================================================================
# Health check
# =============================================================================

def show_check(path: Path):
    """Show detailed health check."""
    print_color("-> Running health-check...", Colors.YELLOW)
    print()

    stat = path.stat()
    print(f"   Last write: {datetime.fromtimestamp(stat.st_mtime)}")
    print(f"   File size:  {stat.st_size:,} bytes")

    content = path.read_bytes().decode("latin-1")
    marker_count = content.count(EXE_PATCH_MARKER)
    old_count = sum(content.count(p["old"]) for p in EXE_PATTERNS)

    # Also check generic (only count matches NOT already covered by known patterns)
    generic_old = 0
    for m in GENERIC_OLD_RE.finditer(content):
        if not any(m.group(0) == p["old"] for p in EXE_PATTERNS):
            generic_old += 1

    total_old = old_count + generic_old
    is_patched = marker_count > 0 and total_old == 0
    has_bug = total_old > 0
    can_patch = not is_patched and has_bug

    print("   Status:     ", end="")
    print_color("PATCHED" if is_patched else "NOT PATCHED", Colors.GREEN if is_patched else Colors.RED)

    print("   Bug code:   ", end="")
    if has_bug:
        detail = f"Present (known: {old_count}, generic: {generic_old})"
        print_color(detail, Colors.YELLOW)
    else:
        print_color("Not found", Colors.CYAN)

    print("   Can patch:  ", end="")
    print_color("YES" if can_patch else "NO", Colors.GREEN if can_patch else Colors.YELLOW)

    print(f"   Marker cnt: {marker_count}")
    print(f"   Old cnt:    {old_count} (known) + {generic_old} (generic)")

    # Write access
    try:
        test_file = path.parent / f".write_test_{datetime.now().timestamp()}"
        test_file.write_text("test")
        test_file.unlink()
        print("   Write access:", end="")
        print_color(" OK", Colors.GREEN)
    except Exception as e:
        print("   Write access:", end="")
        print_color(" DENIED", Colors.RED)
        print(f"   Write error: {e}")

    # Backups
    pattern = f"{path.name}.backup-*"
    backups = sorted(path.parent.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    print(f"   Backups:    {len(backups)}")
    if backups:
        print(f"   Latest:     {backups[0].name}")

    # SHA256
    sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"   SHA256:     {sha256}")

    # Version
    print(f"   Version:    {get_claude_version()}")

    # Smoke test
    try:
        result = subprocess.run(["claude", "--help"], capture_output=True, timeout=10)
        smoke_ok = result.returncode == 0 and result.stdout
    except Exception:
        smoke_ok = False

    print("   Smoke test (--help):", end="")
    print_color(" OK" if smoke_ok else " FAIL", Colors.GREEN if smoke_ok else Colors.RED)


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Claude Code Vietnamese IME Fix (EXE only)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Actions:
  patch   - Apply the Vietnamese IME fix (default)
  restore - Restore original from backup
  check   - Show detailed health check
        """,
    )
    parser.add_argument("action", nargs="?", default="patch", choices=["patch", "restore", "check"])
    args = parser.parse_args()

    print_header()

    # Check psutil
    if psutil is None:
        print_color("! Warning: psutil not installed. Process detection disabled.", Colors.YELLOW)
        print("  Install with: pip install psutil")
        print()

    # Find claude.exe
    print_color("-> Searching for claude.exe...", Colors.YELLOW)

    path = find_claude_exe()
    if not path:
        print_color("X claude.exe not found.", Colors.RED)
        print("  Please install Claude Code or check your PATH.")
        print("  Expected locations:")
        print(f"    - {Path.home() / '.local' / 'bin' / 'claude.exe'}")
        print(f"    - PATH: {shutil.which('claude') or 'not found'}")
        return 1

    print_color(f"   Path: {path}", Colors.CYAN)
    print_color(f"   Version: {get_claude_version()}", Colors.CYAN)
    print()

    # Execute action
    if args.action == "check":
        show_check(path)
        return 0

    elif args.action == "patch":
        if is_exe_patched(path):
            print_color("OK claude.exe is already patched.", Colors.GREEN)
            return 0

        # Stop running processes
        if psutil and get_claude_processes():
            if not stop_claude_processes():
                return 1
            print()

        # Apply patch
        success = patch_exe(path)

        if success:
            print()
            print_color("=" * 60, Colors.GREEN)
            print_color("  OK Patch successful! Vietnamese IME fix has been applied.", Colors.GREEN)
            print_color("=" * 60, Colors.GREEN)
            print()
            print("Please ", end="")
            print_color("restart Claude Code", Colors.YELLOW, end="")
            print(" to apply changes.")
            return 0
        else:
            print()
            print_color("X Failed to apply patch.", Colors.RED)
            return 1

    elif args.action == "restore":
        if not is_exe_patched(path):
            print_color("claude.exe is not patched.", Colors.YELLOW)
            return 0

        # Stop running processes
        if psutil and get_claude_processes():
            if not stop_claude_processes():
                return 1
            print()

        restore(path)
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
