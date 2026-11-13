#requires -Version 4.0
# AION2 汉化一键诊断（只读，不修改任何游戏文件）
# 输出：同目录 AION2汉化诊断_时间.txt，把该文件发给作者即可
#
# 判断依据（不读取作者本机的任何状态）：
#   1. 工具包完整性：跟脚本里写死的载荷尺寸/SHA256 比对（这两个值就是随包发布的那两个文件）
#   2. 汉化是否装对：比对游戏里 en / en-US 的 Engine.locres 是否等于上面两个载荷
#   3. 游戏原始文件：只有「尺寸与基准完全相同、内容却不同」才判为被改动；
#      尺寸不同一律视为游戏已更新，只记录、不报错（避免更新后全员误报）
#   4. 其余为固定规则：目录能否写入、存档语言、旧方案残留、日志关键词
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$ToolName = 'AION2 英文入口汉化工具'

# ===== 载荷基准（与 build.ps1 打包内容必须一致）=====
$ZH = @{ Rel = 'zh\Engine.locres';    Size = 15786542; Hash = '20169D244C1FB9D578FD91278E678C9E44041FC8414A255C5253AB21F6C1568F' }
$TW = @{ Rel = 'zh-TW\Engine.locres'; Size = 15786612; Hash = '97695A94DD5806978F64D412672B59A122ECD74123A3C5A3845411307ADB2DF8' }

# ===== 游戏原始文件基准（仅用于识别「被旧方案原地改过」，不用于判定游戏版本）=====
# 游戏每次更新 pak 都会变，所以这里只在「尺寸相同、内容不同」时才判为被改动；
# 尺寸不同说明版本不一样，属正常情况，不报错。
$OFFICIAL = @{
    'Aion2\Content\Paks\pakchunk0-Windows.pak'                          = @{ Size = 34330774; Hash = '6B0C57CC50F949EDB4F47D0A04E859951E2213130FD415D6B19B195767565681' }
    'Aion2\Content\Paks\L10N\Text\en-US\pakchunk502000-Windows_0_P.pak' = @{ Size = 3980982;  Hash = '94F59B218B42CEC2ADD7B0275C6A105CEB3A0A3D92075A1FA621FE4DE06822B8' }
}

$LOC_CULTURES = @('en', 'en-US')

$outDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outFile = Join-Path $outDir ("AION2汉化诊断_" + $stamp + ".txt")

$lines = New-Object System.Collections.Generic.List[string]
$detail = New-Object System.Collections.Generic.List[string]
$problems = New-Object System.Collections.Generic.List[object]

function D([string]$s) { $detail.Add($s) }
function AddProblem([string]$text, [string]$advice, [string]$level) {
    $problems.Add([pscustomobject]@{ Text = $text; Advice = $advice; Level = $level })
}
function Sha([string]$p) {
    try { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } catch { return '' }
}
function Line([string]$s) { Write-Host $s }

# =========================================================
# 一、工具包自检
# =========================================================
$pkgNeeded = @(
    '1-图形版-双击启动.exe',
    'Aion2CNTool.ps1',
    'Aion2Diag.ps1',
    '2-窗口版-安装简体中文.bat',
    '2-窗口版-安装繁体中文.bat',
    '3-窗口版-还原官方英文.bat',
    '0-使用说明（先看这里）.txt',
    'zh\Engine.locres',
    'zh-TW\Engine.locres'
)

