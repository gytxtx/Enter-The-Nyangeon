# 构建成功契约：退出码、诊断、完成标记和 PCK 结构均通过后才替换正式产物。
function Invoke-CheckedGodot {
    param([string]$Godot, [string[]]$Arguments, [string]$Marker = "")
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $Godot @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    $text = ($output | Out-String)
    Write-Host $text
    if ($code -ne 0) { throw "Godot 构建进程退出失败：$code" }
    # 与原生回归 runner 一致：仅豁免已知的进程退出资源计数，不吞掉构建/脚本错误。
    $diagnostics = ($text -replace '\x1b\[[0-9;]*m', '') -split "`r?`n" | Where-Object {
        $_ -notmatch '^ERROR: \d+ resources still in use at exit \(run with --verbose for details\)\.$'
    }
    if (($diagnostics -join "`n") -match '(SCRIPT ERROR|ERROR:|add_file failed)') { throw "Godot 构建包含错误诊断" }
    if ($Marker -ne "" -and $text -notmatch [regex]::Escape($Marker)) { throw "Godot 构建缺少完成标记：$Marker" }
}

function Complete-ModPack {
    param([string]$Godot, [string]$Project, [string]$Candidate, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { throw "构建未生成候选 PCK：$Candidate" }
    $verify = Join-Path $PSScriptRoot "verify_mod_pack.gd"
    $validator = Join-Path $PSScriptRoot "..\script\mod_pack_validator.gd"
    Invoke-CheckedGodot -Godot $Godot -Arguments @('--headless', '--path', $Project, '--script', $verify, '--', $validator, $Candidate) -Marker 'PACK_VERIFIED'
    Move-Item -LiteralPath $Candidate -Destination $Destination -Force
}

function Assert-ModId {
    param([string]$ModId)
    if ($ModId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$' -or $ModId -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "ModId 必须是安全的单个目录名" }
}
