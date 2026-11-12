# -*- coding: utf-8 -*-
# AION 2 (Steam / PURPLE 正式版·英文入口) 简繁双语一键汉化与还原工具
# 作者: B站@吃素的佩奇
# 开源主页: https://github.com/duoluoyuji/Aion2-EN-CN

param(
    [switch]$Install,
    [switch]$Restore,
    [string]$Lang = ""
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ToolDir        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ZhDir          = Join-Path $ToolDir 'zh'
$ZhTwDir        = Join-Path $ToolDir 'zh-TW'
# 英文入口唯一可用的汉化通道：这两个 Engine.locres。删掉即回落官方英文，不需要备份、也不碰任何 pak。
$LocresRel = @(
    'Engine\Content\Localization\Engine\Platforms\Windows\en\Engine.locres',
    'Engine\Content\Localization\Engine\Platforms\Windows\en-US\Engine.locres'
)
$LangName       = '简体中文'
$ActiveSourceDir = $ZhDir
if ($Lang -eq 'zh-TW' -or $Lang -eq 'tw' -or $Lang -eq 'cht') {
    $ActiveSourceDir = $ZhTwDir
    $LangName = '繁体中文'
}
$CurrentVersion = '2.0.0'
# 3393110 为 Steam 正式服 AppID，4972320 为 Steam Playtest 测试服 AppID
$AppIds         = @('3393110', '4972320')
$RemoteVersionUrl   = 'https://raw.githubusercontent.com/duoluoyuji/Aion2-EN-CN/main/version.json'
$FallbackVersionUrl = 'https://gh-proxy.com/https://raw.githubusercontent.com/duoluoyuji/Aion2-EN-CN/main/version.json'

# ==================== 客户端状态检测 ====================
function Get-Sha256([string]$Path) {
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } catch { return '' }
}

function Get-ClientState([string]$Root) {
    if (-not (Test-Path (Join-Path $Root "Aion2\Content\Paks\L10N"))) { return '目录无效' }

    $zh = Get-Sha256 (Join-Path $ZhDir 'Engine.locres')
    $tw = Get-Sha256 (Join-Path $ZhTwDir 'Engine.locres')
    $vals = @()
    foreach ($rel in $LocresRel) {
        $p = Join-Path $Root $rel
        $vals += if (Test-Path $p) { Get-Sha256 $p } else { '' }
    }
    if (($vals | Where-Object { $_ }).Count -eq 0) { return '官方英文原版' }
    if ($zh -and ($vals | Where-Object { $_ -ne $zh }).Count -eq 0) { return '本工具简体中文' }
    if ($tw -and ($vals | Where-Object { $_ -ne $tw }).Count -eq 0) { return '本工具繁体中文' }
    return '未知汉化文件'
}

# 还原 = 删掉那两个 Engine.locres。删掉即回落官方英文，不需要任何备份。
function Restore-ClientFiles([string]$Root) {
    $removed = $false
    foreach ($rel in $LocresRel) {
        $p = Join-Path $Root $rel
        if (Test-Path $p) {
            Set-ItemProperty -Path $p -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $p)) { $removed = $true }
        }
    }
    return $removed
}

# ==================== 控制台作者署名横幅 ====================
function Show-Banner {
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host "      AION 2 (Steam / PURPLE 正式版) 简繁双语一键汉化工具 · 英文入口 v$CurrentVersion" -ForegroundColor Cyan
    Write-Host "      制作团队: 吃素的佩奇汉化" -ForegroundColor Gray
    Write-Host "      开源主页: https://github.com/duoluoyuji/Aion2-EN-CN" -ForegroundColor Gray
    Write-Host "      【声明】本工具完全免费分享，仅供交流学习，严禁倒卖牟利！" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host ""
}