D '【一、工具包自检】'
$missing = @()
foreach ($rel in $pkgNeeded) {
    $p = Join-Path $outDir $rel
    if (-not (Test-Path -LiteralPath $p)) {
        $missing += $rel
        D ("   缺失: " + $rel)
        continue
    }
    $i = Get-Item -LiteralPath $p
    $h = ''
    if ($rel -like '*.locres') { $h = Sha $p }
    D ("   " + $rel + " | " + $i.Length + " B | " + $h)
}
foreach ($x in @($ZH, $TW)) {
    $p = Join-Path $outDir $x.Rel
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $i = Get-Item -LiteralPath $p
    if ($i.Length -ne $x.Size) {
        AddProblem ("工具包里的 " + $x.Rel + " 大小不对（" + $i.Length + " 字节，应为 " + $x.Size + " 字节）") '请重新解压，或重新下载完整压缩包' 'error'
    } elseif ((Sha $p) -ne $x.Hash) {
        AddProblem ("工具包里的 " + $x.Rel + " 内容损坏") '请重新下载完整压缩包（不要用下载器续传的残缺文件）' 'error'
    }
}
if ($missing.Count -gt 0) {
    AddProblem ("工具包缺少 " + $missing.Count + " 个文件：" + ($missing -join '、')) '请重新解压压缩包，确保整个文件夹一起解压' 'error'
}
$verFile = Join-Path $outDir 'Aion2CNTool.ps1'
$toolVer = ''
if (Test-Path -LiteralPath $verFile) {
    $m = [regex]::Match((Get-Content -LiteralPath $verFile -Raw), "CurrentVersion\s*=\s*'([\d\.]+)'")
    if ($m.Success) { $toolVer = $m.Groups[1].Value }
}
D ("   工具版本: v" + $toolVer)

# =========================================================
# 二、系统环境
# =========================================================
D ''
D '【二、系统环境】'
$osName = 'Windows'
$osBuild = ''
$disp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
$build = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
if ($build) { $osBuild = $build }
D ("   " + [Environment]::OSVersion.VersionString + " | DisplayVersion=" + $disp + " | Build=" + $osBuild)
D ("   PowerShell " + $PSVersionTable.PSVersion.ToString() + " | 执行策略 " + (Get-ExecutionPolicy))
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
D ("   管理员权限: " + $isAdmin)

$avList = @()
try {
    $av = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct
    foreach ($a in $av) { $avList += $a.displayName }
} catch { }
if ($avList.Count -gt 0) { D ("   安全软件: " + ($avList -join '、')) } else { D '   安全软件: 未读取到' }

