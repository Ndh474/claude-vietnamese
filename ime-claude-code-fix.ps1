#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Vietnamese IME Fix - Windows (v2.1.9+)
    Fix Vietnamese typing issues in Claude Code CLI

.DESCRIPTION
    This script patches Claude Code to fix:
    - Vietnamese IMEs (EVKey, Unikey, OpenKey...) send DEL character (0x7F)
    - Claude Code handles backspace but does not insert replacement text
    
    Supports:
    - npm package (cli.js)
    - Binary claude.exe (v2.1.38+ tested)

.PARAMETER Action
    patch   - Apply patch (default)
    restore - Restore original from backup
    check   - Detailed check (write access, pattern, backup, smoke test)

.EXAMPLE
    .\ime-claude-code-fix.ps1
    .\ime-claude-code-fix.ps1 patch
    .\ime-claude-code-fix.ps1 restore
    .\ime-claude-code-fix.ps1 check
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('patch', 'restore', 'check')]
    [string]$Action = 'patch'
)

$ErrorActionPreference = 'Stop'
$script:PATCH_MARKER = "/* PHTV Vietnamese IME fix */"
$script:EXE_PATCH_MARKER = "/*PHTV_EXE*/"
$script:EXE_PATTERNS = @(
    @{
        Version = 'v2.1.39'
        Old = 'if(!MH.backspace&&!MH.delete&&s.includes("\x7F")){let UH=(s.match(/\x7f/g)||[]).length,FH=h;for(let ZH=0;ZH<UH;ZH++)FH=FH.deleteTokenBefore()??FH.backspace();if(!h.equals(FH)){if(h.text!==FH.text)$(FH.text);O(FH.offset)}TRH(),QRH();return}'
        NewCore = 'if(!MH.backspace&&!MH.delete&&s.includes("\x7F")){let FH=h;for(let ZH of s)FH="\x08\x7f".includes(ZH)?FH.deleteTokenBefore()??FH.backspace():FH.insert(ZH);if(!h.equals(FH)){$(FH.text);O(FH.offset)}/*PHTV_EXE*/TRH(),QRH();return}'
    },
    @{
        Version = 'v2.1.38'
        Old = 'if(!XH.backspace&&!XH.delete&&s.includes("\x7F")){let UH=(s.match(/\x7f/g)||[]).length,GH=h;for(let YH=0;YH<UH;YH++)GH=GH.deleteTokenBefore()??GH.backspace();if(!h.equals(GH)){if(h.text!==GH.text)$(GH.text);O(GH.offset)}IRH(),fRH();return}'
        NewCore = 'if(!XH.backspace&&!XH.delete&&s.includes("\x7F")){let GH=h;for(let YH of s)GH="\x08\x7f".includes(YH)?GH.deleteTokenBefore()??GH.backspace():GH.insert(YH);if(!h.equals(GH)){$(GH.text);O(GH.offset)}/*PHTV_EXE*/IRH(),fRH();return}'
    }
)

function Write-ColorLine {
    param([string]$Text, [string]$Color = 'White')
    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    Write-Host ""
    Write-ColorLine "============================================================" "Cyan"
    Write-ColorLine "  Claude Code Vietnamese IME Fix - v2.1.9+" "Cyan"
    Write-ColorLine "  Fix Vietnamese typing issues in Claude Code CLI" "Cyan"
    Write-ColorLine "============================================================" "Cyan"
    Write-Host ""
}

function Find-ClaudeCliJs {
    # Method 1: From claude command
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $claudePath = $claudeCmd.Source

        # npm install - find cli.js
        if ($claudePath -match '\.(cmd|bat|ps1)$') {
            $claudeDir = Split-Path $claudePath -Parent
            $npmModules = Join-Path $claudeDir "node_modules\@anthropic-ai\claude-code\cli.js"
            if (Test-Path $npmModules) {
                return $npmModules
            }
        }
    }
    
    # Method 2: npm root -g
    try {
        $npmRoot = & npm root -g 2>$null
        if ($npmRoot) {
            $cliPath = Join-Path $npmRoot "@anthropic-ai\claude-code\cli.js"
            if (Test-Path $cliPath) {
                return $cliPath
            }
        }
    } catch { }
    
    # Method 3: Common paths
    $commonPaths = @(
        "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code\cli.js"
        "$env:USERPROFILE\AppData\Local\npm\node_modules\@anthropic-ai\claude-code\cli.js"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

function Find-ClaudeExe {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) { return $null }

    $claudePath = $claudeCmd.Source
    if (($claudePath -match '\.exe$') -and (Test-Path $claudePath)) {
        return $claudePath
    }

    return $null
}

