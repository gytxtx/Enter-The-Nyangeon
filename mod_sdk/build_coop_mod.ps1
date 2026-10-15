<#
.SYNOPSIS
  打包联机 mod 源为 pck，并可选安装到 user://mods。
  - mod.json 未设 replace_files 时：用 PCKPacker 直接打包（仅 res://mods/<id>/…）。
  - mod.json 设 replace_files=true 时：走覆盖型导出预设 ModPackReplace（--export-pack），
    pck 内含 res://mods/<id>/** 与 mod.json.replace_paths 指定的本体文件（用于覆盖本体）。
    该模式要求先运行 setup_mod_project.ps1 -Replace 注入预设。

.EXAMPLE
  .\build_coop_mod.ps1
  .\build_coop_mod.ps1 -Install
#>
param(
    [string]$Godot = "H:\Godot_v4.7-stable_win64.exe",
    [string]$Project = "H:\Enter The Nyangeon",
    [string]$ModId = "etn_coop",
    [string]$Source = "",
    [switch]$Install
)
# Godot 输出由共用构建契约分类；退出资源计数之外的错误会终止构建。
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "build_common.ps1")
Assert-ModId -ModId $ModId
$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($Source -eq "") {
    $Source = Join-Path $PSScriptRoot "coop_mod\mods\$ModId"
}
if (-not (Test-Path -LiteralPath (Join-Path $Source "mod.json"))) {
    throw "找不到 mod.json：$Source\mod.json"
}