D ("   系统时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

# =========================================================
# 三、客户端发现
# =========================================================
function Test-ClientRoot([string]$p) {
    if (-not $p) { return $false }
    return (Test-Path -LiteralPath (Join-Path $p 'Aion2\Content\Paks'))
}

function Get-SteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath).SteamPath
    if ($steamPath) { $libs.Add($steamPath) }
    foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        $v = (Get-ItemProperty $k -Name InstallPath).InstallPath
        if ($v) { $libs.Add($v) }
    }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($l in $libs) {
        $lf = Join-Path $l 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $lf)) { continue }
        $raw = Get-Content -LiteralPath $lf -Raw
        foreach ($m in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) { $result.Add(($m.Groups[1].Value -replace '\\\\', '\')) }
    }
    return $result
}

$candidates = New-Object System.Collections.Generic.List[object]
function Add-Candidate([string]$path, [string]$source) {
    if (-not $path) { return }
    $path = $path.TrimEnd('\')
    if (-not (Test-ClientRoot $path)) { return }
    foreach ($c in $candidates) {
        if ($c.Path.TrimEnd('\').ToLower() -eq $path.ToLower()) { return }
    }
    $candidates.Add([pscustomobject]@{ Path = $path; Source = $source })
}

foreach ($id in @('3393110', '4972320')) {
    foreach ($k in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $id", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $id")) {
        $v = (Get-ItemProperty -Path $k -Name InstallLocation).InstallLocation
        Add-Candidate $v 'Steam 注册表'
    }
}
foreach ($lib in (Get-SteamLibraries)) {
    foreach ($n in @('Aion2', 'AION2')) {
        Add-Candidate (Join-Path $lib ("steamapps\common\" + $n)) 'Steam 库目录'
    }
}
foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
    foreach ($p in @(
        "$($d.Root)SteamLibrary\steamapps\common\Aion2", "$($d.Root)SteamLibrary\steamapps\common\AION2",
        "$($d.Root)Steam\steamapps\common\Aion2", "$($d.Root)Steam\steamapps\common\AION2",
        "$($d.Root)Program Files\NCSOFT\AION2", "$($d.Root)Program Files (x86)\NCSOFT\AION2",
        "$($d.Root)NCSOFT\AION2", "$($d.Root)Purple\AION2", "$($d.Root)Games\AION2")) {
        Add-Candidate $p '磁盘扫描'
    }
}
foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\Plaync\Purple\Auth', 'HKLM:\SOFTWARE\Plaync\Purple\Auth')) {
    $v = (Get-ItemProperty $k -Name BaseDir).BaseDir
    if ($v) {
        Add-Candidate (Join-Path $v 'AION2') 'PURPLE 注册表'
        Add-Candidate (Join-Path $v 'Games\AION2') 'PURPLE 注册表'
    }
}

$procNames = @()
foreach ($pn in @('Aion2*', 'Steam', 'Purple', 'PurpleLauncher')) {
    $ps = Get-Process -Name $pn
    foreach ($q in $ps) { $procNames += $q.ProcessName }
}
$procNames = @($procNames | Sort-Object -Unique)

D ''
D '【三、客户端发现】'
D ("   找到客户端: " + $candidates.Count + " 个")
foreach ($c in $candidates) { D ("   - " + $c.Path + "  （来源: " + $c.Source + "）") }
if ($procNames.Count -gt 0) { D ("   正在运行: " + ($procNames -join '、')) } else { D '   正在运行: 无' }

if ($candidates.Count -eq 0) {
    AddProblem '没有找到游戏客户端' '请确认游戏已安装，并在工具里手动选择游戏目录（SteamLibrary\steamapps\common\Aion2）' 'error'
}

# =========================================================
# 四、安装状态 + 五、存档配置
# =========================================================
function Get-ClientState($root) {
    $states = New-Object System.Collections.Generic.List[string]
    $hasZh = $false
    $hasTw = $false
    $hasUnknown = $false
    $locRoot = Join-Path $root 'Engine\Content\Localization\Engine\Platforms\Windows'
    $locState = '不存在'
    if (Test-Path -LiteralPath $locRoot) { $locState = '存在' }
    D ("   Localization 目录: " + $locState)
    foreach ($c in $LOC_CULTURES) {
        $p = Join-Path $locRoot ("$c\Engine.locres")
        if (-not (Test-Path -LiteralPath $p)) {
            D ("   " + $c + "\Engine.locres: 不存在")
            continue
        }
        $i = Get-Item -LiteralPath $p
        $h = Sha $p
        $tag = '未知汉化文件'
        if ($h -eq $ZH.Hash) { $tag = '本工具简体'; $hasZh = $true }
        elseif ($h -eq $TW.Hash) { $tag = '本工具繁体'; $hasTw = $true }
        else { $hasUnknown = $true }
        D ("   " + $c + "\Engine.locres: " + $i.Length + " B | " + $h + " | " + $tag)
    }

    # 写权限实测
    $wtest = Join-Path $root ('_aion2_wtest_' + $stamp + '.tmp')
    $writable = $false
    try {
        [System.IO.File]::WriteAllText($wtest, 'test')
        $writable = $true
    } catch { $writable = $false }
    if (Test-Path -LiteralPath $wtest) { Remove-Item -LiteralPath $wtest -Force }
    $wtext = '写入失败'
    if ($writable) { $wtext = '可写入' }
    D ("   目录写测试: " + $wtext)

    # pak 是否被旧方案改过（只在「尺寸相同、内容不同」时判定，游戏更新不误报）
    $pakBad = @()
    foreach ($rel in $OFFICIAL.Keys) {
        $base = $OFFICIAL[$rel]
        $leaf = Split-Path $rel -Leaf
        $p = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $p)) {
            $pakBad += ($leaf + ' 缺失')
            D ("   文件 " + $leaf + ": 缺失")
            continue
        }
        $i = Get-Item -LiteralPath $p
        if ($i.Length -ne $base.Size) {
            D ("   文件 " + $leaf + ": 与工具记录版本不同（" + $i.Length + " B，游戏可能已更新，属正常）")
            continue
        }
        if ((Sha $p) -ne $base.Hash) {
            $pakBad += ($leaf + ' 被改动')
            D ("   文件 " + $leaf + ": 已被改动（尺寸相同、内容不同）")
        } else {
            D ("   文件 " + $leaf + ": 官方原版")
        }
    }

    # 旧方案残留
    $leftover = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath (Join-Path $root 'Aion2_Japanese_Backup_Safe')) { $leftover.Add('Aion2_Japanese_Backup_Safe 备份目录') }
    $paksDir = Join-Path $root 'Aion2\Content\Paks'
    if (Test-Path -LiteralPath $paksDir) {
        $baks = Get-ChildItem -LiteralPath $paksDir -Recurse -Filter '*.bak'
        if ($baks) { $leftover.Add($baks.Count.ToString() + ' 个 .bak 备份文件') }
        $ja = Join-Path $paksDir 'L10N\Text\ja-JP'
        if (Test-Path -LiteralPath $ja) {
            $jap = Get-ChildItem -LiteralPath $ja -Filter 'packchunk503000*'
            if ($jap) { $leftover.Add('ja-JP 日文语言包已被替换') }
        }
    }
    $otherLoc = @()
    if (Test-Path -LiteralPath $locRoot) {
        $otherLoc = @(Get-ChildItem -LiteralPath $locRoot -Directory | Where-Object { $LOC_CULTURES -notcontains $_.Name } | ForEach-Object { $_.Name })
    }

    # 存档 Culture
    $culture = ''
    $iniCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Aion2\Saved_Steam\Config\Windows\Engine.ini'),
        (Join-Path $env:LOCALAPPDATA 'Aion2\Saved\Config\Windows\Engine.ini')
    )
    $iniUsed = ''
    foreach ($ini in $iniCandidates) {
        if (Test-Path -LiteralPath $ini) {
            $iniUsed = $ini
            $m = [regex]::Match((Get-Content -LiteralPath $ini -Raw), 'Culture\s*=\s*([A-Za-z\-]+)')
            if ($m.Success) { $culture = $m.Groups[1].Value }
            break
        }
    }

    return [pscustomobject]@{
        HasZh = $hasZh; HasTw = $hasTw; HasUnknown = $hasUnknown; Writable = $writable
        LocExists = (Test-Path -LiteralPath $locRoot); PakBad = $pakBad; Leftover = $leftover
        OtherCultures = $otherLoc; Culture = $culture; IniUsed = $iniUsed
    }
}