function Find-ClaudeTarget {
    $cliPath = Find-ClaudeCliJs
    if ($cliPath) {
        return @{
            Type = 'cli.js'
            Path = $cliPath
        }
    }

    $exePath = Find-ClaudeExe
    if ($exePath) {
        return @{
            Type = 'exe'
            Path = $exePath
        }
    }

    return $null
}

function Test-IsCliJsPatched {
    param([string]$CliPath)
    $content = Get-Content $CliPath -Raw -ErrorAction SilentlyContinue
    return $content -match [regex]::Escape($PATCH_MARKER)
}

function Test-IsExePatched {
    param([string]$ExePath)

    $enc = [System.Text.Encoding]::GetEncoding(28591)
    $content = $enc.GetString([System.IO.File]::ReadAllBytes($ExePath))
    return $content.Contains($EXE_PATCH_MARKER)
}

function Get-ClaudeVersion {
    try {
        $version = & claude --version 2>$null | Select-Object -First 1
        return $version
    } catch {
        return "unknown"
    }
}

function Get-ClaudeProcesses {
    # Find all running claude processes
    $processes = @()
    
    # Find claude.exe
    $claudeExe = Get-Process -Name "claude" -ErrorAction SilentlyContinue
    if ($claudeExe) {
        $processes += $claudeExe
    }
    
    # Find node process running cli.js (for npm install)
    $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmdLine -match "claude-code" -or $cmdLine -match "@anthropic-ai"
        } catch { $false }
    }
    if ($nodeProcesses) {
        $processes += $nodeProcesses
    }
    
    return $processes
}

function Stop-ClaudeProcesses {
    param([switch]$Force)
    
    $processes = Get-ClaudeProcesses
    
    if ($processes.Count -eq 0) {
        return $true
    }
    
    Write-Host ""
    Write-ColorLine "! Detected running Claude Code processes:" "Yellow"
    foreach ($proc in $processes) {
        Write-Host "   - $($proc.ProcessName) (PID: $($proc.Id))"
    }
    Write-Host ""
    
    if (-not $Force) {
        Write-ColorLine "? This action will CLOSE ALL running Claude Code sessions." "Yellow"
        Write-ColorLine "  Any unsaved work will be lost!" "Red"
        Write-Host ""
        $confirm = Read-Host "  Do you want to continue? (y/N)"
        
        if ($confirm -notmatch '^[yY]$') {
            Write-ColorLine "-> Cancelled. Please close Claude Code manually and try again." "Cyan"
            return $false
        }
    }
    
    Write-ColorLine "-> Closing Claude Code processes..." "Yellow"
    foreach ($proc in $processes) {
        try {
            $proc | Stop-Process -Force -ErrorAction Stop
            Write-Host "   Closed: $($proc.ProcessName) (PID: $($proc.Id))"
        } catch {
            Write-ColorLine "   Failed to close: $($proc.ProcessName) (PID: $($proc.Id))" "Red"
        }
    }
    
    # Wait a bit for processes to fully terminate
    Start-Sleep -Milliseconds 500
    
    # Check again
    $remaining = Get-ClaudeProcesses
    if ($remaining.Count -gt 0) {
        Write-ColorLine "X Some Claude processes are still running. Please close them manually." "Red"
        return $false
    }
    
    Write-ColorLine "   All Claude Code processes closed." "Green"
    return $true
}

