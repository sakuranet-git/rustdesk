#Requires -Version 5.1
# SAKURA-Remote 接続不変条件ゲート (Codex指摘: 接続事故防止)
# 認証/中継サーバー・公開鍵の焼き込みが「ソース」と「ビルド成果物」の両方で守られているか厳格検査する。
# check_branding.ps1(表示名残骸検出/allowlist広め) とは役割を分離する。
#
# 使い方:
#   pwsh installer/check_network_invariants.ps1 -SourceDir source [-ArtifactDir <librustdesk.dllのあるディレクトリ>]
#   (-ArtifactDir 省略時は Layer1=ソースのみ検査)
#
# 終了コード: 0=全PASS / 1=不変条件違反 / 2=対象ファイル不在

[CmdletBinding()]
param(
    [string]$SourceDir = "source",
    [string]$ArtifactDir = ""
)

$ErrorActionPreference = 'Stop'

# ===== 不変条件 (絶対に守る値 / 絶対に出てはいけない公式値) =====
$GOOD_SERVER = '116.58.164.244'
$GOOD_KEY    = 'CiBjNf1UarFy7pU5OhHoAVQUG0wvvOLriqycc4PMPd8='
$APP_NAME    = 'SAKURA-Remote'
$ORG         = 'jp.sakuranet'
$BAD_SERVER  = 'rs-ny.rustdesk.com'                                # RustDesk公式 rendezvous
$BAD_KEY     = 'OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw='      # RustDesk公式 公開鍵

$violations = New-Object System.Collections.Generic.List[string]
$checks = 0

# バイナリを文字コード非依存(Latin1=1バイト1文字)で読む。ASCIIだと>127が壊れ検索を誤る(Codex指摘)。
function Read-AsLatin1([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::GetEncoding(28591))
}

# ---------- Layer 1: ソース config.rs ----------
$configRel = "libs/hbb_common/src/config.rs"
$configPath = Join-Path $SourceDir $configRel
Write-Host "■ Layer1: ソース $configRel" -ForegroundColor Cyan
if (-not (Test-Path $configPath)) {
    Write-Host "  ERROR: 見つかりません: $configPath" -ForegroundColor Red
    exit 2
}
$cfg = Get-Content $configPath -Raw
$checks++
if ($cfg -notmatch [regex]::Escape($GOOD_SERVER)) { $violations.Add("config.rs に 自社サーバー $GOOD_SERVER がない") }
if ($cfg -notmatch [regex]::Escape($GOOD_KEY))    { $violations.Add("config.rs に 自社鍵 がない") }
if ($cfg -match    [regex]::Escape($BAD_SERVER))  { $violations.Add("config.rs に 公式サーバー $BAD_SERVER が残存") }
if ($cfg -match    [regex]::Escape($BAD_KEY))     { $violations.Add("config.rs に 公式鍵 が残存") }
if ($violations.Count -eq 0) { Write-Host "  OK: config.rs 不変条件 満たす" -ForegroundColor Green }

# ---------- Layer 2: updater guard (公式更新経路が is_custom_client で封鎖されているか) ----------
Write-Host "■ Layer2: updater guard (is_custom_client)" -ForegroundColor Cyan
$guardFns = @(
    @{ file = "src/updater.rs"; fn = "fn start_auto_update" },
    @{ file = "src/updater.rs"; fn = "fn check_update" },
    @{ file = "src/updater.rs"; fn = "fn stop_auto_update" },
    @{ file = "src/updater.rs"; fn = "fn manually_check_update" },
    @{ file = "src/common.rs";  fn = "fn check_software_update" },
    @{ file = "src/common.rs";  fn = "fn do_check_software_update" }
)
$guardPat = "is_custom_client"
$guardOk = 0
foreach ($g in $guardFns) {
    $fp = Join-Path $SourceDir $g.file
    if (-not (Test-Path $fp)) {
        $violations.Add("$($g.file) が無い($($g.fn) を検査できない・上流でファイル改名/削除の疑い)")
        continue
    }
    $lines = Get-Content $fp
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match [regex]::Escape($g.fn)) {
            $found = $true
            # 探索範囲を広げる(空行/コメント増加での誤判定防止・Codex指摘: 40行)
            $window = ($lines[$i..([Math]::Min($i + 40, $lines.Count - 1))]) -join "`n"
            if ($window -notmatch $guardPat) {
                $violations.Add("$($g.file): $($g.fn) に $guardPat guard が無い(公式updater経路が開いている可能性)")
            } else { $guardOk++ }
            break
        }
    }
    # 各関数ごとに未検出=fail(Codex指摘: 上流の改名/削除で1つでも欠けたら危険)
    if (-not $found) {
        $violations.Add("$($g.file): $($g.fn) が見つからない(上流改名/削除の疑い・要人間確認)")
    }
}
$checks++
if (($violations | Where-Object { $_ -match 'guard|見つからない|検査できない' }).Count -eq 0) {
    Write-Host "  OK: 全 $($guardFns.Count) 関数に guard あり" -ForegroundColor Green
}

