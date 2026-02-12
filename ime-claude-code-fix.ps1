#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Vietnamese IME Fix - Windows (v2.1.9+)
    Fix loi go tieng Viet trong Claude Code CLI

.DESCRIPTION
    Script nay patch Claude Code de fix loi:
    - Bo go tieng Viet (EVKey, Unikey, OpenKey...) gui ky tu DEL (0x7F)
    - Claude Code xu ly backspace nhung khong insert text thay the
    
    Ho tro:
    - Ban npm (cli.js)
    - Ban binary claude.exe (v2.1.38+ da test)

.PARAMETER Action
    patch   - Ap dung patch (default)
    restore - Khoi phuc ban goc tu backup
    check   - Kiem tra chi tiet (quyen ghi, pattern, backup, smoke test)

.EXAMPLE
    .\patch-claude-vn-v2.1.9.ps1
    .\patch-claude-vn-v2.1.9.ps1 patch
    .\patch-claude-vn-v2.1.9.ps1 restore
    .\patch-claude-vn-v2.1.9.ps1 check
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
    Write-ColorLine "  Fix loi go tieng Viet trong Claude Code CLI" "Cyan"
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
    
    Write-ColorLine "-> Dang tao backup..." "Yellow"
    Copy-Item $CliPath $backupPath -Force
    Write-Host "   Backup: $backupPath"
    
    Write-ColorLine "-> Dang phan tich va ap dung patch..." "Yellow"
    
    $content = Get-Content $CliPath -Raw -Encoding UTF8
    
    if ($content -match [regex]::Escape($PATCH_MARKER)) {
        Write-ColorLine "   Da patch truoc do." "Green"
        return $true
    }
    
    $patched = $false
    
    # Pattern alternatives cho cac version khac nhau
    # v2.1.11: T(CA.offset)}Qe1(),Be1();return}  - Bien: l=input, S=cursor, CA=cursorAfter, Q=setText, T=setOffset
    # v2.1.9:  j(_A.offset)}Oe1(),Me1();return}  - Bien: n=input, P=cursor, _A=cursorAfter, Q=setText, j=setOffset
    # v2.1.7:  _(FA.offset)}...                  - Bien: s=input, j=cursor, FA=cursorAfter, Q=setText, _=setOffset
    
    $altPatterns = @(
        @{ Search = 'T(CA.offset)}Qe1(),Be1();return}'; Var = 'CA'; Input = 'l'; Cursor = 'S'; SetOffset = 'T'; Version = 'v2.1.11' },
        @{ Search = 'j(_A.offset)}Oe1(),Me1();return}'; Var = '_A'; Input = 'n'; Cursor = 'P'; SetOffset = 'j'; Version = 'v2.1.9' },
        @{ Search = '_(FA.offset)}'; Var = 'FA'; Input = 's'; Cursor = 'j'; SetOffset = '_'; Version = 'v2.1.7' },
        @{ Search = '_(EA.offset)}'; Var = 'EA'; Input = 's'; Cursor = 'j'; SetOffset = '_'; Version = 'older' }
    )
    
    foreach ($alt in $altPatterns) {
        $idx = $content.IndexOf($alt.Search)
        if ($idx -eq -1) { continue }
        
        # Kiem tra context - phai co backspace() va \x7f
        $startCtx = [Math]::Max(0, $idx - 500)
        $context = $content.Substring($startCtx, $idx - $startCtx)
        
        if (($context -match 'backspace\(\)') -and ($context -match '\\x7f|\.includes\(')) {
            Write-Host "   Tim thay pattern $($alt.Version)"
            
            $varName = $alt.Var
            $inputVar = $alt.Input
            $cursorVar = $alt.Cursor
            $setOffsetFn = $alt.SetOffset
            
            # Fix code: replay input theo stream event de giu dung thu tu IME
            # Su dung string concatenation de tranh PowerShell expand variables sai cach
            $fixCode = $PATCH_MARKER + 'let _phtv_seq=' + $cursorVar + ';for(const _c of ' + $inputVar + '){_phtv_seq=(_c==="\x7f"||_c==="\x08")?_phtv_seq.backspace():_phtv_seq.insert(_c)}if(!' + $cursorVar + '.equals(_phtv_seq)){if(' + $cursorVar + '.text!==_phtv_seq.text)Q(_phtv_seq.text);' + $setOffsetFn + '(_phtv_seq.offset)}'
            
            # Tim vi tri insert - sau pattern nhung truoc Qe1/Oe1 hoac return
            if ($alt.Search -match '\}$') {
                # Pattern ket thuc bang }, insert truoc return
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
        Write-ColorLine "   Khong tim thay pattern can patch." "Red"
        Write-Host "   Code structure co the da thay doi trong phien ban moi."
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
            Write-ColorLine "-> Patch that bai, dang khoi phuc..." "Yellow"
            Copy-Item $backupPath $CliPath -Force
            return $false
        }
    } else {
        Write-ColorLine "   Khong tim thay pattern can patch." "Red"
        Write-Host "   Code structure co the da thay doi trong phien ban moi."
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
        Write-ColorLine "   Da patch truoc do." "Green"
        return $true
    }

    if ($totalOldCount -lt 1) {
        Write-ColorLine "   Khong tim thay pattern can patch trong binary." "Red"
        Write-Host "   Code structure co the da thay doi trong phien ban moi."
        return $false
    }

    Write-ColorLine "-> Dang tao backup..." "Yellow"
    Copy-Item $ExePath $backupPath -Force
    Write-Host "   Backup: $backupPath"

    Write-ColorLine "-> Dang phan tich va ap dung patch binary..." "Yellow"

    $patchedContent = $content
    $matched = @()

    foreach ($pattern in $EXE_PATTERNS) {
        if ($pattern.NewCore.Length -gt $pattern.Old.Length) {
            Write-ColorLine "X Loi noi bo: payload patch cho exe dai hon block goc ($($pattern.Version))." "Red"
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
        Write-Host "   Da patch $totalOldCount block."
        if ($matched.Count -gt 0) {
            Write-Host "   Match: $($matched -join ', ')"
        }
        return $true
    }

    Write-ColorLine "-> Patch that bai, dang khoi phuc..." "Yellow"
    Copy-Item $backupPath $ExePath -Force
    return $false
}

function Invoke-Restore {
    param([string]$CliPath)
    
    $cliDir = Split-Path $CliPath -Parent
    $backups = Get-ChildItem $cliDir -Filter "cli.js.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorLine "X Khong tim thay file backup." "Red"
        Write-Host "  Ban co the cai lai Claude Code de khoi phuc:"
        Write-ColorLine "  npm install -g @anthropic-ai/claude-code" "Green"
        return $false
    }
    
    $latestBackup = $backups[0]
    Write-ColorLine "-> Dang khoi phuc tu backup..." "Yellow"
    Write-Host "   Backup: $($latestBackup.FullName)"
    
    Copy-Item $latestBackup.FullName $CliPath -Force
    Remove-Item $latestBackup.FullName -Force
    
    Write-ColorLine "OK Da khoi phuc Claude Code ve ban goc." "Green"
    return $true
}