function Test-WriteAccess {
    param([string]$Directory, [ref]$ErrorText)

    $probePath = Join-Path $Directory ("._phtv_write_probe_" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [System.IO.File]::WriteAllText($probePath, "ok")
        Remove-Item $probePath -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        $ErrorText.Value = $_.Exception.Message
        if (Test-Path $probePath) {
            Remove-Item $probePath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function Invoke-Patch {
    param([string]$CliPath)
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$CliPath.backup-$timestamp"
    
    Write-ColorLine "-> Creating backup..." "Yellow"
    Copy-Item $CliPath $backupPath -Force
    Write-Host "   Backup: $backupPath"
    
    Write-ColorLine "-> Analyzing and applying patch..." "Yellow"
    
    $content = Get-Content $CliPath -Raw -Encoding UTF8
    
    if ($content -match [regex]::Escape($PATCH_MARKER)) {
        Write-ColorLine "   Already patched." "Green"
        return $true
    }
    
    $patched = $false
    
    # Pattern alternatives for different versions
    # v2.1.11: T(CA.offset)}Qe1(),Be1();return}  - Vars: l=input, S=cursor, CA=cursorAfter, Q=setText, T=setOffset
    # v2.1.9:  j(_A.offset)}Oe1(),Me1();return}  - Vars: n=input, P=cursor, _A=cursorAfter, Q=setText, j=setOffset
    # v2.1.7:  _(FA.offset)}...                  - Vars: s=input, j=cursor, FA=cursorAfter, Q=setText, _=setOffset
    
    $altPatterns = @(
        @{ Search = 'T(CA.offset)}Qe1(),Be1();return}'; Var = 'CA'; Input = 'l'; Cursor = 'S'; SetOffset = 'T'; Version = 'v2.1.11' },
        @{ Search = 'j(_A.offset)}Oe1(),Me1();return}'; Var = '_A'; Input = 'n'; Cursor = 'P'; SetOffset = 'j'; Version = 'v2.1.9' },
        @{ Search = '_(FA.offset)}'; Var = 'FA'; Input = 's'; Cursor = 'j'; SetOffset = '_'; Version = 'v2.1.7' },
        @{ Search = '_(EA.offset)}'; Var = 'EA'; Input = 's'; Cursor = 'j'; SetOffset = '_'; Version = 'older' }
    )
    
    foreach ($alt in $altPatterns) {
        $idx = $content.IndexOf($alt.Search)
        if ($idx -eq -1) { continue }
        
        # Check context - must have backspace() and \x7f
        $startCtx = [Math]::Max(0, $idx - 500)
        $context = $content.Substring($startCtx, $idx - $startCtx)
        
        if (($context -match 'backspace\(\)') -and ($context -match '\\x7f|\.includes\(')) {
            Write-Host "   Found pattern $($alt.Version)"
            
            $varName = $alt.Var
            $inputVar = $alt.Input
            $cursorVar = $alt.Cursor
            $setOffsetFn = $alt.SetOffset
            
            # Fix code: replay input as stream events to maintain IME order
            # Use string concatenation to avoid PowerShell variable expansion issues
            $fixCode = $PATCH_MARKER + 'let _phtv_seq=' + $cursorVar + ';for(const _c of ' + $inputVar + '){_phtv_seq=(_c==="\x7f"||_c==="\x08")?_phtv_seq.backspace():_phtv_seq.insert(_c)}if(!' + $cursorVar + '.equals(_phtv_seq)){if(' + $cursorVar + '.text!==_phtv_seq.text)Q(_phtv_seq.text);' + $setOffsetFn + '(_phtv_seq.offset)}'
            
            # Find insert point - after pattern but before Qe1/Oe1 or return
            if ($alt.Search -match '\}$') {
                # Pattern ends with }, insert before return
                $insertPoint = $idx + $alt.Search.Length - 'return}'.Length
            } else {
                $insertPoint = $idx + $alt.Search.Length
            }
            
            $content = $content.Substring(0, $insertPoint) + $fixCode + $content.Substring($insertPoint)
            $patched = $true
            break
        }
    }
    
    if (-not $patched) {
        Write-ColorLine "   Pattern not found." "Red"
        Write-Host "   Code structure may have changed in newer version."
        return $false
    }
    
    if ($patched) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($CliPath, $content, $utf8NoBom)
        
        # Verify
        $verifyContent = Get-Content $CliPath -Raw -ErrorAction SilentlyContinue
        if ($verifyContent -match [regex]::Escape($PATCH_MARKER)) {
            return $true
        } else {
            Write-ColorLine "-> Patch failed, restoring..." "Yellow"
            Copy-Item $backupPath $CliPath -Force
            return $false
        }
    } else {
        Write-ColorLine "   Pattern not found." "Red"
        Write-Host "   Code structure may have changed in newer version."
        return $false
    }
}

function Invoke-PatchExe {
    param([string]$ExePath)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$ExePath.backup-$timestamp"

    $enc = [System.Text.Encoding]::GetEncoding(28591)
    $bytes = [System.IO.File]::ReadAllBytes($ExePath)
    $content = $enc.GetString($bytes)

    $totalOldCount = 0
    foreach ($pattern in $EXE_PATTERNS) {
        $totalOldCount += ([regex]::Matches($content, [regex]::Escape($pattern.Old))).Count
    }
    $markerCountBefore = ([regex]::Matches($content, [regex]::Escape($EXE_PATCH_MARKER))).Count

    if (($totalOldCount -eq 0) -and ($markerCountBefore -gt 0)) {
        Write-ColorLine "   Already patched." "Green"
        return $true
    }

    if ($totalOldCount -lt 1) {
        Write-ColorLine "   Pattern not found in binary." "Red"
        Write-Host "   Code structure may have changed in newer version."
        return $false
    }

    Write-ColorLine "-> Creating backup..." "Yellow"
    Copy-Item $ExePath $backupPath -Force
    Write-Host "   Backup: $backupPath"

    Write-ColorLine "-> Analyzing and applying binary patch..." "Yellow"

    $patchedContent = $content
    $matched = @()

    foreach ($pattern in $EXE_PATTERNS) {
        if ($pattern.NewCore.Length -gt $pattern.Old.Length) {
            Write-ColorLine "X Internal error: patch payload longer than original block ($($pattern.Version))." "Red"
            return $false
        }

        $count = ([regex]::Matches($patchedContent, [regex]::Escape($pattern.Old))).Count
        if ($count -lt 1) { continue }

        $newBlock = $pattern.NewCore + (' ' * ($pattern.Old.Length - $pattern.NewCore.Length))
        $patchedContent = $patchedContent.Replace($pattern.Old, $newBlock)
        $matched += "$($pattern.Version):$count"
    }

    [System.IO.File]::WriteAllBytes($ExePath, $enc.GetBytes($patchedContent))

    # Verify
    $verifyContent = $enc.GetString([System.IO.File]::ReadAllBytes($ExePath))
    $remainingOld = 0
    foreach ($pattern in $EXE_PATTERNS) {
        $remainingOld += ([regex]::Matches($verifyContent, [regex]::Escape($pattern.Old))).Count
    }
    $markerCount = ([regex]::Matches($verifyContent, [regex]::Escape($EXE_PATCH_MARKER))).Count

    if (($remainingOld -eq 0) -and ($markerCount -ge $totalOldCount)) {
        Write-Host "   Patched $totalOldCount block(s)."
        if ($matched.Count -gt 0) {
            Write-Host "   Match: $($matched -join ', ')"
        }
        return $true
    }

    Write-ColorLine "-> Patch failed, restoring..." "Yellow"
    Copy-Item $backupPath $ExePath -Force
    return $false
}

function Invoke-Restore {
    param([string]$CliPath)
    
    $cliDir = Split-Path $CliPath -Parent
    $backups = Get-ChildItem $cliDir -Filter "cli.js.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorLine "X Backup file not found." "Red"
        Write-Host "  You can reinstall Claude Code to restore:"
        Write-ColorLine "  npm install -g @anthropic-ai/claude-code" "Green"
        return $false
    }
    
    $latestBackup = $backups[0]
    Write-ColorLine "-> Restoring from backup..." "Yellow"
    Write-Host "   Backup: $($latestBackup.FullName)"
    
    Copy-Item $latestBackup.FullName $CliPath -Force
    Remove-Item $latestBackup.FullName -Force
    
    Write-ColorLine "OK Claude Code restored to original." "Green"
    return $true
}

function Invoke-RestoreExe {
    param([string]$ExePath)

    $exeDir = Split-Path $ExePath -Parent
    $exeName = Split-Path $ExePath -Leaf
    $backups = Get-ChildItem $exeDir -Filter "$exeName.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorLine "X Backup file not found." "Red"
        return $false
    }

    $latestBackup = $backups[0]
    Write-ColorLine "-> Restoring from backup..." "Yellow"
    Write-Host "   Backup: $($latestBackup.FullName)"

    Copy-Item $latestBackup.FullName $ExePath -Force
    Remove-Item $latestBackup.FullName -Force

    Write-ColorLine "OK Claude Code restored to original." "Green"
    return $true
}

