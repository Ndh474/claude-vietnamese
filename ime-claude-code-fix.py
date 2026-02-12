#!/usr/bin/env python3
"""
Claude Code Vietnamese IME Fix

Fixes Vietnamese typing issues in Claude Code CLI (EVKey, UniKey, OpenKey, etc.)
Supports: npm package (cli.js) and binary (claude.exe)
"""

import argparse
import hashlib
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

PATCH_MARKER = "/* PHTV Vietnamese IME fix */"
EXE_PATCH_MARKER = "/*PHTV_EXE*/"

EXE_PATTERNS = [
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

CLI_PATTERNS = [
    {"search": "T(CA.offset)}Qe1(),Be1();return}", "var": "CA", "input": "l", "cursor": "S", "set_offset": "T", "version": "v2.1.11"},
    {"search": "j(_A.offset)}Oe1(),Me1();return}", "var": "_A", "input": "n", "cursor": "P", "set_offset": "j", "version": "v2.1.9"},
    {"search": "_(FA.offset)}", "var": "FA", "input": "s", "cursor": "j", "set_offset": "_", "version": "v2.1.7"},
    {"search": "_(EA.offset)}", "var": "EA", "input": "s", "cursor": "j", "set_offset": "_", "version": "older"},
]


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
    print_color("  Claude Code Vietnamese IME Fix - v2.1.9+", Colors.CYAN)
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
            cmdline = " ".join(proc.info["cmdline"] or []).lower()
            
            if name == "claude.exe" or name == "claude":
                processes.append(proc)
            elif name in ("node.exe", "node") and ("claude-code" in cmdline or "@anthropic-ai" in cmdline):
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
# Claude Code detection
# =============================================================================

def find_claude_command() -> Path | None:
    """Find claude command path."""
    result = shutil.which("claude")
    return Path(result) if result else None


def find_cli_js() -> Path | None:
    """Find cli.js for npm installation."""
    claude_cmd = find_claude_command()
    
    if claude_cmd and claude_cmd.suffix in (".cmd", ".bat", ".ps1"):
        npm_path = claude_cmd.parent / "node_modules" / "@anthropic-ai" / "claude-code" / "cli.js"
        if npm_path.exists():
            return npm_path
    
    # Try npm root -g
    try:
        result = subprocess.run(["npm", "root", "-g"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            npm_root = Path(result.stdout.strip())
            cli_path = npm_root / "@anthropic-ai" / "claude-code" / "cli.js"
            if cli_path.exists():
                return cli_path
    except Exception:
        pass
    
    # Common paths on Windows
    common_paths = [
        Path.home() / "AppData" / "Roaming" / "npm" / "node_modules" / "@anthropic-ai" / "claude-code" / "cli.js",
        Path.home() / "AppData" / "Local" / "npm" / "node_modules" / "@anthropic-ai" / "claude-code" / "cli.js",
    ]
    
    for path in common_paths:
        if path.exists():
            return path
    
    return None


def find_claude_exe() -> Path | None:
    """Find claude.exe for binary installation."""
    claude_cmd = find_claude_command()
    if claude_cmd and claude_cmd.suffix.lower() == ".exe" and claude_cmd.exists():
        return claude_cmd
    return None


def find_target() -> tuple[str, Path] | None:
    """Find Claude Code installation target."""
    cli_path = find_cli_js()
    if cli_path:
        return ("cli.js", cli_path)
    
    exe_path = find_claude_exe()
    if exe_path:
        return ("exe", exe_path)
    
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

def is_cli_patched(path: Path) -> bool:
    """Check if cli.js is already patched."""
    content = path.read_text(encoding="utf-8")
    return PATCH_MARKER in content


def is_exe_patched(path: Path) -> bool:
    """Check if exe is already patched."""
    content = path.read_bytes().decode("latin-1")
    return EXE_PATCH_MARKER in content


# =============================================================================
# Patching
# =============================================================================

def create_backup(path: Path) -> Path:
    """Create timestamped backup."""
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = path.with_suffix(f"{path.suffix}.backup-{timestamp}")
    shutil.copy2(path, backup_path)
    return backup_path


def patch_cli(path: Path) -> bool:
    """Patch cli.js file."""
    print_color("-> Creating backup...", Colors.YELLOW)
    backup_path = create_backup(path)
    print(f"   Backup: {backup_path}")
    
    print_color("-> Analyzing and applying patch...", Colors.YELLOW)
    
    content = path.read_text(encoding="utf-8")
    
    if PATCH_MARKER in content:
        print_color("   Already patched.", Colors.GREEN)
        return True
    
    for pattern in CLI_PATTERNS:
        idx = content.find(pattern["search"])
        if idx == -1:
            continue
        
        # Check context
        start_ctx = max(0, idx - 500)
        context = content[start_ctx:idx]
        
        if "backspace()" in context and ("\\x7f" in context or ".includes(" in context):
            print(f"   Found pattern {pattern['version']}")
            
            # Build fix code
            cursor = pattern["cursor"]
            input_var = pattern["input"]
            set_offset = pattern["set_offset"]
            
            fix_code = (
                f'{PATCH_MARKER}let _phtv_seq={cursor};'
                f'for(const _c of {input_var}){{_phtv_seq=(_c==="\\x7f"||_c==="\\x08")?_phtv_seq.backspace():_phtv_seq.insert(_c)}}'
                f'if(!{cursor}.equals(_phtv_seq)){{if({cursor}.text!==_phtv_seq.text)Q(_phtv_seq.text);{set_offset}(_phtv_seq.offset)}}'
            )
            
            # Find insert point
            if pattern["search"].endswith("}"):
                insert_point = idx + len(pattern["search"]) - len("return}")
            else:
                insert_point = idx + len(pattern["search"])
            
            content = content[:insert_point] + fix_code + content[insert_point:]
            
            # Write and verify
            path.write_text(content, encoding="utf-8")
            
            if PATCH_MARKER in path.read_text(encoding="utf-8"):
                return True
            else:
                print_color("-> Patch failed, restoring...", Colors.YELLOW)
                shutil.copy2(backup_path, path)
                return False
    
    print_color("   Pattern not found.", Colors.RED)
    print("   Code structure may have changed in newer version.")
    return False


def patch_exe(path: Path) -> bool:
    """Patch exe file."""
    content = path.read_bytes().decode("latin-1")
    
    # Count matches
    total_old = sum(content.count(p["old"]) for p in EXE_PATTERNS)
    marker_count = content.count(EXE_PATCH_MARKER)
    
    if total_old == 0 and marker_count > 0:
        print_color("   Already patched.", Colors.GREEN)
        return True
    
    if total_old == 0:
        print_color("   Pattern not found in binary.", Colors.RED)
        print("   Code structure may have changed in newer version.")
        return False
    
    print_color("-> Creating backup...", Colors.YELLOW)
    backup_path = create_backup(path)
    print(f"   Backup: {backup_path}")
    
    print_color("-> Analyzing and applying binary patch...", Colors.YELLOW)
    
    patched_content = content
    matched = []
    
    for pattern in EXE_PATTERNS:
        if len(pattern["new"]) > len(pattern["old"]):
            print_color(f"X Internal error: patch payload longer than original ({pattern['version']}).", Colors.RED)
            return False
        
        count = patched_content.count(pattern["old"])
        if count == 0:
            continue
        
        # Pad new content to match old length
        new_block = pattern["new"] + " " * (len(pattern["old"]) - len(pattern["new"]))
        patched_content = patched_content.replace(pattern["old"], new_block)
        matched.append(f"{pattern['version']}:{count}")
    
    # Write
    path.write_bytes(patched_content.encode("latin-1"))
    
    # Verify
    verify_content = path.read_bytes().decode("latin-1")
    remaining_old = sum(verify_content.count(p["old"]) for p in EXE_PATTERNS)
    new_marker_count = verify_content.count(EXE_PATCH_MARKER)
    
    if remaining_old == 0 and new_marker_count >= total_old:
        print(f"   Patched {total_old} block(s).")
        if matched:
            print(f"   Match: {', '.join(matched)}")
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
        if path.suffix == ".js":
            print("  You can reinstall Claude Code to restore:")
            print_color("  npm install -g @anthropic-ai/claude-code", Colors.GREEN)
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

def show_check(target_type: str, path: Path):
    """Show detailed health check."""
    print_color("-> Running health-check...", Colors.YELLOW)
    print()
    
    stat = path.stat()
    print(f"   Last write: {datetime.fromtimestamp(stat.st_mtime)}")
    print(f"   File size:  {stat.st_size} bytes")
    
    if target_type == "exe":
        content = path.read_bytes().decode("latin-1")
        marker_count = content.count(EXE_PATCH_MARKER)
        old_count = sum(content.count(p["old"]) for p in EXE_PATTERNS)
        is_patched = marker_count > 0 and old_count == 0
        has_bug = old_count > 0
    else:
        content = path.read_text(encoding="utf-8")
        is_patched = PATCH_MARKER in content
        has_bug = "backspace()" in content and ("\\x7f" in content or '"\x7f"' in content)
    
    can_patch = not is_patched and has_bug
    
    print("   Status:     ", end="")
    print_color("PATCHED" if is_patched else "NOT PATCHED", Colors.GREEN if is_patched else Colors.RED)
    
    print("   Bug code:   ", end="")
    print_color("Present" if has_bug else "Not found", Colors.YELLOW if has_bug else Colors.CYAN)
    
    print("   Can patch now: ", end="")
    print_color("YES" if can_patch else "NO", Colors.GREEN if can_patch else Colors.YELLOW)
    
    if target_type == "exe":
        print(f"   Marker cnt: {marker_count}")
        print(f"   Old cnt:    {old_count}")
    
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
        description="Claude Code Vietnamese IME Fix",
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
    
    # Find target
    print_color("-> Searching for Claude Code...", Colors.YELLOW)
    
    target = find_target()
    if not target:
        print_color("X Claude Code not found.", Colors.RED)
        print("  Please install Claude Code or check your PATH.")
        return 1
    
    target_type, path = target
    
    print_color(f"   Path: {path}", Colors.CYAN)
    print_color(f"   Install type: {target_type}", Colors.CYAN)
    print_color(f"   Version: {get_claude_version()}", Colors.CYAN)
    print()
    
    # Execute action
    if args.action == "check":
        show_check(target_type, path)
        return 0
    
    elif args.action == "patch":
        is_patched = is_exe_patched(path) if target_type == "exe" else is_cli_patched(path)
        
        if is_patched:
            print_color("OK Claude Code was already patched.", Colors.GREEN)
            return 0
        
        # Stop running processes
        if psutil and get_claude_processes():
            if not stop_claude_processes():
                return 1
            print()
        
        # Apply patch
        success = patch_exe(path) if target_type == "exe" else patch_cli(path)
        
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
        is_patched = is_exe_patched(path) if target_type == "exe" else is_cli_patched(path)
        
        if not is_patched:
            print_color("Claude Code is not patched.", Colors.YELLOW)
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