# ---------- Layer 3: ビルド成果物 librustdesk.dll ----------
if ($ArtifactDir -ne "") {
    $dll = Join-Path $ArtifactDir "librustdesk.dll"
    Write-Host "■ Layer3: 成果物 librustdesk.dll" -ForegroundColor Cyan
    if (-not (Test-Path $dll)) {
        Write-Host "  ERROR: 見つかりません: $dll" -ForegroundColor Red
        exit 2
    }
    $bin = Read-AsLatin1 $dll
    $checks++
    if ($bin -notmatch [regex]::Escape($GOOD_SERVER)) { $violations.Add("librustdesk.dll に 自社サーバー $GOOD_SERVER が焼き込まれていない") }
    if ($bin -notmatch [regex]::Escape($GOOD_KEY))    { $violations.Add("librustdesk.dll に 自社鍵 が焼き込まれていない") }
    if ($bin -match    [regex]::Escape($BAD_SERVER))  { $violations.Add("librustdesk.dll に 公式サーバー $BAD_SERVER が残存") }
    if ($bin -match    [regex]::Escape($BAD_KEY))     { $violations.Add("librustdesk.dll に 公式鍵 が残存") }
    if ($violations.Count -eq 0) { Write-Host "  OK: librustdesk.dll 焼き込み 満たす" -ForegroundColor Green }
}

# ---------- Layer 4: APP_NAME / ORG ブランディング (警告のみ・誤配信ブロックを避ける) ----------
# APP_NAMEは版数リソース等でUTF-16に入るためLatin1/UTF-16両方を探す。
# 剥がれてもサーバー/鍵喪失ほど致命でないので、ここは fatal にせず警告に留める。
if ($ArtifactDir -ne "") {
    Write-Host "■ Layer4: APP_NAME / ORG ブランディング (警告のみ)" -ForegroundColor Cyan
    # 成果物の全対象を Latin1/UTF-16 で結合して APP_NAME/ORG を探す
    $blob = ""
    foreach ($name in @("SAKURA-Remote.exe", "rustdesk.exe", "librustdesk.dll")) {
        $t = Join-Path $ArtifactDir $name
        if (-not (Test-Path $t)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($t)
        $blob += [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
        $blob += [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    foreach ($brand in @($APP_NAME, $ORG)) {
        if ($blob -match [regex]::Escape($brand)) { Write-Host "  OK: '$brand' 検出" -ForegroundColor Green }
        else { Write-Host "  警告: '$brand' を成果物内で検出できず(要目視・check_branding.ps1で別途確認)" -ForegroundColor Yellow }
    }
} else {
    Write-Host "■ Layer3/4: -ArtifactDir 未指定のためスキップ (ソースのみ検査)" -ForegroundColor DarkGray
}

# ---------- 結果 ----------
Write-Host ""
if ($violations.Count -gt 0) {
    Write-Host "X 接続不変条件 違反 $($violations.Count) 件:" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "   - $v" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  → 上流マージ等で 認証/中継サーバー・鍵 が失われた可能性。配信してはいけない。" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ 接続不変条件 全PASS (検査層: $checks)" -ForegroundColor Green
exit 0