function Show-CheckCliJs {
    param([string]$CliPath)

    Write-ColorLine "-> Running health-check..." "Yellow"
    Write-Host ""

    $fileInfo = Get-Item $CliPath -ErrorAction SilentlyContinue
    if ($fileInfo) {
        Write-Host "   Last write: $($fileInfo.LastWriteTime)"
        Write-Host "   File size:  $($fileInfo.Length) bytes"
    }

    $content = Get-Content $CliPath -Raw -ErrorAction SilentlyContinue
    $isPatched = $content -match [regex]::Escape($PATCH_MARKER)
    $hasBugCode = ($content -match 'backspace\(\)') -and ($content -match '\\x7f|"\x7f"')
    $canPatchNow = (-not $isPatched) -and $hasBugCode

    Write-Host "   Status:     " -NoNewline
    if ($isPatched) { Write-ColorLine "PATCHED" "Green" } else { Write-ColorLine "NOT PATCHED" "Red" }
    Write-Host "   Bug code:   " -NoNewline
    if ($hasBugCode) { Write-ColorLine "Present" "Yellow" } else { Write-ColorLine "Not found" "Cyan" }
    Write-Host "   Can patch now: " -NoNewline
    if ($canPatchNow) { Write-ColorLine "YES" "Green" } else { Write-ColorLine "NO" "DarkYellow" }

    $cliDir = Split-Path $CliPath -Parent
    $writeErr = ""
    $canWrite = Test-WriteAccess $cliDir ([ref]$writeErr)
    Write-Host "   Write access:" -NoNewline
    if ($canWrite) {
        Write-ColorLine " OK" "Green"
    } else {
        Write-ColorLine " DENIED" "Red"
        Write-Host "   Write error: $writeErr"
    }

    $backups = Get-ChildItem $cliDir -Filter "cli.js.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    Write-Host "   Backups:    $($backups.Count)"
    if ($backups -and $backups.Count -gt 0) {
        Write-Host "   Latest:     $($backups[0].Name) ($($backups[0].LastWriteTime))"
    }

    try {
        $hash = Get-FileHash $CliPath -Algorithm SHA256 -ErrorAction Stop
        Write-Host "   SHA256:     $($hash.Hash)"
    } catch {
        Write-Host "   SHA256:     N/A"
    }

    $version = Get-ClaudeVersion
    Write-Host "   Version:    $version"

    $helpOk = $false
    try {
        $helpFirstLine = & claude --help 2>$null | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($helpFirstLine)) {
            $helpOk = $true
        }
    } catch { }
    Write-Host "   Smoke test (--help):" -NoNewline
    if ($helpOk) { Write-ColorLine " OK" "Green" } else { Write-ColorLine " FAIL" "Red" }
}