# 从 mod.json 读取版本号与覆盖配置（按 UTF-8 读取，避免含中文时 PowerShell 5.1 默认 ANSI 解析失败）
$manifest = [System.IO.File]::ReadAllText((Join-Path $Source "mod.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$version = ""
if ($manifest -and $manifest.version) { $version = [string]$manifest.version }
if ($version -eq "") { Write-Warning "mod.json 缺少 version，跳过版本化归档命名" }
$replaceFiles = $false
if ($manifest -and ($manifest.PSObject.Properties.Name -contains 'replace_files')) {
    $replaceFiles = [bool]$manifest.replace_files
}
$replacePaths = @()
if ($manifest -and ($manifest.PSObject.Properties.Name -contains 'replace_paths')) {
    foreach ($rp in $manifest.replace_paths) { if (([string]$rp) -ne "") { $replacePaths += [string]$rp } }
}

$outDir = Join-Path $PSScriptRoot "coop_mod\build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$pck = Join-Path $outDir "$ModId.pck"
$buildPck = Join-Path $outDir "$ModId.building.pck"
if (Test-Path -LiteralPath $buildPck) { Remove-Item -LiteralPath $buildPck -Force }

# 编辑器镜像（res://mods/<id>）：编辑器会扫描并生成 .uid，源目录在 .gdignore 下不会。
$mirror = Join-Path $Project "mods\$ModId"

# 同步镜像里生成的 .uid 边车到 mod 源目录（缺 .gd.uid 会刷 invalid UID 警告）
if (Test-Path -LiteralPath $mirror) {
    $synced = 0
    foreach ($u in (Get-ChildItem -LiteralPath $mirror -Recurse -File -Filter "*.uid")) {
        $rel = $u.FullName.Substring($mirror.Length + 1)
        $dest = Join-Path $Source $rel
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item -LiteralPath $u.FullName -Destination $dest -Force
        $synced++
    }
    Write-Host "已同步 $synced 个 .uid：$mirror -> $Source"
} else {
    Write-Warning "未找到编辑器镜像 $mirror，跳过 .uid 同步（若源目录已含 .uid 则不影响）"
}

if ($replaceFiles) {
    # ---------- 覆盖构建（ModPackReplace 预设）：pck 含 mod 目录 + 本体替换文件 ----------
    if (-not (Test-Path -LiteralPath $mirror)) {
        throw "覆盖构建需要编辑器镜像 $mirror 作为 res:// 来源，但不存在"
    }
    # 保证镜像与打包源一致（镜像才是 res:// 下的真实来源）
    foreach ($f in (Get-ChildItem -LiteralPath $Source -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($Source.Length + 1)
        if ($rel -match '(^|\\)\.') { continue }
        $dest = Join-Path $mirror $rel
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    Write-Host "已同步打包源到编辑器镜像：$Source -> $mirror"

    $presetsPath = Join-Path $Project "export_presets.cfg"
    if (-not (Test-Path -LiteralPath $presetsPath)) {
        throw "找不到 export_presets.cfg：先运行 setup_mod_project.ps1 -Replace"
    }
    if (-not (Select-String -LiteralPath $presetsPath -Pattern '^name="ModPackReplace"\s*$' -Quiet)) {
        throw "export_presets.cfg 缺少 ModPackReplace 预设：先运行 setup_mod_project.ps1 -Replace（需关闭编辑器）"
    }

    # 生成 export_files = 镜像下全部文件（res://mods/<id>/…） + replace_paths（本体 res:// 文件）
    $exportFiles = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $mirror -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($mirror.Length + 1).Replace('\', '/')
        if ($rel -notmatch '(^|/)\.') { $exportFiles.Add("res://mods/$ModId/$rel") }
    }
    foreach ($rp in $replacePaths) {
        $rel = $rp -replace '^res://', ''
        $abs = Join-Path $Project ($rel.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $abs)) { throw "replace_paths 指向的文件不存在：$rp" }
        $exportFiles.Add($rp)
    }
    $exportFiles = @($exportFiles | Select-Object -Unique)
    $arr = (($exportFiles | ForEach-Object { '"' + $_ + '"' }) -join ", ")
    $exportLine = "export_files=PackedStringArray($arr)"

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($ln in ([System.IO.File]::ReadAllText($presetsPath) -split "`n")) { $lines.Add($ln.TrimEnd("`r")) }
    $nameIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq 'name="ModPackReplace"') { $nameIdx = $i; break } }
    if ($nameIdx -lt 0) { throw "未找到 ModPackReplace 预设；先运行 setup_mod_project.ps1 -Replace" }
    $start = -1
    for ($j = $nameIdx; $j -ge 0; $j--) { if ($lines[$j].Trim() -match '^\[preset\.\d+\]$') { $start = $j; break } }
    $end = $lines.Count
    for ($j = $start + 1; $j -lt $lines.Count; $j++) { if ($lines[$j].Trim().StartsWith("[")) { $end = $j; break } }
    $replaced = $false
    for ($j = $start; $j -lt $end; $j++) {
        if ($lines[$j] -match '^export_files=') { $lines[$j] = $exportLine; $replaced = $true; break }
    }
    if (-not $replaced) {
        for ($j = $start; $j -lt $end; $j++) {
            if ($lines[$j] -match '^export_filter=') { $lines.Insert($j + 1, $exportLine); $replaced = $true; break }
        }
    }
    if (-not $replaced) { throw "在 ModPackReplace 区块内找不到 export_filter/export_files 行" }
    [System.IO.File]::WriteAllText($presetsPath, ($lines -join "`n"), $utf8)
    Write-Host "已生成 export_files：$($exportFiles.Count) 个文件（含 $($replacePaths.Count) 个本体替换）"

    Write-Host "导出 pck（preset: ModPackReplace）：$pck"
    Invoke-CheckedGodot -Godot $Godot -Arguments @('--headless', '--path', $Project, '--export-pack', 'ModPackReplace', $buildPck)
} else {
    Write-Host "打包 pck（PCKPacker）：$pck"
    $packer = Join-Path $PSScriptRoot "pack_mod.gd"
    Invoke-CheckedGodot -Godot $Godot -Arguments @('--headless', '--path', $Project, '--script', $packer, '--', "--mod-source=$Source", "--out=$buildPck", "--mod-id=$ModId") -Marker 'PACK_MOD:'
}
Complete-ModPack -Godot $Godot -Project $Project -Candidate $buildPck -Destination $pck

$stage = Join-Path $outDir $ModId
$stage = [IO.Path]::GetFullPath($stage)
if (-not $stage.StartsWith([IO.Path]::GetFullPath($outDir).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "暂存目录越界" }
if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $Source "mod.json") (Join-Path $stage "mod.json")
Copy-Item $pck (Join-Path $stage "$ModId.pck")
if (Test-Path -LiteralPath (Join-Path $Source "icon.png")) {
    Copy-Item (Join-Path $Source "icon.png") (Join-Path $stage "icon.png")
}

$zip = Join-Path $outDir "$ModId.zip"
$candidateZip = Join-Path $outDir "$ModId.building.zip"
if (Test-Path -LiteralPath $candidateZip) { Remove-Item -LiteralPath $candidateZip -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $candidateZip
Move-Item -LiteralPath $candidateZip -Destination $zip -Force
Write-Host "已生成：$zip"

# 版本化归档：etn_coop_<version>.zip（对齐既有分发命名）
if ($version -ne "") {
    $zipVersioned = Join-Path $outDir "$ModId`_$version.zip"
    if (Test-Path -LiteralPath $zipVersioned) { Remove-Item -Force $zipVersioned }
    Copy-Item -LiteralPath $zip -Destination $zipVersioned -Force
    Write-Host "已生成版本归档：$zipVersioned"
}

if ($Install) {
    $dest = Join-Path $env:APPDATA "Godot\app_userdata\Enter The Nyangeon\mods\$ModId"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item (Join-Path $stage "*") $dest -Recurse -Force
    Write-Host "已安装到：$dest（重启游戏生效）"
}