# ==================== 在线版本检测与自动更新提醒 ====================
function Check-Update {
    Write-Host "[0/4] 正在检查最新版本更新与公告..." -ForegroundColor DarkGray
    $remoteJson = $null
    $urls = @($RemoteVersionUrl, $FallbackVersionUrl)
    try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]3072 } catch {}
    
    foreach ($u in $urls) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.Timeout = 3000
            $req.UserAgent = "Aion2CNTool"
            $resp = $req.GetResponse()
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $txt = $sr.ReadToEnd()
            $sr.Close()
            $resp.Close()
            if ($txt) {
                $remoteJson = ConvertFrom-Json $txt
                break
            }
        } catch {}
    }

    if ($remoteJson) {
        $shouldUpdate = $false
        try {
            $rv = [System.Version]$remoteJson.version
            $lv = [System.Version]$CurrentVersion
            if ($rv -gt $lv) {
                $shouldUpdate = $true
            }
        } catch {
            # 容错：若版本号非标准四段/三段数字，则仅当非自身且非旧版本时处理
            if ($remoteJson.version -and ($remoteJson.version -ne $CurrentVersion) -and ($remoteJson.version -ne '1.1.1') -and ($remoteJson.version -ne '1.1.0')) {
                $shouldUpdate = $true
            }
        }

        if ($shouldUpdate) {
            Write-Host ">>> 发现新版本: v$($remoteJson.version)！" -ForegroundColor Yellow
            $tip = "发现 AION 2 汉化工具最新版本：v$($remoteJson.version)`n`n公告内容：`n$($remoteJson.announcement)`n`n是否立即打开下载页面？"
            $box = [System.Windows.Forms.MessageBox]::Show($tip, "版本更新提示 - B站@吃素的佩奇", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($box -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Start-Process "https://github.com/duoluoyuji/Aion2-EN-CN/releases"
                } catch {
                    try {
                        [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo("https://github.com/duoluoyuji/Aion2-EN-CN/releases") -Property @{UseShellExecute=$true}))
                    } catch {}
                }
            }
        } else {
            Write-Host "-> 当前已是最新正式版本 (v$CurrentVersion)。" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "-> 网络检测超时，使用离线模式继续运行。" -ForegroundColor DarkGray
    }
}