function Show-CheckExe {
    param([string]$ExePath)

    Write-ColorLine "-> Running health-check..." "Yellow"
    Write-Host ""

    $fileInfo = Get-Item $ExePath -ErrorAction SilentlyContinue
    if ($fileInfo) {
        Write-Host "   Last write: $($fileInfo.LastWriteTime)"
        Write-Host "   File size:  $($fileInfo.Length) bytes"
    }

    $enc = [System.Text.Encoding]::GetEncoding(28591)
    $content = $enc.GetString([System.IO.File]::ReadAllBytes($ExePath))
    $markerCount = ([regex]::Matches($content, [regex]::Escape($EXE_PATCH_MARKER))).Count
    $oldCount = 0
    $oldDetail = @()
    foreach ($pattern in $EXE_PATTERNS) {
        $count = ([regex]::Matches($content, [regex]::Escape($pattern.Old))).Count
        $oldCount += $count
        if ($count -gt 0) {
            $oldDetail += "$($pattern.Version):$count"
        }
    }
    $isPatched = ($markerCount -gt 0) -and ($oldCount -eq 0)
    $canPatchNow = ($oldCount -gt 0)

    Write-Host "   Status:     " -NoNewline
    if ($isPatched) { Write-ColorLine "PATCHED" "Green" } else { Write-ColorLine "NOT PATCHED" "Red" }
    Write-Host "   Bug code:   " -NoNewline
    if ($oldCount -gt 0) { Write-ColorLine "Present" "Yellow" } else { Write-ColorLine "Not found" "Cyan" }
    Write-Host "   Can patch now: " -NoNewline
    if ($canPatchNow) { Write-ColorLine "YES" "Green" } else { Write-ColorLine "NO" "DarkYellow" }
    Write-Host "   Marker cnt: $markerCount"
    Write-Host "   Old cnt:    $oldCount"
    if ($oldDetail.Count -gt 0) {
        Write-Host "   Old detail: $($oldDetail -join ', ')"
    }

    $exeDir = Split-Path $ExePath -Parent
    $writeErr = ""
    $canWrite = Test-WriteAccess $exeDir ([ref]$writeErr)
    Write-Host "   Write access:" -NoNewline
    if ($canWrite) {
        Write-ColorLine " OK" "Green"
    } else {
        Write-ColorLine " DENIED" "Red"
        Write-Host "   Write error: $writeErr"
    }

    $exeName = Split-Path $ExePath -Leaf
    $backups = Get-ChildItem $exeDir -Filter "$exeName.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    Write-Host "   Backups:    $($backups.Count)"
    if ($backups -and $backups.Count -gt 0) {
        Write-Host "   Latest:     $($backups[0].Name) ($($backups[0].LastWriteTime))"
    }

    try {
        $hash = Get-FileHash $ExePath -Algorithm SHA256 -ErrorAction Stop
        Write-Host "   SHA256:     $($hash.Hash)"
    } catch {
        Write-Host "   SHA256:     N/A"
    }

    $version = Get-ClaudeVersion
    Write-Host "   Version:    $version"

    $helpOk = $false
    try {
        $helpFirstLine = & claude --help 2>$null | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($helpFirstLine)) {
            $helpOk = $true
        }
    } catch { }
    Write-Host "   Smoke test (--help):" -NoNewline
    if ($helpOk) { Write-ColorLine " OK" "Green" } else { Write-ColorLine " FAIL" "Red" }
}