function Invoke-RestoreExe {
    param([string]$ExePath)

    $exeDir = Split-Path $ExePath -Parent
    $exeName = Split-Path $ExePath -Leaf
    $backups = Get-ChildItem $exeDir -Filter "$exeName.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorLine "X Khong tim thay file backup." "Red"
        return $false
    }

    $latestBackup = $backups[0]
    Write-ColorLine "-> Dang khoi phuc tu backup..." "Yellow"
    Write-Host "   Backup: $($latestBackup.FullName)"

    Copy-Item $latestBackup.FullName $ExePath -Force
    Remove-Item $latestBackup.FullName -Force

    Write-ColorLine "OK Da khoi phuc Claude Code ve ban goc." "Green"
    return $true
}

function Show-CheckCliJs {
    param([string]$CliPath)

    Write-ColorLine "-> Chay health-check..." "Yellow"
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

    Write-Host "   Trang thai: " -NoNewline
    if ($isPatched) { Write-ColorLine "DA PATCH" "Green" } else { Write-ColorLine "CHUA PATCH" "Red" }
    Write-Host "   Bug code:   " -NoNewline
    if ($hasBugCode) { Write-ColorLine "Co ton tai" "Yellow" } else { Write-ColorLine "Khong tim thay" "Cyan" }
    Write-Host "   Co the patch ngay: " -NoNewline
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

    Write-ColorLine "-> Chay health-check..." "Yellow"
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

    Write-Host "   Trang thai: " -NoNewline
    if ($isPatched) { Write-ColorLine "DA PATCH" "Green" } else { Write-ColorLine "CHUA PATCH" "Red" }
    Write-Host "   Bug code:   " -NoNewline
    if ($oldCount -gt 0) { Write-ColorLine "Co ton tai" "Yellow" } else { Write-ColorLine "Khong tim thay" "Cyan" }
    Write-Host "   Co the patch ngay: " -NoNewline
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
    
    Write-ColorLine "-> Dang tim Claude Code..." "Yellow"
    
    $target = Find-ClaudeTarget

    if (-not $target -or -not (Test-Path $target.Path)) {
        Write-ColorLine "X Khong tim thay Claude Code." "Red"
        Write-Host "  Vui long cai dat Claude Code hoac kiem tra lai PATH."
        return
    }

    Write-ColorLine "   Duong dan: $($target.Path)" "Cyan"
    Write-ColorLine "   Kieu cai dat: $($target.Type)" "Cyan"
    Write-ColorLine "   Phien ban: $(Get-ClaudeVersion)" "Cyan"
    Write-Host ""
    
    switch ($Action) {
        'patch' {
            $alreadyPatched = if ($target.Type -eq 'exe') {
                Test-IsExePatched $target.Path
            } else {
                Test-IsCliJsPatched $target.Path
            }

            if ($alreadyPatched) {
                Write-ColorLine "OK Claude Code da duoc patch truoc do." "Green"
                return
            }

            $patchOk = if ($target.Type -eq 'exe') {
                Invoke-PatchExe $target.Path
            } else {
                Invoke-Patch $target.Path
            }

            if ($patchOk) {
                Write-Host ""
                Write-ColorLine "============================================================" "Green"
                Write-ColorLine "  OK Patch thanh cong! Vietnamese IME fix da duoc ap dung." "Green"
                Write-ColorLine "============================================================" "Green"
                Write-Host ""
                Write-Host "Vui long " -NoNewline
                Write-ColorLine "khoi dong lai Claude Code" "Yellow" -NoNewline
                Write-Host " de ap dung thay doi."
            } else {
                Write-Host ""
                Write-ColorLine "X Khong the ap dung patch." "Red"
            }
        }
        
        'restore' {
            $isPatched = if ($target.Type -eq 'exe') {
                Test-IsExePatched $target.Path
            } else {
                Test-IsCliJsPatched $target.Path
            }

            if (-not $isPatched) {
                Write-ColorLine "Claude Code chua duoc patch." "Yellow"
                return
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