# ==================== 扫描全盘所有已安装的 AION 2 版本 ====================
function Get-AllGameRoots {
    $detected = @()
    $fixedDrives = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null -and $_.Root }).Root
    
    # ---------------- 1. 扫描 Steam 游戏库 ----------------
    $steamRoots = @()
    foreach ($d in $fixedDrives) {
        $candidates = @(
            (Join-Path $d 'SteamLibrary\steamapps'),
            (Join-Path $d 'steamapps'),
            (Join-Path $d 'Program Files (x86)\Steam\steamapps'),
            (Join-Path $d 'Program Files\Steam\steamapps'),
            (Join-Path $d 'Steam\steamapps')
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $steamRoots += $c }
        }
    }
    
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg -and $reg.SteamPath) {
            $regApps = Join-Path $reg.SteamPath 'steamapps'
            if (Test-Path $regApps) { $steamRoots += $regApps }
        }
    } catch {}

    $steamRoots = $steamRoots | Select-Object -Unique

    foreach ($r in $steamRoots) {
        foreach ($aid in $AppIds) {
            $acf = Join-Path $r "appmanifest_$aid.acf"
            if (Test-Path $acf) {
                try {
                    $txt = Get-Content $acf -Raw -ErrorAction SilentlyContinue
                    if ($txt -match '"installdir"\s+"([^"]+)"') {
                        $gameAbs = Join-Path (Join-Path $r 'common') $matches[1]
                        if (Test-Path (Join-Path $gameAbs 'Aion2\Content\Paks\L10N')) {
                            $label = if ($aid -eq '3393110') { "Steam 国际正式版" } else { "Steam 测试服版" }
                            if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $gameAbs.ToLower() })) {
                                $detected += [PSCustomObject]@{
                                    Platform = $label
                                    Path     = $gameAbs
                                    Type     = "Steam"
                                }
                            }
                        }
                    }
                } catch {}
            }
        }

        $common = Join-Path $r 'common'
        if (Test-Path $common) {
            $hits = Get-ChildItem $common -Directory -ErrorAction SilentlyContinue | Where-Object {
                Test-Path (Join-Path $_.FullName 'Aion2\Content\Paks\L10N')
            }
            foreach ($h in $hits) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $h.FullName.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "Steam 游戏库 ($($h.Name))"
                        Path     = $h.FullName
                        Type     = "Steam"
                    }
                }
            }
        }
    }

    # ---------------- 2. 三重增强：扫描 NCSoft PURPLE (紫P) 客户端 ----------------
    # 增强 1：从 plaync 官方注册表枚举 BaseDir
    $playncRegKeys = @(
        "HKLM:\SOFTWARE\plaync",
        "HKLM:\SOFTWARE\WOW6432Node\plaync",
        "HKCU:\SOFTWARE\plaync"
    )
    foreach ($rk in $playncRegKeys) {
        try {
            if (Test-Path $rk) {
                $subKeys = Get-ChildItem -Path $rk -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($props -and $props.BaseDir) {
                        $bPath = $props.BaseDir.ToString().TrimEnd('\')
                        if (Test-Path (Join-Path $bPath 'Aion2\Content\Paks\L10N')) {
                            if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $bPath.ToLower() })) {
                                $detected += [PSCustomObject]@{
                                    Platform = "NCSoft PURPLE 国际服 (注册表定位)"
                                    Path     = $bPath
                                    Type     = "PURPLE"
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 增强 2：从 Windows 软件卸载列表中精确匹配 AION 2 / PURPLE 安装目录
    $uninstallRegKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($uk in $uninstallRegKeys) {
        try {
            if (Test-Path $uk) {
                $subKeys = Get-ChildItem -Path $uk -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($props) {
                        $dName = $props.DisplayName
                        $iLoc = $props.InstallLocation
                        if ($dName -and ($dName -like "*AION*" -or $dName -like "*Purple*") -and $iLoc) {
                            $cleanLoc = $iLoc.ToString().TrimEnd('\')
                            if (Test-Path (Join-Path $cleanLoc 'Aion2\Content\Paks\L10N')) {
                                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $cleanLoc.ToLower() })) {
                                    $detected += [PSCustomObject]@{
                                        Platform = "NCSoft PURPLE 国际服 (系统识别)"
                                        Path     = $cleanLoc
                                        Type     = "PURPLE"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 增强 3：全盘常见默认路径深度匹配池
    foreach ($d in $fixedDrives) {
        $purpleCandidates = @(
            (Join-Path $d 'AION 2'),
            (Join-Path $d 'Aion2'),
            (Join-Path $d 'Games\AION 2'),
            (Join-Path $d 'Games\Aion2'),
            (Join-Path $d 'PurpleGames\AION 2'),
            (Join-Path $d 'PurpleGames\Aion2'),
            (Join-Path $d 'Purple\Games\AION 2'),
            (Join-Path $d 'NC\AION 2'),
            (Join-Path $d 'NCSOFT\AION 2'),
            (Join-Path $d 'NCSOFT\Purple\Games\AION 2'),
            (Join-Path $d 'Program Files\NCSOFT\Purple\AION 2'),
            (Join-Path $d 'Program Files (x86)\NCSOFT\Purple\AION 2')
        )
        foreach ($pc in $purpleCandidates) {
            if (Test-Path (Join-Path $pc 'Aion2\Content\Paks\L10N')) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $pc.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "NCSoft PURPLE 国际服 (磁盘扫描)"
                        Path     = $pc
                        Type     = "PURPLE"
                    }
                }
            }
        }
    }

    return $detected
}

# 手动选择游戏目录保底
function Select-GameFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "未自动检测到游戏安装位置。`n请手动选择 AION 2 游戏根目录（包含 Aion2 文件夹的那一层，名字通常为 AION 2 或 AION 2 Playtest）："
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq 'OK') {
        $sel = $dlg.SelectedPath
        if (Test-Path (Join-Path $sel 'Aion2\Content\Paks\L10N')) {
            return $sel
        } else {
            [System.Windows.Forms.MessageBox]::Show("所选目录不是有效的 AION 2 游戏根目录！`n该目录下必须包含 Aion2 文件夹。", "错误 - B站@吃素的佩奇", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return $null
        }
    }
    return $null
}

# ==================== 智能版本决策与多版本选择窗口 ====================
function Select-TargetGameRoots {
    param([string]$ActionName = "汉化")

    $all = @(Get-AllGameRoots)

    # 场景 0: 全盘未搜到任何版本 -> 弹窗手动选择
    if ($all.Count -eq 0) {
        Write-Host "未能自动定位到游戏安装路径，请在弹出的窗口中手动指定..." -ForegroundColor Yellow
        $manual = Select-GameFolder
        if ($manual) {
            return @($manual)
        }
        return @()
    }

    # 场景 1: 只检测到 1 个版本 -> 直接自动采用，无需用户费神多点一次
    if ($all.Count -eq 1) {
        Write-Host "-> 检测到唯一安装版本: $($all[0].Platform) [$($all[0].Path)]" -ForegroundColor Green
        return @($all[0].Path)
    }

    # 场景 2: 检测到 2 个或以上不同版本 (例如同时存在 Steam 与 PURPLE) -> 弹出交互窗口让用户勾选
    Write-Host ">>> 检测到电脑中安装了多个不同版本的 AION 2 ($($all.Count) 个)，正在弹出选择窗口..." -ForegroundColor Cyan

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AION 2 游戏版本选择 - B站@吃素的佩奇"
    $formHeight = 310 + ($all.Count * 45)
    $form.Size = New-Object System.Drawing.Size(650, $formHeight)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)

    # 顶部横幅
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 70
    $banner.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 45)
    $form.Controls.Add($banner)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "检测到多个游戏版本，请选择要【$ActionName】的目标："
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $title.AutoSize = $true
    $banner.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = "您可以在下方选择其中一个版本，或选择「同时处理全部版本」"
    $subtitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 190)
    $subtitle.Location = New-Object System.Drawing.Point(22, 42)
    $subtitle.AutoSize = $true
    $banner.Controls.Add($subtitle)

    # 中部列表单选区
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(25, 15, 25, 10)
    $form.Controls.Add($body)
    $form.Controls.SetChildIndex($body, 0)

    $radioList = @()
    $y = 15

    for ($i = 0; $i -lt $all.Count; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = "$($all[$i].Platform)  |  $($all[$i].Path)"
        $rb.Location = New-Object System.Drawing.Point(25, $y)
        $rb.Size = New-Object System.Drawing.Size(580, 36)
        $rb.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 240)
        $rb.Tag = @($all[$i].Path)
        if ($i -eq 0) { $rb.Checked = $true } # 默认高亮排在第一顺位的版本
        $body.Controls.Add($rb)
        $radioList += $rb
        $y += 42
    }

    # 选项：同时处理全部版本 (两端均生效)
    $rbAll = New-Object System.Windows.Forms.RadioButton
    $rbAll.Text = "★ 同时${ActionName}以上全部版本 (推荐，两端都享受中文)"
    $rbAll.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $rbAll.Location = New-Object System.Drawing.Point(25, $y)
    $rbAll.Size = New-Object System.Drawing.Size(580, 36)
    $rbAll.ForeColor = [System.Drawing.Color]::FromArgb(255, 215, 0)
    $allPaths = @($all | ForEach-Object { $_.Path })
    $rbAll.Tag = $allPaths
    $body.Controls.Add($rbAll)
    $radioList += $rbAll

    # 底部按钮栏
    $btnRow = New-Object System.Windows.Forms.Panel
    $btnRow.Dock = 'Bottom'
    $btnRow.Height = 60
    $btnRow.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $form.Controls.Add($btnRow)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "确认执行"
    $btnOk.DialogResult = 'OK'
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = 'Flat'
    $btnOk.Location = New-Object System.Drawing.Point(390, 14)
    $btnOk.Size = New-Object System.Drawing.Size(110, 32)
    $btnRow.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "取消"
    $btnCancel.DialogResult = 'Cancel'
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.Location = New-Object System.Drawing.Point(515, 14)
    $btnCancel.Size = New-Object System.Drawing.Size(95, 32)
    $btnRow.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $dialogRes = $form.ShowDialog()
    if ($dialogRes -eq 'OK') {
        foreach ($rb in $radioList) {
            if ($rb.Checked) {
                return $rb.Tag
            }
        }
    }

    Write-Host "用户已取消版本选择。" -ForegroundColor Yellow
    return @()
}

# ==================== 专属定制免责声明弹窗 ====================
function Show-Disclaimer {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AION 2 正式版汉化工具 - 制作: B站@吃素的佩奇"
    $form.Size = New-Object System.Drawing.Size(580, 480)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24,24,28)

    # 顶部横幅
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 65
    $banner.BackColor = [System.Drawing.Color]::FromArgb(35,35,45)
    $form.Controls.Add($banner)

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = '!'
    $icon.Font = New-Object System.Drawing.Font('Arial', 24, [System.Drawing.FontStyle]::Bold)
    $icon.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $icon.Location = New-Object System.Drawing.Point(16,12)
    $icon.Size = New-Object System.Drawing.Size(36,40)
    $icon.TextAlign = 'MiddleCenter'
    $banner.Controls.Add($icon)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '重要操作风险说明 (英文入口 · Steam / PURPLE 通用)'
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $title.Location = New-Object System.Drawing.Point(58,16)
    $title.AutoSize = $true
    $banner.Controls.Add($title)

    # 中部说明文字区
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.BackColor = [System.Drawing.Color]::FromArgb(28,28,34)
    $body.Padding = New-Object System.Windows.Forms.Padding(20,12,20,0)
    $form.Controls.Add($body)
    $form.Controls.SetChildIndex($body, 0)

    $items = @(
        '1. 本工具只适用【英文客户端】：游戏内语言保持 English，装完直接启动即为中文。',
        '2. 本工具只向游戏目录写入 Engine.locres 两个本地化文件，不改动任何 pak 与字体。',
        '3. 任何客户端修改都可能违反游戏服务条款，相关风险由使用者自行承担。',
        '4. 执行过程中请勿启动游戏或中断任务，避免客户端文件损坏。',
        '5. 删掉这两个文件即回落官方英文，可用「一键还原官方英文」随时恢复。'
    )
    $y = 12
    foreach ($it in $items) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $it
        $l.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        $l.ForeColor = [System.Drawing.Color]::FromArgb(220,220,225)
        $l.AutoSize = $false
        $l.Location = New-Object System.Drawing.Point(16,$y)
        $l.Size = New-Object System.Drawing.Size(515,50)
        $l.TextAlign = 'TopLeft'
        $body.Controls.Add($l)
        $y += 56
    }

    # 声明栏
    $authorBanner = New-Object System.Windows.Forms.Label
    $authorBanner.Text = "★ 本补丁支持 Steam / PURPLE 正式版 | 免费分享严禁倒卖"
    $authorBanner.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $authorBanner.ForeColor = [System.Drawing.Color]::FromArgb(160,130,240)
    $newY = $y + 4
    $authorBanner.Location = New-Object System.Drawing.Point(16, $newY)
    $authorBanner.Size = New-Object System.Drawing.Size(515,22)
    $authorBanner.TextAlign = 'MiddleLeft'
    $body.Controls.Add($authorBanner)

    # 底部勾选确认栏
    $checkRow = New-Object System.Windows.Forms.Panel
    $checkRow.Dock = 'Bottom'
    $checkRow.Height = 56
    $checkRow.BackColor = [System.Drawing.Color]::FromArgb(20,20,26)
    $form.Controls.Add($checkRow)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = '我已充分了解修改客户端的潜在风险，并确认当前游戏已经完全关闭。'
    $chk.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $chk.ForeColor = [System.Drawing.Color]::FromArgb(200,200,205)
    $chk.Location = New-Object System.Drawing.Point(18,16)
    $chk.AutoSize = $true
    $checkRow.Controls.Add($chk)

    # 按钮栏
    $btnRow = New-Object System.Windows.Forms.Panel
    $btnRow.Dock = 'Bottom'
    $btnRow.Height = 64
    $btnRow.BackColor = [System.Drawing.Color]::FromArgb(32,32,38)
    $form.Controls.Add($btnRow)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消退出'
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(55,55,62)
    $btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.Location = New-Object System.Drawing.Point(20,15)
    $btnCancel.Size = New-Object System.Drawing.Size(100,34)
    $btnRow.Controls.Add($btnCancel)

    $btnBili = New-Object System.Windows.Forms.Button
    $btnBili.Text = '作者B站主页'
    $btnBili.BackColor = [System.Drawing.Color]::FromArgb(45,85,125)
    $btnBili.ForeColor = [System.Drawing.Color]::White
    $btnBili.FlatStyle = 'Flat'
    $btnBili.Location = New-Object System.Drawing.Point(150,15)
    $btnBili.Size = New-Object System.Drawing.Size(110,34)
    $btnBili.Add_Click({ [System.Diagnostics.Process]::Start("https://space.bilibili.com/3379443") })
    $btnRow.Controls.Add($btnBili)

    $btnGo = New-Object System.Windows.Forms.Button
    $btnGo.Text = '已了解，继续'
    $btnGo.BackColor = [System.Drawing.Color]::FromArgb(90,70,200)
    $btnGo.ForeColor = [System.Drawing.Color]::White
    $btnGo.FlatStyle = 'Flat'
    $btnGo.Location = New-Object System.Drawing.Point(410,15)
    $btnGo.Size = New-Object System.Drawing.Size(130,34)
    $btnGo.Enabled = $false
    $btnRow.Controls.Add($btnGo)

    $btnGo.Add_Click({ $form.DialogResult = 'OK'; $form.Close() })
    $btnCancel.Add_Click({ $form.DialogResult = 'Cancel'; $form.Close() })
    $chk.Add_CheckedChanged({ $btnGo.Enabled = $chk.Checked })

    $form.AcceptButton = $btnGo
    $form.CancelButton = $btnCancel
    return $form.ShowDialog()
}

