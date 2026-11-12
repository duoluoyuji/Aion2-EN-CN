# AION 2 汉化环境诊断（只读，不修改任何游戏文件）
$ErrorActionPreference = 'SilentlyContinue'
$outDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$out = Join-Path $outDir ("AION2汉化诊断_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt")
$lines = New-Object System.Collections.Generic.List[string]
function W($s) { $lines.Add($s); Write-Host $s }

W "AION2 汉化环境诊断（英文入口 / locres 方案）"
W ("时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W ("系统: " + [Environment]::OSVersion.VersionString)
W ""

$roots = New-Object System.Collections.Generic.List[string]
foreach ($id in @('3393110','4972320')) {
    foreach ($k in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $id", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $id")) {
        $v = (Get-ItemProperty -Path $k -Name InstallLocation).InstallLocation
        if ($v -and (Test-Path (Join-Path $v 'Aion2\Content\Paks'))) { $roots.Add($v) }
    }
}
foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
    foreach ($p in @("$($d.Root)SteamLibrary\steamapps\common\Aion2", "$($d.Root)SteamLibrary\steamapps\common\AION2", "$($d.Root)Steam\steamapps\common\Aion2", "$($d.Root)Program Files\NCSOFT\AION2", "$($d.Root)Program Files (x86)\NCSOFT\AION2")) {
        if (Test-Path (Join-Path $p 'Aion2\Content\Paks')) { $roots.Add($p) }
    }
}
$seen = @{}
$roots = @($roots | Where-Object { $k = $_.TrimEnd('\').ToLower(); if ($seen.ContainsKey($k)) { $false } else { $seen[$k] = $true; $true } })
if (-not $roots) { W "未找到游戏目录"; W "" }

foreach ($r in $roots) {
    W ("==== 客户端: " + $r + " ====")
    $loc = Join-Path $r "Engine\Content\Localization\Engine\Platforms\Windows"
    W "-- Engine.locres --"
    foreach ($c in @('en','en-US','ja','ja-JP')) {
        $p = Join-Path $loc "$c\Engine.locres"
        if (Test-Path $p) {
            $i = Get-Item $p
            W ("   " + $c + "\Engine.locres  " + $i.Length + "  " + $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + "  " + (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash)
        } else {
            W ("   " + $c + "\Engine.locres  (不存在)")
        }
    }
    W "-- pak（应保持官方原版） --"
    foreach ($n in @("Aion2\Content\Paks\pakchunk0-Windows.pak", "Aion2\Content\Paks\L10N\Text\en-US\pakchunk502000-Windows_0_P.pak")) {
        $p = Join-Path $r $n
        if (Test-Path $p) {
            W ("   " + (Split-Path $n -Leaf) + "  " + (Get-Item $p).Length + "  " + (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash)
        } else {
            W ("   " + (Split-Path $n -Leaf) + "  (缺失)")
        }
    }
    W ""
}

W "参照值（本工具自带）:"
W "   简体 Engine.locres  15786542 字节"
W "   繁体 Engine.locres  15786612 字节"
W "   en/en-US 两个都是上面尺寸 = 已装汉化；两个都不存在 = 官方英文原版"
W ""
W "生成完毕，请把本文件发给作者。"
[System.IO.File]::WriteAllLines($out, $lines, (New-Object System.Text.UTF8Encoding($true)))
Write-Host ""
Write-Host ("诊断文件已生成: " + $out) -ForegroundColor Green
Write-Host "请把这个 txt 文件发给作者。" -ForegroundColor Yellow