$installedAny = $false
$idx = 0
foreach ($c in $candidates) {
    $idx++
    D ''
    D ("【四、安装状态 · 客户端 " + $idx + "】" + $c.Path)
    $s = Get-ClientState $c.Path
    $ocText = '无'
    if ($s.OtherCultures.Count -gt 0) { $ocText = ($s.OtherCultures -join '、') }
    D ("   其它语言目录: " + $ocText)
    $lfText = '无'
    if ($s.Leftover.Count -gt 0) { $lfText = ($s.Leftover -join '、') }
    D ("   旧方案残留: " + $lfText)
    $cuText = '未读取到（游戏未运行过属正常）'
    if ($s.Culture) { $cuText = $s.Culture + '  (' + $s.IniUsed + ')' }
    D ("   存档 Culture: " + $cuText)

    if ($s.HasZh -or $s.HasTw) { $installedAny = $true }
    if ($s.HasZh -or $s.HasTw) {
        if ($s.Culture -and $s.Culture -ne 'en-US' -and $s.Culture -ne 'en') {
            AddProblem ('汉化文件已安装，但游戏语言被设成了 ' + $s.Culture) '把游戏内语言切回 English，或在启动器里改回英文后重启游戏' 'warn'
        }
    }
    if ($s.PakBad.Count -gt 0) {
        AddProblem ('游戏原始文件与官方不一致：' + ($s.PakBad -join '、')) '本方案不改 pak；若装过旧日文方案请先还原，再用 Steam 验证文件完整性后重新安装' 'warn'
    }
    if (-not $s.LocExists -and -not $s.HasZh -and -not $s.HasTw) {
        D '   说明: 没有 Localization 目录 = 从未安装过本汉化，属正常'
    }
    if (-not $s.Writable) {
        AddProblem ('游戏目录无法写入：' + $c.Path) '关闭杀毒软件/安全卫士后重试，或用管理员身份运行工具' 'error'
    }
    if ($s.HasUnknown) {
        AddProblem ('游戏里装的是来路不明的汉化文件：' + $c.Path) '先点「一键还原官方英文」，再重新安装本工具' 'warn'
    }
    if ($s.Culture -and $s.Culture -ne 'en-US' -and $s.Culture -ne 'en' -and -not $s.HasZh -and -not $s.HasTw) {
        AddProblem ('游戏语言被设成了 ' + $s.Culture + '，本方案只对英文客户端生效') '把游戏语言改回 English（本工具不支持日文/韩文入口）' 'warn'
    }
}