# ==================== 主流程 ====================
Show-Banner


# ==================== 安全文件操作（防只读属性与文件锁） ====================
function Safe-CopyFile($src, $dst) {
    if (Test-Path $dst) {
        Set-ItemProperty -Path $dst -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }
    $tmp = "$dst.new"
    $old = "$dst.old"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Copy-Item $src $tmp -Force
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $tmpHash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    if ($srcHash -ne $tmpHash) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        throw "文件复制不完整（可能被杀毒软件拦截或磁盘错误）：$dst"
    }
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
    if (Test-Path $dst) { Move-Item $dst $old -Force }
    try {
        Move-Item $tmp $dst -Force
    } catch {
        if (Test-Path $old) { Move-Item $old $dst -Force -ErrorAction SilentlyContinue }
        throw "替换文件失败（文件可能被占用）：$dst"
    }
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
    return $srcHash
}

function Write-InstallLog($msg) {
    try {
        $log = Join-Path $ToolDir '汉化日志.txt'
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  " + $msg
        Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    } catch { }
}

function Safe-RemoveDirectory($dir) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.FullName -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($Install) {
    $res = Show-Disclaimer
    if ($res -ne 'OK') {
        Write-Host "用户已取消操作。" -ForegroundColor Yellow
        exit 0
    }

    Check-Update

    Write-Host "[1/4] 正在全盘扫描检测 AION 2 游戏版本 (Steam / PURPLE)..." -ForegroundColor Cyan
        # 自动安全解除游戏和启动器进程占用，防止文件被锁死导致无法替换
    Write-Host "[1.5/4] 正在检查冲突进程并释放文件锁..." -ForegroundColor Cyan
    $conflictList = @("Aion2", "Aion2-Win64-Shipping", "NCLauncher", "NCLauncher2", "Purple", "PurpleApp")
    foreach ($proc in $conflictList) {
        $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($p) {
            Write-Host "-> 检测到运行中的进程: $proc，正在安全解除占用..." -ForegroundColor Yellow
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
        }
    }
    $selectedRoots = @(Select-TargetGameRoots -ActionName "安装汉化")
    if ($selectedRoots.Count -eq 0) {
        Write-Host "未选择有效游戏目录，操作已终止。" -ForegroundColor Red
        exit 1
    }

    # 安装前自检：Engine.locres 必须是完整文件（约 15 MB，防止压缩包没解压完整/被杀软清空）
    $srcLocres = Join-Path $ActiveSourceDir 'Engine.locres'
    if (-not (Test-Path $srcLocres) -or (Get-Item $srcLocres).Length -lt 1000000) {
        $msg = "安装包不完整，找不到有效的 Engine.locres：`n`n$srcLocres`n`n请重新解压压缩包（不要在压缩软件里直接运行），并检查杀毒软件是否拦截。"
        Write-Host $msg -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show($msg, "安装包不完整", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }

    $processedCount = 0
    foreach ($gameRoot in $selectedRoots) {
        $processedCount++
        Write-Host ""
        Write-Host "========================================================================" -ForegroundColor DarkCyan
        Write-Host ">>> 正在处理目标游戏目录 [$processedCount/$($selectedRoots.Count)]: $gameRoot" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor DarkCyan

        $clientState = Get-ClientState $gameRoot
        Write-Host "-> 当前客户端状态: $clientState" -ForegroundColor Cyan
        if ($clientState -eq '目录无效') {
            Write-Host "-> 不是有效的 AION 2 目录，已中止安装。" -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show("不是有效的 AION 2 游戏目录：`n$gameRoot`n`n请在 Steam / PURPLE 中校验游戏文件完整性后再安装。", "客户端目录无效", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            exit 1
        }

        try {
            Write-Host "[2/3] 正在写入 $($LangName) Engine.locres..." -ForegroundColor Cyan
            foreach ($rel in $LocresRel) {
                $dst = Join-Path $gameRoot $rel
                Write-Host "-> $rel" -ForegroundColor Gray
                $null = Safe-CopyFile $srcLocres $dst
            }
            $liveLocres = Join-Path $gameRoot $LocresRel[0]
            if (-not (Test-Path $liveLocres)) { throw "汉化文件安装后不存在：$liveLocres" }
            if ((Get-Item $liveLocres).Length -ne (Get-Item $srcLocres).Length) { throw "汉化文件安装后大小不一致：$liveLocres" }
            Write-InstallLog "安装 $gameRoot : $($LangName) locres $((Get-Sha256 $liveLocres)) (大小 $((Get-Item $liveLocres).Length))"
            Write-Host "-> 该目录汉化部署完成！" -ForegroundColor Green
        } catch {
            Write-InstallLog "安装失败 $gameRoot : $($_.Exception.Message)"
            $restored = Restore-ClientFiles $gameRoot
            $logPath = Join-Path $ToolDir '汉化日志.txt'
            if ($restored) {
                Write-Host "-> 安装失败，已自动清理汉化文件（游戏回落官方英文）。" -ForegroundColor Yellow
                $tip = '已自动清理汉化文件，游戏已回落官方英文，可以直接正常进入游戏。'
            } else {
                Write-Host "-> 安装失败，请在 Steam / PURPLE 校验游戏完整性。" -ForegroundColor Red
                $tip = '请在 Steam / PURPLE 校验游戏完整性后再试。'
            }
            $msg = "汉化没有安装成功。`n`n原因：$($_.Exception.Message)`n`n$tip`n`n日志文件：`n$logPath`n`n请把这个「汉化日志.txt」发给作者。"
            [System.Windows.Forms.MessageBox]::Show($msg, '汉化失败', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            throw
        }
    }

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host ">>> 恭喜！AION 2 $($LangName)汉化全部安装成功 (共处理 $processedCount 个客户端)！" -ForegroundColor Green
    Write-Host ">>> 【核心提示】直接启动游戏即为中文，不需要改动游戏内任何语言设置！" -ForegroundColor Yellow
    Write-Host ">>> 想回到英文：运行还原，或直接删掉那两个 Engine.locres。" -ForegroundColor Yellow
    Write-Host ">>> 制作团队：吃素的佩奇汉化 | 欢迎关注获取公测最新汉化！" -ForegroundColor Magenta
    Write-Host "========================================================================" -ForegroundColor Green
    [System.Windows.Forms.MessageBox]::Show("AION 2 $($LangName)汉化安装成功 (共处理 $processedCount 个客户端)！`n`n直接启动游戏即为中文，不需要改动游戏内语言设置。`n`n想回到英文：运行「一键还原官方英文」。`n`n制作团队：吃素的佩奇汉化`n欢迎关注获取最新汉化动态！", "汉化成功 - 吃素的佩奇汉化", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}
elseif ($Restore) {
    Write-Host "[1/3] 正在全盘扫描检测 AION 2 游戏版本 (Steam / PURPLE)..." -ForegroundColor Cyan
        # 自动安全解除游戏和启动器进程占用，防止文件被锁死导致无法替换
    Write-Host "[1.5/4] 正在检查冲突进程并释放文件锁..." -ForegroundColor Cyan
    $conflictList = @("Aion2", "Aion2-Win64-Shipping", "NCLauncher", "NCLauncher2", "Purple", "PurpleApp")
    foreach ($proc in $conflictList) {
        $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($p) {
            Write-Host "-> 检测到运行中的进程: $proc，正在安全解除占用..." -ForegroundColor Yellow
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
        }
    }
    $selectedRoots = @(Select-TargetGameRoots -ActionName "还原英文")
    if ($selectedRoots.Count -eq 0) {
        Write-Host "未选择有效游戏目录，操作已终止。" -ForegroundColor Red
        exit 1
    }

    $processedCount = 0
    $restoredTotal = 0
    foreach ($gameRoot in $selectedRoots) {
        $processedCount++
        Write-Host ""
        Write-Host "========================================================================" -ForegroundColor DarkCyan
        Write-Host ">>> 正在还原目标游戏目录 [$processedCount/$($selectedRoots.Count)]: $gameRoot" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor DarkCyan

        Write-Host "[2/3] 正在删除汉化文件 Engine.locres..." -ForegroundColor Cyan
        $restored = Restore-ClientFiles $gameRoot
        if ($restored) { $restoredTotal++ }
        if ($restored) {
            Write-Host "-> 已删除汉化文件，该客户端回落为官方英文。" -ForegroundColor Green
        } else {
            Write-Host "-> 没有发现汉化文件，该客户端本来就是官方英文。" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    if ($restoredTotal -gt 0) {
        Write-Host "========================================================================" -ForegroundColor Green
        Write-Host ">>> 已还原为官方英文 (共处理 $restoredTotal 个客户端)！" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor Green
        [System.Windows.Forms.MessageBox]::Show("已还原为官方英文客户端 (共处理 $restoredTotal 个客户端)！`n`n制作团队：吃素的佩奇汉化", "还原成功", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        Write-Host "========================================================================" -ForegroundColor Yellow
        Write-Host ">>> 没有发现汉化文件，这些客户端本来就是官方英文。" -ForegroundColor Yellow
        Write-Host "========================================================================" -ForegroundColor Yellow
        [System.Windows.Forms.MessageBox]::Show("没有发现汉化文件，未做任何改动。`n`n这些客户端本来就是官方英文原版。", "无需还原", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}
