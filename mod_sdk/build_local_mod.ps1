<#
.SYNOPSIS
  打包本体工程根目录 mods/<ModId>/ 为 pck，并可选安装到 user://mods。
  直接用本体工程 + PCKPacker（mod_sdk/pack_mod.gd），无需工程副本。
  适用于 mod 源就放在本体工程 mods/ 下（编辑器镜像）的本地开发。

.PARAMETER ModId
  mod 目录名 / mod.json 的 id（如 doom_slayer_izzy）。

.PARAMETER Install
  打包后复制 mod.json(+icon.png)+pck 到 %APPDATA%\Godot\app_userdata\Enter The Nyangeon\mods\<ModId>（重启游戏生效）。

.EXAMPLE
  .\mod_sdk\build_local_mod.ps1 -ModId doom_slayer_izzy
  .\mod_sdk\build_local_mod.ps1 -ModId doom_slayer_izzy -Install
#>
param(
    [Parameter(Mandatory = $true)][string]$ModId,
    [string]$Godot = "H:\Godot_v4.7-stable_win64.exe",
    [string]$Project = "H:\Enter The Nyangeon",
    [switch]$Install
)
# Godot 输出由共用构建契约分类；退出资源计数之外的错误会终止构建。
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "build_common.ps1")
Assert-ModId -ModId $ModId

$proj = (Resolve-Path -LiteralPath $Project).Path
$src = Join-Path $proj "mods\$ModId"
if (-not (Test-Path -LiteralPath (Join-Path $src "mod.json"))) {
    throw "找不到 mod.json：$src\mod.json"
}

# 输出到 mods\_build\（在 gitignore 的 /mods/ 下，保持 git 干净）；勿放进 mod 源目录，否则会被再次打包。
$outDir = Join-Path $proj "mods\_build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$pck = Join-Path $outDir "$ModId.pck"
$buildPck = Join-Path $outDir "$ModId.building.pck"
if (Test-Path -LiteralPath $buildPck) { Remove-Item -LiteralPath $buildPck -Force }

$packer = Join-Path $PSScriptRoot "pack_mod.gd"
Write-Host "打包 pck（PCKPacker）：$pck"
Invoke-CheckedGodot -Godot $Godot -Arguments @('--headless', '--path', $proj, '--script', $packer, '--', "--mod-source=$src", "--out=$buildPck", "--mod-id=$ModId") -Marker 'PACK_MOD:'
Complete-ModPack -Godot $Godot -Project $proj -Candidate $buildPck -Destination $pck

if ($Install) {
    $dest = Join-Path $env:APPDATA "Godot\app_userdata\Enter The Nyangeon\mods\$ModId"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item (Join-Path $src "mod.json") $dest -Force
    Copy-Item $pck (Join-Path $dest "$ModId.pck") -Force
    if (Test-Path -LiteralPath (Join-Path $src "icon.png")) {
        Copy-Item (Join-Path $src "icon.png") $dest -Force
    }
    Write-Host "已安装：$dest（重启游戏生效）"
} else {
    Write-Host "已生成：$pck（加 -Install 可安装到 user://mods）"
}