# =========================================================
# 六、工具日志
# =========================================================
D ''
D '【五、工具日志】'
$logPath = Join-Path $outDir '汉化日志.txt'
if (Test-Path -LiteralPath $logPath) {
    $tail = Get-Content -LiteralPath $logPath -Tail 30
    foreach ($t in $tail) { D ('   | ' + $t) }
    $all = Get-Content -LiteralPath $logPath -Raw
    $hits = @()
    foreach ($kw in @('拒绝访问', 'UnauthorizedAccess', 'IOException', '正在使用', '错误', '失败')) {
        if ($all -match $kw) { $hits += $kw }
    }
    if ($hits.Count -gt 0) { D ('   命中关键词: ' + ($hits -join '、')) }
} else {
    D '   未找到 汉化日志.txt（说明工具可能从未成功运行过安装/还原）'
}

# =========================================================
# 汇总输出
# =========================================================
$head = New-Object System.Collections.Generic.List[string]
$head.Add($ToolName + ' · 一键诊断报告')
$head.Add('生成时间: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$head.Add('')
$head.Add('==================== ① 结论 ====================')
if ($problems.Count -eq 0) {
    if ($candidates.Count -eq 0) {
        $head.Add('结论：没有找到游戏客户端。')
        $head.Add('建议：确认游戏装在哪，再用工具手动选择游戏目录。')
    } elseif (-not $installedAny) {
        $head.Add('结论：游戏目前是官方英文，没有检测到汉化文件。')
        $head.Add('建议：用本工具点一次「一键应用【简体中文】」或「繁体中文」，然后直接启动游戏。')
    } else {
        $head.Add('结论：一切正常，汉化文件已正确安装。')
        $head.Add('建议：直接启动游戏；如果游戏内仍是英文，请确认启动的是同一个客户端。')
    }
} else {
    $err = @($problems | Where-Object { $_.Level -eq 'error' })
    $first = if ($err.Count -gt 0) { $err[0] } else { $problems[0] }
    $head.Add('结论：' + $first.Text)
    $head.Add('建议：' + $first.Advice)
    $others = @($problems | Where-Object { $_ -ne $first })
    if ($others.Count -gt 0) {
        $head.Add('')
        $head.Add('另外还发现：')
        foreach ($o in $others) { $head.Add('  · ' + $o.Text + '  →  ' + $o.Advice) }
    }
}
$head.Add('')
$head.Add('==================== ② 详细清单 ====================')

$all = New-Object System.Collections.Generic.List[string]
foreach ($h in $head) { $all.Add($h) }
foreach ($d in $detail) { $all.Add($d) }
$all.Add('')
$all.Add('==================== ③ 工具包文件 ====================')
foreach ($rel in $pkgNeeded) {
    $p = Join-Path $outDir $rel
    if (Test-Path -LiteralPath $p) { $all.Add('   ' + $rel + ' | ' + (Get-Item -LiteralPath $p).Length + ' B') }
    else { $all.Add('   ' + $rel + ' | 缺失') }
}
$all.Add('')
$all.Add('生成完毕，请把本文件发给作者。')

foreach ($h in $head) { Line $h }
foreach ($d in $detail) { Line $d }
Line ''
Line '==================== ③ 工具包文件 ===================='
foreach ($rel in $pkgNeeded) {
    $p = Join-Path $outDir $rel
    if (Test-Path -LiteralPath $p) { Line ('   ' + $rel + ' | ' + (Get-Item -LiteralPath $p).Length + ' B') }
}
Line ''
[System.IO.File]::WriteAllLines($outFile, $all, (New-Object System.Text.UTF8Encoding($true)))
Line ''
Write-Host ('诊断文件已生成: ' + $outFile) -ForegroundColor Green
Write-Host '请把这个 txt 文件发给作者。' -ForegroundColor Yellow
if ($problems.Count -gt 0) { exit 1 } else { exit 0 }