# Main
function Main {
    Write-Header
    
    Write-ColorLine "-> Searching for Claude Code..." "Yellow"
    
    $target = Find-ClaudeTarget

    if (-not $target -or -not (Test-Path $target.Path)) {
        Write-ColorLine "X Claude Code not found." "Red"
        Write-Host "  Please install Claude Code or check your PATH."
        return
    }

    Write-ColorLine "   Path: $($target.Path)" "Cyan"
    Write-ColorLine "   Install type: $($target.Type)" "Cyan"
    Write-ColorLine "   Version: $(Get-ClaudeVersion)" "Cyan"
    Write-Host ""
    
    switch ($Action) {
        'patch' {
            $alreadyPatched = if ($target.Type -eq 'exe') {
                Test-IsExePatched $target.Path
            } else {
                Test-IsCliJsPatched $target.Path
            }

            if ($alreadyPatched) {
                Write-ColorLine "OK Claude Code was already patched." "Green"
                return
            }

            # Check and close running Claude processes
            $claudeProcesses = Get-ClaudeProcesses
            if ($claudeProcesses.Count -gt 0) {
                $stopped = Stop-ClaudeProcesses
                if (-not $stopped) {
                    return
                }
                Write-Host ""
            }

            $patchOk = if ($target.Type -eq 'exe') {
                Invoke-PatchExe $target.Path
            } else {
                Invoke-Patch $target.Path
            }

            if ($patchOk) {
                Write-Host ""
                Write-ColorLine "============================================================" "Green"
                Write-ColorLine "  OK Patch successful! Vietnamese IME fix has been applied." "Green"
                Write-ColorLine "============================================================" "Green"
                Write-Host ""
                Write-Host "Please " -NoNewline
                Write-ColorLine "restart Claude Code" "Yellow" -NoNewline
                Write-Host " to apply changes."
            } else {
                Write-Host ""
                Write-ColorLine "X Failed to apply patch." "Red"
            }
        }
        
        'restore' {
            $isPatched = if ($target.Type -eq 'exe') {
                Test-IsExePatched $target.Path
            } else {
                Test-IsCliJsPatched $target.Path
            }

            if (-not $isPatched) {
                Write-ColorLine "Claude Code is not patched." "Yellow"
                return
            }

            # Check and close running Claude processes
            $claudeProcesses = Get-ClaudeProcesses
            if ($claudeProcesses.Count -gt 0) {
                $stopped = Stop-ClaudeProcesses
                if (-not $stopped) {
                    return
                }
                Write-Host ""
            }

            if ($target.Type -eq 'exe') {
                Invoke-RestoreExe $target.Path
            } else {
                Invoke-Restore $target.Path
            }
        }
        
        'check' {
            if ($target.Type -eq 'exe') {
                Show-CheckExe $target.Path
            } else {
                Show-CheckCliJs $target.Path
            }
        }
    }
}

Main
