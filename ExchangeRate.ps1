#Requires -Version 5.1
# ExchangeRate.ps1 - 台灣銀行外匯查詢工具

# =============================================================================
# 1. Assembly Loading + Proxy Configuration
# =============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing

# Configure .NET to use system proxy with default credentials (fixes 407 Proxy Auth)
[System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# =============================================================================
# 2. Module Import + Cache Initialization
# =============================================================================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir "Modules\RateParser.psm1") -Force
Import-Module (Join-Path $scriptDir "Modules\DataFetcher.psm1") -Force
Import-Module (Join-Path $scriptDir "Modules\ChartBuilder.psm1") -Force
Import-Module (Join-Path $scriptDir "Modules\RateAnalyzer.psm1") -Force
Import-Module (Join-Path $scriptDir "Modules\AIAnalyzer.psm1") -Force
Import-Module (Join-Path $scriptDir "Modules\OllamaHelper.psm1") -Force

$cachePath = Join-Path $scriptDir "Cache"
Initialize-Cache -CacheRootPath $cachePath

# =============================================================================
# 3. Currency Data
# =============================================================================
$Currencies = @(
    @{ Code = 'USD'; Name = '美金' }
    @{ Code = 'JPY'; Name = '日圓' }
    @{ Code = 'EUR'; Name = '歐元' }
    @{ Code = 'GBP'; Name = '英鎊' }
    @{ Code = 'CNY'; Name = '人民幣' }
    @{ Code = 'HKD'; Name = '港幣' }
    @{ Code = 'SGD'; Name = '新加坡幣' }
    @{ Code = 'AUD'; Name = '澳幣' }
    @{ Code = 'CAD'; Name = '加幣' }
    @{ Code = 'CHF'; Name = '瑞士法郎' }
    @{ Code = 'NZD'; Name = '紐西蘭幣' }
    @{ Code = 'THB'; Name = '泰銖' }
    @{ Code = 'PHP'; Name = '披索' }
    @{ Code = 'IDR'; Name = '印尼盾' }
    @{ Code = 'KRW'; Name = '韓元' }
    @{ Code = 'VND'; Name = '越南盾' }
    @{ Code = 'MYR'; Name = '馬來西亞林吉特' }
    @{ Code = 'ZAR'; Name = '南非幣' }
    @{ Code = 'SEK'; Name = '瑞典克朗' }
)

# =============================================================================
# 4. Application State Variables
# =============================================================================
$script:CurrentRates = @()
$script:SelectedCurrency = 'USD'
$script:SelectedPeriod = '本日'
$script:FetchJob = $null
$script:IsFetching = $false
$script:Chart = $null
$script:FetchTimer = $null
$script:FetchQueue = @()
$script:FetchIndex = 0
$script:FetchCurrency = ''
$script:FetchTotal = 0
$script:FetchResults = @()
$script:FetchFirstTick = $true
$script:FetchPeriod = ''
$script:AutoRefreshTimer = $null
$script:SettingsPath = Join-Path $scriptDir 'settings.json'
$script:AiDebounceTimer = $null
$script:AiPS = $null
$script:AiAsync = $null
$script:LastChartData = @()
$script:PullResult = $null
$script:AiPollStart = $null
$script:ConverterRateType = 'Spot'   # 'Spot' or 'Cash'
$script:ConverterDirection = 'TWD'   # 'TWD' = user is typing TWD, 'Foreign' = user is typing foreign
$script:ConverterUpdating = $false   # Re-entrance guard for Update-Converter
$script:IsClosing = $false           # Set true on FormClosing to prevent post-close UI access

# =============================================================================
# 5. Core Functions
# =============================================================================

# --- Settings Persistence ---
function Get-AppSettings {
    $defaults = @{ LastSelectedCurrency = 'USD' }
    try {
        if (Test-Path -Path $script:SettingsPath) {
            $json = Get-Content -Path $script:SettingsPath -Raw -Encoding UTF8
            $saved = $json | ConvertFrom-Json
            # Merge: use saved values, fill missing keys with defaults
            $result = [PSCustomObject]$defaults
            if ($null -ne $saved.LastSelectedCurrency) {
                $result.LastSelectedCurrency = $saved.LastSelectedCurrency
            }
            return $result
        }
    } catch {
        # Corrupt or unreadable — return default
    }
    return [PSCustomObject]$defaults
}

function Set-AppSettings {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Settings
    )
    try {
        $json = $Settings | ConvertTo-Json -Depth 5
        Set-Content -Path $script:SettingsPath -Value $json -Encoding UTF8 -NoNewline
    } catch {
        # Silently fail — non-critical
    }
}

function Update-RateDisplay {
    if ($script:IsClosing) { return }
    $cur = $script:SelectedCurrency
    $rate = $script:CurrentRates | Where-Object { $_.Currency -eq $cur } | Select-Object -First 1
    $chineseName = Get-CurrencyName -Code $cur
    $lblCurrencyTitle.Text = "$cur $chineseName"

    if ($null -ne $rate) {
        if ($rate.CashBuy -eq 0) {
            $lblCashBuy.Text = "現金買入: N/A"
        } else {
            $lblCashBuy.Text = "現金買入: $($rate.CashBuy)"
        }
        if ($rate.CashSell -eq 0) {
            $lblCashSell.Text = "現金賣出: N/A"
        } else {
            $lblCashSell.Text = "現金賣出: $($rate.CashSell)"
        }
        if ($rate.SpotBuy -eq 0) {
            $lblSpotBuy.Text = "即期買入: N/A"
        } else {
            $lblSpotBuy.Text = "即期買入: $($rate.SpotBuy)"
        }
        if ($rate.SpotSell -eq 0) {
            $lblSpotSell.Text = "即期賣出: N/A"
        } else {
            $lblSpotSell.Text = "即期賣出: $($rate.SpotSell)"
        }
        $lblUpdateTime.Text = "更新時間: $(Get-Date -Format 'yyyy/MM/dd HH:mm')"
    } else {
        $lblCashBuy.Text = "現金買入: --"
        $lblCashSell.Text = "現金賣出: --"
        $lblSpotBuy.Text = "即期買入: --"
        $lblSpotSell.Text = "即期賣出: --"
        $lblUpdateTime.Text = "更新時間: --"
    }

    # Update converter labels and recalculate
    Update-ConverterInfo
}

function Format-ConverterAmount {
    <#
    .SYNOPSIS
        Formats a decimal amount for display in the converter text box.
    #>
    param(
        [Parameter(Mandatory)]
        [decimal]$Value
    )

    # For very small values (e.g. VND, IDR), show more decimal places
    if ([Math]::Abs($Value) -gt 0 -and [Math]::Abs($Value) -lt 0.01) {
        return $Value.ToString('G6')
    } elseif ([Math]::Abs($Value) -gt 0 -and [Math]::Abs($Value) -lt 1) {
        return $Value.ToString('F4')
    } elseif ([Math]::Abs($Value) -ge 10000) {
        return $Value.ToString('N2')
    } else {
        return $Value.ToString('F2')
    }
}

function Update-Converter {
    <#
    .SYNOPSIS
        Recalculates and updates the converter output box based on the active input.
    .DESCRIPTION
        Reads the active input (TWD or Foreign), performs the conversion using
        the current rate (Spot or Cash), and updates the other text box.
        Uses a flag to prevent recursive TextChanged events.
    #>

    # Bail out if form is closing or already updating
    if ($script:IsClosing) { return }

    # Prevent re-entrant calls (TextChanged fires when we update the other box)
    if ($script:ConverterUpdating) { return }
    $script:ConverterUpdating = $true

    try {
        $cur = $script:SelectedCurrency
        $rate = $script:CurrentRates | Where-Object { $_.Currency -eq $cur } | Select-Object -First 1

        if ($null -eq $rate) {
            $txtTwdAmount.Text = ''
            $txtForeignAmount.Text = ''
            $lblConverterInfo.Text = '尚無匯率資料'
            return
        }

        # Determine which rate to use based on user selection
        if ($script:ConverterRateType -eq 'Cash') {
            $sellRate = $rate.CashSell   # Bank sells foreign to you (TWD → Foreign)
            $buyRate  = $rate.CashBuy    # Bank buys foreign from you (Foreign → TWD)
        } else {
            $sellRate = $rate.SpotSell
            $buyRate  = $rate.SpotBuy
        }

        # N/A check
        if ($sellRate -eq 0 -or $buyRate -eq 0) {
            $txtTwdAmount.Text = ''
            $txtForeignAmount.Text = ''
            $lblConverterInfo.Text = '此幣別無此類匯率資料'
            return
        }

        if ($script:ConverterDirection -eq 'TWD') {
            # User is typing TWD amount → calculate Foreign amount
            $twdText = $txtTwdAmount.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($twdText)) {
                $txtForeignAmount.Text = ''
                $lblConverterInfo.Text = "1 TWD = $(Format-ConverterAmount -Value ([decimal]1 / $sellRate)) $cur"
                return
            }

            $twdVal = 0
            if (-not [decimal]::TryParse($twdText, [ref]$twdVal)) {
                $txtForeignAmount.Text = ''
                return
            }

            $foreignVal = $twdVal / $sellRate
            $txtForeignAmount.Text = Format-ConverterAmount -Value $foreignVal
        }
        else {
            # User is typing Foreign amount → calculate TWD amount
            $foreignText = $txtForeignAmount.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($foreignText)) {
                $txtTwdAmount.Text = ''
                $lblConverterInfo.Text = "1 $cur = $(Format-ConverterAmount -Value $buyRate) TWD"
                return
            }

            $foreignVal = 0
            if (-not [decimal]::TryParse($foreignText, [ref]$foreignVal)) {
                $txtTwdAmount.Text = ''
                return
            }

            $twdVal = $foreignVal * $buyRate
            $txtTwdAmount.Text = Format-ConverterAmount -Value $twdVal
        }

        # Update info label with reference rate
        $chineseName = Get-CurrencyName -Code $cur
        $rateLabel = if ($script:ConverterRateType -eq 'Cash') { '現金' } else { '即期' }
        $lblConverterInfo.Text = "${rateLabel}賣出: $sellRate | ${rateLabel}買入: $buyRate | 1 TWD ≈ $(Format-ConverterAmount -Value ([decimal]1 / $sellRate)) $cur"
    }
    finally {
        $script:ConverterUpdating = $false
    }
}

function Update-ConverterInfo {
    <#
    .SYNOPSIS
        Updates the converter currency labels when the selected currency changes.
    .DESCRIPTION
        Called from Update-RateDisplay to keep converter labels in sync.
        Does NOT clear input values — preserves user-typed amounts.
    #>

    $cur = $script:SelectedCurrency
    $chineseName = Get-CurrencyName -Code $cur
    $lblForeignCurrency.Text = "$cur $chineseName"

    # Recalculate with current inputs
    Update-Converter
}

function Stop-FetchJob {
    if ($null -ne $script:FetchTimer) {
        $script:FetchTimer.Stop()
        $script:FetchTimer.Dispose()
        $script:FetchTimer = $null
    }
    if ($null -ne $script:SpinnerTimer) {
        $script:SpinnerTimer.Stop()
        $script:SpinnerTimer.Dispose()
        $script:SpinnerTimer = $null
    }
    $script:IsFetching = $false
    $script:FetchQueue = @()
    $script:FetchIndex = 0
    $script:FetchResults = @()
}

function Start-AiAnalysis {
    <#
    .SYNOPSIS
        Triggers local recommendation engine with a 1.5s debounce timer.
    .DESCRIPTION
        When currency or period changes, this function starts a debounce timer.
        After 1.5s of inactivity, it runs the local RateRecommendation engine
        (MACD + Bollinger + RSI + SMA scoring) which requires NO API key.
        OpenAI enhancement is available via a separate button if user has configured a key.
    #>

    # Cancel existing debounce timer
    if ($null -ne $script:AiDebounceTimer) {
        $script:AiDebounceTimer.Stop()
        $script:AiDebounceTimer.Dispose()
        $script:AiDebounceTimer = $null
    }

    $txtAiAnalysis.Text = "🔄 正在分析 $($script:SelectedCurrency) 匯率趨勢..."

    $script:AiDebounceTimer = New-Object System.Windows.Forms.Timer
    $script:AiDebounceTimer.Interval = 1500

    $script:AiDebounceTimer.Add_Tick({
        if ($script:IsClosing) {
            $script:AiDebounceTimer.Stop()
            $script:AiDebounceTimer.Dispose()
            $script:AiDebounceTimer = $null
            return
        }
        $script:AiDebounceTimer.Stop()
        $script:AiDebounceTimer.Dispose()
        $script:AiDebounceTimer = $null

        # If chart data is still being fetched, wait and retry
        if ($script:IsFetching) {
            $txtAiAnalysis.Text = "⏳ 等待資料讀取完成後分析..."
            $script:AiWaitTimer = New-Object System.Windows.Forms.Timer
            $script:AiWaitTimer.Interval = 1000
            $script:AiWaitTimer.Add_Tick({
                if ($script:IsClosing -or -not $script:IsFetching) {
                    $script:AiWaitTimer.Stop()
                    $script:AiWaitTimer.Dispose()
                    $script:AiWaitTimer = $null
                    if (-not $script:IsClosing) {
                        # Re-trigger analysis now that data is ready
                        Start-AiAnalysis
                    }
                    return
                }
            })
            $script:AiWaitTimer.Start()
            return
        }

        $cur = $script:SelectedCurrency
        $period = $script:SelectedPeriod

        try {
            # 1. Gather data
            $dataForAnalysis = $null
            if ($period -eq '本日') {
                $date = (Get-Date).ToString('yyyy-MM-dd')
                $url = "https://rate.bot.com.tw/xrt/quote/$date/$cur/spot"
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
                $intradayRates = ConvertFrom-BotHtml -RawHtml $response.Content

                if ($null -eq $intradayRates -or $intradayRates.Count -eq 0) {
                    $txtAiAnalysis.Text = "📊 本日無即期匯率資料，無法進行分析。"
                    return
                }
                $dataForAnalysis = $intradayRates
            } else {
                # Reuse already-loaded chart data when available to avoid redundant network fetch
                if ($null -ne $script:LastChartData -and $script:LastChartData.Count -ge 5) {
                    $dataPoints = $script:LastChartData
                } else {
                    $range = Get-PeriodDateRange -Period $period
                    $missingDates = [ref]@()
                    $dataPoints = @(Get-HistoricalRange -CurrencyCode $cur -StartDate $range.StartDate -EndDate $range.EndDate -MissingDates $missingDates)
                }

                if ($null -eq $dataPoints -or $dataPoints.Count -lt 5) {
                    $txtAiAnalysis.Text = "📊 歷史資料不足（$($dataPoints.Count) 筆），至少需要 5 筆資料才能進行分析。`n請稍候資料讀取完成後再試。"
                    return
                }
                $dataForAnalysis = $dataPoints
            }

            # 2. Run local recommendation engine (no API key needed)
            $recommendation = Get-RateRecommendation -DataPoints $dataForAnalysis -Currency $cur -Period $period

            if ($null -ne $recommendation -and $null -ne $recommendation.DetailedReport) {
                $txtAiAnalysis.Text = $recommendation.DetailedReport
            } else {
                $txtAiAnalysis.Text = "📊 本地分析完成，但資料不足以產生完整建議。"
            }

        } catch {
            $txtAiAnalysis.Text = "⚠ 分析失敗: $($_.Exception.Message)"
        }
    })

    $script:AiDebounceTimer.Start()
}

function Show-AiProviderDialog {
    <#
    .SYNOPSIS
        Shows a dialog to select an AI model and enter API key.
    .DESCRIPTION
        Displays a WinForms dialog with a model dropdown (OpenAI,
        Gemini, Llama 3.3, Ollama, Custom) and an API Key input field.
        Each preset auto-fills the Base URL and Model name; user only needs
        to enter the API Key (Ollama needs no key).
        Returns a hashtable with: Provider, DisplayName, ApiKey, Model, BaseUrl, BypassProxy
        Returns $null if user cancels.
    #>

    # --- Provider presets ---
    $presets = [ordered]@{
        'OpenAI (GPT-4o-mini)'     = @{ BaseUrl = 'https://api.openai.com/v1';                     Model = 'gpt-4o-mini';               NeedsKey = $true;  BypassProxy = $false }
        'OpenAI (GPT-4o)'          = @{ BaseUrl = 'https://api.openai.com/v1';                     Model = 'gpt-4o';                    NeedsKey = $true;  BypassProxy = $false }
        'Google Gemini (2.0 Flash)' = @{ BaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai'; Model = 'gemini-2.0-flash'; NeedsKey = $true;  BypassProxy = $false }
        'Google Gemini (2.5 Pro)'  = @{ BaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai'; Model = 'gemini-2.5-pro';  NeedsKey = $true;  BypassProxy = $false }
        'Meta Llama 3.3 (Together)' = @{ BaseUrl = 'https://api.together.xyz/v1';                   Model = 'meta-llama/Llama-3.3-70B-Instruct-Turbo'; NeedsKey = $true; BypassProxy = $false }
        'Ollama (本地)'             = @{ BaseUrl = 'http://localhost:11434/v1';                     Model = 'llama3.2:3b';               NeedsKey = $false; BypassProxy = $true  }
        '自訂端點...'               = @{ BaseUrl = ''; Model = ''; NeedsKey = $true;  BypassProxy = $false }
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = '選擇 AI 模型'
    $dlg.Size = New-Object System.Drawing.Size(480, 320)
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

    # --- Label: Model ---
    $lblModel = New-Object System.Windows.Forms.Label
    $lblModel.Text = 'AI 模型:'
    $lblModel.Location = New-Object System.Drawing.Point(20, 18)
    $lblModel.Size = New-Object System.Drawing.Size(80, 22)
    $dlg.Controls.Add($lblModel)

    # --- ComboBox: Model selection ---
    $cmbModel = New-Object System.Windows.Forms.ComboBox
    $cmbModel.Location = New-Object System.Drawing.Point(105, 15)
    $cmbModel.Size = New-Object System.Drawing.Size(340, 24)
    $cmbModel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    foreach ($key in $presets.Keys) { [void]$cmbModel.Items.Add($key) }
    $cmbModel.SelectedIndex = 0
    $dlg.Controls.Add($cmbModel)

    # --- Panel: fields that change per provider ---
    $fieldPanel = New-Object System.Windows.Forms.Panel
    $fieldPanel.Location = New-Object System.Drawing.Point(20, 55)
    $fieldPanel.Size = New-Object System.Drawing.Size(430, 180)
    $dlg.Controls.Add($fieldPanel)

    # Label: Base URL
    $lblUrl = New-Object System.Windows.Forms.Label
    $lblUrl.Text = 'Base URL:'
    $lblUrl.Location = New-Object System.Drawing.Point(0, 8)
    $lblUrl.Size = New-Object System.Drawing.Size(80, 22)
    $fieldPanel.Controls.Add($lblUrl)

    $txtUrl = New-Object System.Windows.Forms.TextBox
    $txtUrl.Location = New-Object System.Drawing.Point(85, 6)
    $txtUrl.Size = New-Object System.Drawing.Size(310, 24)
    $fieldPanel.Controls.Add($txtUrl)

    # Label: Model Name
    $lblModelName = New-Object System.Windows.Forms.Label
    $lblModelName.Text = 'Model:'
    $lblModelName.Location = New-Object System.Drawing.Point(0, 42)
    $lblModelName.Size = New-Object System.Drawing.Size(80, 22)
    $fieldPanel.Controls.Add($lblModelName)

    $txtModelName = New-Object System.Windows.Forms.TextBox
    $txtModelName.Location = New-Object System.Drawing.Point(85, 40)
    $txtModelName.Size = New-Object System.Drawing.Size(310, 24)
    $fieldPanel.Controls.Add($txtModelName)

    # Label: API Key
    $lblKey = New-Object System.Windows.Forms.Label
    $lblKey.Text = 'API Key:'
    $lblKey.Location = New-Object System.Drawing.Point(0, 76)
    $lblKey.Size = New-Object System.Drawing.Size(80, 22)
    $fieldPanel.Controls.Add($lblKey)

    $txtKey = New-Object System.Windows.Forms.TextBox
    $txtKey.Location = New-Object System.Drawing.Point(85, 74)
    $txtKey.Size = New-Object System.Drawing.Size(310, 24)
    $txtKey.UseSystemPasswordChar = $true
    $fieldPanel.Controls.Add($txtKey)

    # Checkbox: show API key
    $chkShowKey = New-Object System.Windows.Forms.CheckBox
    $chkShowKey.Text = '顯示'
    $chkShowKey.Location = New-Object System.Drawing.Point(400, 76)
    $chkShowKey.Size = New-Object System.Drawing.Size(50, 22)
    $chkShowKey.Add_CheckedChanged({
        $txtKey.UseSystemPasswordChar = -not $chkShowKey.Checked
    })
    $fieldPanel.Controls.Add($chkShowKey)

    # Checkbox: bypass proxy
    $chkBypassProxy = New-Object System.Windows.Forms.CheckBox
    $chkBypassProxy.Text = '略過系統 Proxy'
    $chkBypassProxy.Location = New-Object System.Drawing.Point(85, 110)
    $chkBypassProxy.Size = New-Object System.Drawing.Size(200, 22)
    $fieldPanel.Controls.Add($chkBypassProxy)

    # Hint label
    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = ''
    $lblHint.Location = New-Object System.Drawing.Point(0, 140)
    $lblHint.Size = New-Object System.Drawing.Size(430, 22)
    $lblHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $fieldPanel.Controls.Add($lblHint)

    # --- Buttons ---
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = '確定'
    $btnOk.Location = New-Object System.Drawing.Point(210, 250)
    $btnOk.Size = New-Object System.Drawing.Size(85, 30)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消'
    $btnCancel.Location = New-Object System.Drawing.Point(305, 250)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 30)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dlg.Controls.Add($btnOk)
    $dlg.Controls.Add($btnCancel)
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    # --- Helper: update fields when selection changes ---
    $updateFields = {
        $sel = $cmbModel.SelectedItem
        if ($null -eq $sel -or -not $presets.Contains($sel)) { return }

        $p = $presets[$sel]
        $txtUrl.Text = $p.BaseUrl
        $txtModelName.Text = $p.Model
        $chkBypassProxy.Checked = $p.BypassProxy

        if ($p.NeedsKey) {
            $lblKey.Enabled = $true
            $txtKey.Enabled = $true
            $chkShowKey.Enabled = $true
            $lblHint.Text = '請輸入您的 API Key'
        } else {
            $txtKey.Text = ''
            $lblKey.Enabled = $false
            $txtKey.Enabled = $false
            $chkShowKey.Enabled = $false
            $lblHint.Text = '此模型無需 API Key'
        }
    }

    $cmbModel.Add_SelectedIndexChanged($updateFields)

    # Trigger initial state
    & $updateFields

    # --- Show dialog ---
    $result = $dlg.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $dlg.Dispose()
        return $null
    }

    $selected = $cmbModel.SelectedItem
    $preset = $presets[$selected]

    # Validate: custom endpoint needs URL
    if ([string]::IsNullOrWhiteSpace($txtUrl.Text.Trim())) {
        [System.Windows.Forms.MessageBox]::Show(
            '請輸入 API Base URL。',
            '缺少必要欄位',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        $dlg.Dispose()
        return $null
    }

    # Validate: needs key but empty
    if ($preset.NeedsKey -and [string]::IsNullOrWhiteSpace($txtKey.Text.Trim())) {
        [System.Windows.Forms.MessageBox]::Show(
            '此模型需要 API Key，請輸入。',
            '缺少必要欄位',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        $dlg.Dispose()
        return $null
    }

    # --- Ollama-specific integration: auto-detect, start, model selection ---
    if ($selected -match 'Ollama') {
        $ollamaStatus = Test-OllamaAvailable

        # Case 1: Ollama not on PATH — show install guide
        if (-not $ollamaStatus.IsOnPath) {
            $dlg.Dispose()

            $installDlg = New-Object System.Windows.Forms.Form
            $installDlg.Text = 'Ollama 安裝指引'
            $installDlg.Size = New-Object System.Drawing.Size(460, 280)
            $installDlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
            $installDlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $installDlg.MaximizeBox = $false
            $installDlg.MinimizeBox = $false
            $installDlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

            $installLbl = New-Object System.Windows.Forms.Label
            $installLbl.Text = "偵測到系統尚未安裝 Ollama。`n`n請依下列步驟安裝：`n  1. 前往 https://ollama.com/download`n  2. 下載 Windows 版本並安裝`n  3. 安裝完成後重新啟動本程式`n`n下載連結：`nhttps://ollama.com/download"
            $installLbl.Location = New-Object System.Drawing.Point(20, 15)
            $installLbl.Size = New-Object System.Drawing.Size(400, 160)
            $installDlg.Controls.Add($installLbl)

            $btnCopy = New-Object System.Windows.Forms.Button
            $btnCopy.Text = '複製下載連結'
            $btnCopy.Location = New-Object System.Drawing.Point(80, 190)
            $btnCopy.Size = New-Object System.Drawing.Size(130, 32)
            $btnCopy.Add_Click({
                [System.Windows.Forms.Clipboard]::SetText('https://ollama.com/download')
                [System.Windows.Forms.MessageBox]::Show(
                    '已複製下載連結到剪貼簿！',
                    '複製成功',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            })
            $installDlg.Controls.Add($btnCopy)

            $btnClose = New-Object System.Windows.Forms.Button
            $btnClose.Text = '關閉'
            $btnClose.Location = New-Object System.Drawing.Point(230, 190)
            $btnClose.Size = New-Object System.Drawing.Size(100, 32)
            $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $installDlg.Controls.Add($btnClose)
            $installDlg.CancelButton = $btnClose

            [void]$installDlg.ShowDialog()
            $installDlg.Dispose()
            return $null
        }

        # Case 2: Ollama on PATH but not running — try to start
        if (-not $ollamaStatus.IsRunning) {
            [System.Windows.Forms.MessageBox]::Show(
                'Ollama 服務尚未啟動，將嘗試在背景啟動…',
                '啟動 Ollama',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            $started = Start-OllamaService -WaitSeconds 3

            if (-not $started) {
                [System.Windows.Forms.MessageBox]::Show(
                    '無法啟動 Ollama 服務。請手動在終端機執行「ollama serve」後再試。',
                    '啟動失敗',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                $dlg.Dispose()
                return $null
            }
        }

        # Case 3: Ollama is running — check for installed models
        $installedModels = Get-OllamaModels

        if ($installedModels.Count -eq 0) {
            # No models installed — offer to pull one
            $dlg.Dispose()

            $pullDlg = New-Object System.Windows.Forms.Form
            $pullDlg.Text = '下載 Ollama 模型'
            $pullDlg.Size = New-Object System.Drawing.Size(440, 220)
            $pullDlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
            $pullDlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $pullDlg.MaximizeBox = $false
            $pullDlg.MinimizeBox = $false
            $pullDlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

            $pullLbl = New-Object System.Windows.Forms.Label
            $pullLbl.Text = '本機尚未安裝任何 Ollama 模型。`n請輸入要下載的模型名稱（預設 llama3.2:3b，約 2GB）：'
            $pullLbl.Location = New-Object System.Drawing.Point(20, 15)
            $pullLbl.Size = New-Object System.Drawing.Size(390, 55)
            $pullDlg.Controls.Add($pullLbl)

            $txtPullModel = New-Object System.Windows.Forms.TextBox
            $txtPullModel.Text = 'llama3.2:3b'
            $txtPullModel.Location = New-Object System.Drawing.Point(20, 75)
            $txtPullModel.Size = New-Object System.Drawing.Size(380, 24)
            $pullDlg.Controls.Add($txtPullModel)

            $btnPull = New-Object System.Windows.Forms.Button
            $btnPull.Text = '下載模型'
            $btnPull.Location = New-Object System.Drawing.Point(60, 120)
            $btnPull.Size = New-Object System.Drawing.Size(130, 32)
            $btnPull.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $pullDlg.Controls.Add($btnPull)
            $pullDlg.AcceptButton = $btnPull

            $btnSkip = New-Object System.Windows.Forms.Button
            $btnSkip.Text = '取消'
            $btnSkip.Location = New-Object System.Drawing.Point(220, 120)
            $btnSkip.Size = New-Object System.Drawing.Size(100, 32)
            $btnSkip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $pullDlg.Controls.Add($btnSkip)
            $pullDlg.CancelButton = $btnSkip

            $pullResult = $pullDlg.ShowDialog()

            if ($pullResult -ne [System.Windows.Forms.DialogResult]::OK) {
                $pullDlg.Dispose()
                return $null
            }

            $modelToPull = $txtPullModel.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($modelToPull)) {
                $pullDlg.Dispose()
                return $null
            }

            $pullDlg.Dispose()

            # Show progress dialog while pulling model (background via timer)
            $progressDlg = New-Object System.Windows.Forms.Form
            $progressDlg.Text = '下載模型中'
            $progressDlg.Size = New-Object System.Drawing.Size(420, 150)
            $progressDlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
            $progressDlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $progressDlg.MaximizeBox = $false
            $progressDlg.MinimizeBox = $false
            $progressDlg.ControlBox = $false
            $progressDlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

            $progressLbl = New-Object System.Windows.Forms.Label
            $progressLbl.Text = "正在下載模型 '$modelToPull'，請稍候…`n這可能需要幾分鐘，取決於模型大小與網速。"
            $progressLbl.Location = New-Object System.Drawing.Point(20, 15)
            $progressLbl.Size = New-Object System.Drawing.Size(370, 55)
            $progressDlg.Controls.Add($progressLbl)

            $progressBar = New-Object System.Windows.Forms.ProgressBar
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
            $progressBar.Location = New-Object System.Drawing.Point(20, 75)
            $progressBar.Size = New-Object System.Drawing.Size(370, 23)
            $progressBar.MarqueeAnimationSpeed = 30
            $progressDlg.Controls.Add($progressBar)

            # Run pull in a background PowerShell instance
            $pullPS = [System.Management.Automation.PowerShell]::Create()
            $pullPS.Runspace.SessionStateProxy.SetVariable('modelName', $modelToPull)
            $modulePath = Join-Path $scriptDir 'Modules'
            [void]$pullPS.AddScript(@"
                Import-Module (Join-Path '$modulePath' 'OllamaHelper.psm1') -Force
                Invoke-OllamaPull -ModelName `$modelName
"@)

            $pullAsync = $pullPS.BeginInvoke()

            # Timer to poll for completion
            $pullTimer = New-Object System.Windows.Forms.Timer
            $pullTimer.Interval = 500

            $script:PullResult = $null

            $pullTimer.Add_Tick({
                if ($pullAsync.IsCompleted) {
                    $pullTimer.Stop()
                    $pullTimer.Dispose()

                    try {
                        $pullOutput = $pullPS.EndInvoke($pullAsync)
                        $script:PullResult = $pullOutput[0]
                    }
                    catch {
                        $script:PullResult = [PSCustomObject]@{
                            Success = $false
                            Message = "下載程序異常: $($_.Exception.Message)"
                        }
                    }
                    finally {
                        $pullPS.Dispose()
                    }

                    $progressDlg.Close()
                }
            })

            $pullTimer.Start()
            [void]$progressDlg.ShowDialog()
            $progressDlg.Dispose()

            if ($null -eq $script:PullResult -or -not $script:PullResult.Success) {
                $errMsg = if ($null -ne $script:PullResult) { $script:PullResult.Message } else { '未知錯誤' }
                [System.Windows.Forms.MessageBox]::Show(
                    "模型下載失敗：$errMsg",
                    '下載失敗',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return $null
            }

            # Model pulled successfully — use it
            $txtModelName.Text = $modelToPull
        }
        else {
            # Models exist — auto-fill with the first model if default not found
            $defaultModel = 'llama3.2:3b'
            if ($installedModels -contains $defaultModel) {
                $txtModelName.Text = $defaultModel
            }
            else {
                $txtModelName.Text = $installedModels[0]
            }
        }
    }

    # Determine provider name
    $providerName = if ($selected -match 'OpenAI') { 'OpenAI' }
                    elseif ($selected -match 'Gemini') { 'Gemini' }
                    elseif ($selected -match 'Llama')  { 'Llama' }
                    elseif ($selected -match 'Ollama') { 'Ollama' }
                    else { 'Custom' }

    $choice = @{
        Provider     = $providerName
        DisplayName  = $selected
        ApiKey       = if ($preset.NeedsKey) { $txtKey.Text.Trim() } else { '' }
        Model        = $txtModelName.Text.Trim()
        BaseUrl      = $txtUrl.Text.Trim()
        BypassProxy  = $chkBypassProxy.Checked
    }

    $dlg.Dispose()
    return $choice
}

function Start-AiEnhancement {
    <#
    .SYNOPSIS
        Triggers AI enhancement on top of the local analysis.
    .DESCRIPTION
        Shows a provider selection dialog, then runs the current data through
        Get-RateStatistics and calls the chosen AI API on a background thread.
        Supports any OpenAI-compatible endpoint.
    #>

    # --- Step 1: Show provider selection dialog ---
    $provider = Show-AiProviderDialog
    if ($null -eq $provider) { return }   # User cancelled

    $cur = $script:SelectedCurrency
    $period = $script:SelectedPeriod
    $providerName = $provider.Provider

    $txtAiAnalysis.Text = "🔄 正在呼叫 AI 增強分析 ($providerName)..."

    try {
        # Gather data for statistics
        if ($period -eq '本日') {
            $date = (Get-Date).ToString('yyyy-MM-dd')
            $url = "https://rate.bot.com.tw/xrt/quote/$date/$cur/spot"
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
            $intradayRates = ConvertFrom-BotHtml -RawHtml $response.Content
            if ($null -eq $intradayRates -or $intradayRates.Count -eq 0) {
                $txtAiAnalysis.Text = "📊 本日無即期匯率資料，無法進行 AI 分析。"
                return
            }
            $stats = Get-RateStatistics -DataPoints $intradayRates -Currency $cur -Period $period
        } else {
            if ($null -ne $script:LastChartData -and $script:LastChartData.Count -ge 5) {
                $dataPoints = $script:LastChartData
            } else {
                $range = Get-PeriodDateRange -Period $period
                $missingDates = [ref]@()
                $dataPoints = @(Get-HistoricalRange -CurrencyCode $cur -StartDate $range.StartDate -EndDate $range.EndDate -MissingDates $missingDates)
            }
            if ($null -eq $dataPoints -or $dataPoints.Count -lt 5) {
                $txtAiAnalysis.Text = "📊 歷史資料不足，無法進行 AI 分析。"
                return
            }
            $stats = Get-RateStatistics -DataPoints $dataPoints -Currency $cur -Period $period
        }

        $txtAiAnalysis.Text = "🤖 AI 增強分析中 ($providerName)，請稍候..."

        # --- Step 2: Build the background script with provider params ---
        $script:AiPS = [System.Management.Automation.PowerShell]::Create()
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('stats', $stats)

        # Pass provider info via variables
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiApiKey', $provider.ApiKey)
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiModel', $provider.Model)
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiBaseUrl', $provider.BaseUrl)
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiBypassProxy', $provider.BypassProxy)
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiProvider', $providerName)
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiDisplayName', $provider.DisplayName)

        $modulePath = Join-Path $scriptDir 'Modules'

        # Unified script: all params passed explicitly from dialog
        [void]$script:AiPS.AddScript(@"
            Import-Module (Join-Path '$modulePath' 'RateParser.psm1') -Force
            Import-Module (Join-Path '$modulePath' 'AIAnalyzer.psm1') -Force
            `$params = @{
                Statistics = `$stats
                ApiKey     = `$aiApiKey
                Model      = `$aiModel
                BaseUrl    = `$aiBaseUrl
            }
            if (`$aiBypassProxy) { `$params['BypassProxy'] = `$true }
            Get-AIAnalysis @params
"@)

        $script:AiAsync = $script:AiPS.BeginInvoke()

        # Poll for completion using a WinForms Timer
        $script:AiPollTimer = New-Object System.Windows.Forms.Timer
        $script:AiPollTimer.Interval = 500
        $script:AiPollStart = (Get-Date)

        $script:AiPollTimer.Add_Tick({
            # Bail out if form is closing
            if ($script:IsClosing) {
                $script:AiPollTimer.Stop()
                $script:AiPollTimer.Dispose()
                $script:AiPollTimer = $null
                if ($null -ne $script:AiPS) {
                    $script:AiPS.Stop()
                    $script:AiPS.Dispose()
                    $script:AiPS = $null
                }
                $script:AiAsync = $null
                return
            }

            # Timeout guard: 5 minutes max
            if (((Get-Date) - $script:AiPollStart).TotalMinutes -ge 5) {
                $script:AiPollTimer.Stop()
                $script:AiPollTimer.Dispose()
                $script:AiPollTimer = $null
                $txtAiAnalysis.Text = "⚠ AI 回應超時（5 分鐘），請檢查網路或更換模型。`n`n切換幣別/期間可返回本地分析報告"
                if ($null -ne $script:AiPS) {
                    $script:AiPS.Stop()
                    $script:AiPS.Dispose()
                    $script:AiPS = $null
                }
                $script:AiAsync = $null
                return
            }

            if ($script:AiAsync.IsCompleted) {
                $script:AiPollTimer.Stop()
                $script:AiPollTimer.Dispose()
                $script:AiPollTimer = $null

                try {
                    $results = $script:AiPS.EndInvoke($script:AiAsync)
                    $pName = $script:AiPS.Runspace.SessionStateProxy.GetVariable('aiProvider')
                    $pDisplay = $script:AiPS.Runspace.SessionStateProxy.GetVariable('aiDisplayName')

                    if ($script:AiPS.HadErrors -and $script:AiPS.Streams.Error.Count -gt 0) {
                        $errMsg = ($script:AiPS.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
                        $txtAiAnalysis.Text = "⚠ AI 增強分析失敗 ($pDisplay): $errMsg`n`n切換幣別/期間可返回本地分析報告"
                    }
                    elseif ($null -ne $results -and $results.Count -gt 0) {
                        $aiText = $results[0]
                        $txtAiAnalysis.Text = "🤖 AI 增強分析 ($pDisplay)`n`n$aiText`n`n━━━━━━━━━━━━━━━━━━━━━`n切換幣別/期間可返回本地分析報告"
                    }
                    else {
                        $txtAiAnalysis.Text = "⚠ AI 增強分析未返回結果，請檢查網路連線。`n`n切換幣別/期間可返回本地分析報告"
                    }
                } catch {
                    $txtAiAnalysis.Text = "⚠ AI 增強分析失敗: $($_.Exception.Message)`n`n切換幣別/期間可返回本地分析報告"
                } finally {
                    $script:AiPS.Dispose()
                    $script:AiPS = $null
                    $script:AiAsync = $null
                }
            }
        })

        $script:AiPollTimer.Start()

    } catch {
        $txtAiAnalysis.Text = "⚠ AI 增強分析失敗: $($_.Exception.Message)"
    }
}

function Load-ChartData {
    param(
        [string]$PeriodContext = $script:SelectedPeriod
    )

    # Cancel any running fetch
    Stop-FetchJob

    $cur = $script:SelectedCurrency
    $period = $script:SelectedPeriod
    $range = Get-PeriodDateRange -Period $period
    Set-ChartPeriod -Chart $script:Chart -Period $period

    if ($period -eq '本日') {
        # Intraday: fetch synchronously (single request)
        $lblStatus.Text = "讀取本日資料..."
        $lblFetchProgress.Text = ""
        $statusProgressBar.Visible = $true
        $statusProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $date = (Get-Date).ToString('yyyy-MM-dd')
            $url = "https://rate.bot.com.tw/xrt/quote/$date/$cur/spot"
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
            $intradayRates = ConvertFrom-BotHtml -RawHtml $response.Content

            if ($null -ne $intradayRates -and $intradayRates.Count -gt 0) {
                Update-ChartDataIntraday -Chart $script:Chart -IntradayPoints $intradayRates
                $script:LastChartData = $intradayRates
            } else {
                Update-ChartDataIntraday -Chart $script:Chart -IntradayPoints @()
                $script:LastChartData = @()
            }
            $lblStatus.Text = "就緒 ✓"
        } catch {
            $lblStatus.Text = "讀取失敗 (網路問題)"
            # Clear chart gracefully
            foreach ($series in $script:Chart.Series) {
                $series.Points.Clear()
            }
            if ($script:Chart.Titles.Count -gt 0) {
                $script:Chart.Titles[0].Text = '尚無資料'
            }
            $script:Chart.Invalidate()
        }
        $statusProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $statusProgressBar.Visible = $false
        return
    }

    # Historical: load cached data, then fetch missing dates in batch
    $missingDates = [ref]@()
    $cachedData = @(Get-HistoricalRange -CurrencyCode $cur -StartDate $range.StartDate -EndDate $range.EndDate -MissingDates $missingDates)

    # Show cached data immediately (null-safe)
    if ($null -ne $cachedData -and $cachedData.Count -gt 0) {
        Update-ChartData -Chart $script:Chart -DataPoints $cachedData
    } else {
        Update-ChartData -Chart $script:Chart -DataPoints @()
    }

    $totalMissing = $missingDates.Value.Count

    if ($totalMissing -eq 0) {
        $lblStatus.Text = "就緒 ✓"
        $lblFetchProgress.Text = "已快取: $($cachedData.Count) 筆"
        $statusProgressBar.Visible = $false
        return
    }

    # --- Batch fetch all missing dates with parallel runspaces (6 concurrent) ---
    $script:IsFetching = $true
    $fetchResults = @($cachedData)
    $fetchQueue = @($missingDates.Value | Sort-Object)
    $totalMissing = $fetchQueue.Count

    # Show progress bar
    $statusProgressBar.Visible = $true
    $statusProgressBar.Value = 0
    $statusProgressBar.Maximum = $totalMissing
    $lblStatus.Text = "讀取中... (0/$totalMissing)"
    [System.Windows.Forms.Application]::DoEvents()

    # Start loading spinner in chart title
    $script:SpinnerFrames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $script:SpinnerTimer = New-Object System.Windows.Forms.Timer
    $script:SpinnerTimer.Interval = 150
    $script:SpinnerTimer.Add_Tick({
        if ($script:IsClosing -or $script:Chart.Titles.Count -eq 0 -or -not $script:IsFetching) { return }
        $script:SpinnerTimer.Tag = (([int]$script:SpinnerTimer.Tag + 1) % $script:SpinnerFrames.Count)
        $frame = $script:SpinnerFrames[[int]$script:SpinnerTimer.Tag]
        $script:Chart.Titles[0].Text = "$frame  讀取匯率資料中..."
        $script:Chart.Invalidate()
    })
    $script:SpinnerTimer.Tag = 0
    $script:SpinnerTimer.Start()

    # --- Parallel fetch using RunspacePool (6 concurrent threads) ---
    $concurrency = 6
    $script:RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $concurrency)
    $script:RunspacePool.Open()

    $modPath = $scriptDir  # capture for closure

    # Build per-date scripts
    $jobs = @()
    foreach ($dateStr in $fetchQueue) {
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.RunspacePool = $script:RunspacePool

        [void]$ps.AddScript({
            param([string]$__dateStr, [string]$__cur, [string]$__modPath)
            Import-Module (Join-Path $__modPath 'Modules\RateParser.psm1') -Force
            Import-Module (Join-Path $__modPath 'Modules\DataFetcher.psm1') -Force

            $cacheRoot = Join-Path $__modPath 'Cache'
            Initialize-Cache -CacheRootPath $cacheRoot

            # Check cache first (another thread may have populated it)
            $cached = Get-CachedDate -CurrencyCode $__cur -Date $__dateStr
            if ($null -ne $cached) {
                return [PSCustomObject]@{
                    Date     = $cached.date
                    CashBuy  = $cached.closeRate.CashBuy
                    CashSell = $cached.closeRate.CashSell
                    SpotBuy  = $cached.closeRate.SpotBuy
                    SpotSell = $cached.closeRate.SpotSell
                }
            }

            $url = "https://rate.bot.com.tw/xrt/quote/$__dateStr/$__cur/spot"
            try {
                # Configure proxy for this request
                [System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
                [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
                $intradayRates = ConvertFrom-BotHtml -RawHtml $response.Content
                $closingRate = Get-ClosingRate -IntradayRates $intradayRates -Date $__dateStr

                if ($null -ne $closingRate) {
                    $cacheData = [PSCustomObject]@{
                        date      = $__dateStr
                        currency  = $__cur
                        closeRate = $closingRate
                        fetchedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                    }
                    Save-Cache -CurrencyCode $__cur -Date $__dateStr -Data $cacheData

                    return [PSCustomObject]@{
                        Date     = $__dateStr
                        CashBuy  = $closingRate.CashBuy
                        CashSell = $closingRate.CashSell
                        SpotBuy  = $closingRate.SpotBuy
                        SpotSell = $closingRate.SpotSell
                    }
                }
            } catch { }

            return $null
        }).AddArgument($dateStr).AddArgument($cur).AddArgument($modPath)

        $jobs += @{
            PS    = $ps
            Async = $ps.BeginInvoke()
            Date  = $dateStr
        }
    }

    # Poll for completion with DoEvents so UI stays responsive
    $completedCount = 0
    while ($completedCount -lt $jobs.Count -and -not $script:IsClosing) {
        [System.Windows.Forms.Application]::DoEvents()

        for ($j = 0; $j -lt $jobs.Count; $j++) {
            if ($null -ne $jobs[$j] -and $jobs[$j].Async.IsCompleted) {
                $completedCount++

                # Update progress
                if (-not $script:IsClosing) {
                    $statusProgressBar.Value = $completedCount
                    $lblStatus.Text = "讀取中... ($completedCount/$($jobs.Count))"
                    $lblFetchProgress.Text = "$completedCount/$($jobs.Count)"
                }

                try {
                    $result = $jobs[$j].PS.EndInvoke($jobs[$j].Async)
                    if ($null -ne $result -and $result.Count -gt 0 -and $null -ne $result[0]) {
                        $fetchResults += $result[0]
                    }
                } catch {
                    # Skip failed fetch
                } finally {
                    $jobs[$j].PS.Dispose()
                    $jobs[$j] = $null
                }
            }
        }

        # Short sleep to avoid busy-waiting while still responsive
        Start-Sleep -Milliseconds 50
    }

    # If form is closing, just dispose runspaces and exit — don't touch UI
    if ($script:IsClosing) {
        foreach ($j_item in $jobs) {
            if ($null -ne $j_item -and $null -ne $j_item.PS) {
                try { $j_item.PS.Dispose() } catch { }
            }
        }
        try {
            $script:RunspacePool.Close()
            $script:RunspacePool.Dispose()
        } catch { }
        $script:RunspacePool = $null
        $script:IsFetching = $false
        return
    }

    $script:RunspacePool.Close()
    $script:RunspacePool.Dispose()

    # All done — update chart with complete data
    if ($fetchResults.Count -gt 0) {
        $sorted = $fetchResults | Sort-Object -Property Date
        Update-ChartData -Chart $script:Chart -DataPoints $sorted
        $script:LastChartData = @($sorted)
    } else {
        $script:LastChartData = @()
    }

    # Stop spinner and restore chart title
    if ($null -ne $script:SpinnerTimer) {
        $script:SpinnerTimer.Stop()
        $script:SpinnerTimer.Dispose()
        $script:SpinnerTimer = $null
    }
    if ($script:Chart.Titles.Count -gt 0) {
        $script:Chart.Titles[0].Text = '歷史匯率曲線'
    }

    # Hide progress bar
    $statusProgressBar.Visible = $false
    $statusProgressBar.Value = 0

    $script:IsFetching = $false
    $lblStatus.Text = "就緒 ✓"
    $lblFetchProgress.Text = "共 $($fetchResults.Count) 筆"
}

# =============================================================================
# 5b. Auto-Refresh Timer (10-second interval)
# =============================================================================

$script:AutoRefreshTimer = New-Object System.Windows.Forms.Timer
$script:AutoRefreshTimer.Interval = 10000  # 10 seconds

$script:AutoRefreshTimer.Add_Tick({
    try {
        if ($script:IsClosing -or $script:IsFetching) { return }

        # Expire the in-memory cache so Get-CurrentRates fetches fresh data
        Expire-Cache

        $script:CurrentRates = Get-CurrentRates
        Update-RateDisplay
    } catch {
        # Silently ignore — next tick will retry
    }
})

# =============================================================================
# 6. Form Construction
# =============================================================================

# --- Main Form ---
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(1200, 720)
$form.MinimumSize = New-Object System.Drawing.Size(900, 500)
$form.Text = "台灣銀行外匯查詢工具"
$form.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 45)

# --- TableLayoutPanel: top-level layout (2 columns) ---
$mainTable = New-Object System.Windows.Forms.TableLayoutPanel
$mainTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainTable.ColumnCount = 2
$mainTable.RowCount = 1
$mainTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 520)))
$mainTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mainTable.RowStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mainTable.Padding = New-Object System.Windows.Forms.Padding(0)
$mainTable.Margin = New-Object System.Windows.Forms.Padding(0)
$form.Controls.Add($mainTable)

# =============================================================================
# 7. LEFT COLUMN — Currency Selection + Chart
# =============================================================================

# Label: 貨幣選擇
$lblCurrencyHeader = New-Object System.Windows.Forms.Label
$lblCurrencyHeader.Text = "貨幣選擇"
$lblCurrencyHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$lblCurrencyHeader.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10, [System.Drawing.FontStyle]::Bold)
$lblCurrencyHeader.Height = 30
$lblCurrencyHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCurrencyHeader.Padding = New-Object System.Windows.Forms.Padding(5)
$lblCurrencyHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)

# TextBox: Search
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Name = 'txtSearch'
$txtSearch.Text = "搜尋貨幣..."
$txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(100, 110, 135)
$txtSearch.Dock = [System.Windows.Forms.DockStyle]::Top
$txtSearch.Height = 30
$txtSearch.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
$txtSearch.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)

# ComboBox: Currency List
$cmbCurrency = New-Object System.Windows.Forms.ComboBox
$cmbCurrency.Name = 'cmbCurrency'
$cmbCurrency.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbCurrency.Sorted = $true
$cmbCurrency.Dock = [System.Windows.Forms.DockStyle]::Top
$cmbCurrency.Height = 28
$cmbCurrency.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)

# Populate items
foreach ($cur in $Currencies) {
    $cmbCurrency.Items.Add("$($cur.Code) $($cur.Name)") | Out-Null
}

# Chart Host Panel (fills remaining space below ComboBox)
$pnlChart = New-Object System.Windows.Forms.Panel
$pnlChart.Name = 'pnlChart'
$pnlChart.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlChart.BackColor = [System.Drawing.Color]::FromArgb(35, 38, 52)

# Left panel container
$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$leftPanel.Padding = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)
$leftPanel.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)

# Add controls to left panel in reverse Dock order (Fill first, then Top)
$leftPanel.Controls.Add($pnlChart)
$leftPanel.Controls.Add($cmbCurrency)
$leftPanel.Controls.Add($txtSearch)
$leftPanel.Controls.Add($lblCurrencyHeader)

# Create Chart control
$script:Chart = New-RateChart -Width 500 -Height 400
$script:Chart.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlChart.Controls.Add($script:Chart)

$mainTable.Controls.Add($leftPanel, 0, 0)

# =============================================================================
# 8. RIGHT COLUMN — Rate Display + Period Selector
# =============================================================================

# --- Top Info Panel ---
$infoPanel = New-Object System.Windows.Forms.Panel
$infoPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$infoPanel.Height = 120
$infoPanel.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)
$infoPanel.Padding = New-Object System.Windows.Forms.Padding(10)

# Currency Title Label
$lblCurrencyTitle = New-Object System.Windows.Forms.Label
$lblCurrencyTitle.Name = 'lblCurrencyTitle'
$lblCurrencyTitle.Text = "USD 美金"
$lblCurrencyTitle.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 16, [System.Drawing.FontStyle]::Bold)
$lblCurrencyTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblCurrencyTitle.Location = New-Object System.Drawing.Point(10, 10)
$lblCurrencyTitle.AutoSize = $true
$infoPanel.Controls.Add($lblCurrencyTitle)

# Rate Labels (2x2 grid)
$lblCashBuy = New-Object System.Windows.Forms.Label
$lblCashBuy.Text = "現金買入: --"
$lblCashBuy.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblCashBuy.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblCashBuy.Location = New-Object System.Drawing.Point(10, 45)
$lblCashBuy.AutoSize = $true
$infoPanel.Controls.Add($lblCashBuy)

$lblCashSell = New-Object System.Windows.Forms.Label
$lblCashSell.Text = "現金賣出: --"
$lblCashSell.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblCashSell.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblCashSell.Location = New-Object System.Drawing.Point(250, 45)
$lblCashSell.AutoSize = $true
$infoPanel.Controls.Add($lblCashSell)

$lblSpotBuy = New-Object System.Windows.Forms.Label
$lblSpotBuy.Text = "即期買入: --"
$lblSpotBuy.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblSpotBuy.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblSpotBuy.Location = New-Object System.Drawing.Point(10, 75)
$lblSpotBuy.AutoSize = $true
$infoPanel.Controls.Add($lblSpotBuy)

$lblSpotSell = New-Object System.Windows.Forms.Label
$lblSpotSell.Text = "即期賣出: --"
$lblSpotSell.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblSpotSell.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblSpotSell.Location = New-Object System.Drawing.Point(250, 75)
$lblSpotSell.AutoSize = $true
$infoPanel.Controls.Add($lblSpotSell)

# Update Time Label
$lblUpdateTime = New-Object System.Windows.Forms.Label
$lblUpdateTime.Name = 'lblUpdateTime'
$lblUpdateTime.Text = "更新時間: --"
$lblUpdateTime.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$lblUpdateTime.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
$lblUpdateTime.Location = New-Object System.Drawing.Point(500, 10)
$lblUpdateTime.AutoSize = $true
$infoPanel.Controls.Add($lblUpdateTime)

# CheckBox: 置頂 (Always on Top)
$chkTopMost = New-Object System.Windows.Forms.CheckBox
$chkTopMost.Name = 'chkTopMost'
$chkTopMost.Text = "置頂"
$chkTopMost.Checked = $false
$chkTopMost.Location = New-Object System.Drawing.Point(650, 10)
$chkTopMost.AutoSize = $true
$infoPanel.Controls.Add($chkTopMost)

# Button: 重新整理 (Refresh)
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Name = 'btnRefresh'
$btnRefresh.Text = "重新整理"
$btnRefresh.Location = New-Object System.Drawing.Point(720, 6)
$btnRefresh.Size = New-Object System.Drawing.Size(80, 28)
$btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(138, 43, 226)
$btnRefresh.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$infoPanel.Controls.Add($btnRefresh)

# =============================================================================
# 8b. CONVERTER PANEL — Currency Exchange Calculator
# =============================================================================

$converterPanel = New-Object System.Windows.Forms.Panel
$converterPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$converterPanel.Height = 88
$converterPanel.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)
$converterPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

# --- Converter Header ---
$lblConverterHeader = New-Object System.Windows.Forms.Label
$lblConverterHeader.Text = "💱 匯率換算"
$lblConverterHeader.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10, [System.Drawing.FontStyle]::Bold)
$lblConverterHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblConverterHeader.Location = New-Object System.Drawing.Point(10, 5)
$lblConverterHeader.AutoSize = $true
$converterPanel.Controls.Add($lblConverterHeader)

# --- Radio Buttons: Spot / Cash ---
$rbSpotRate = New-Object System.Windows.Forms.RadioButton
$rbSpotRate.Text = "即期"
$rbSpotRate.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$rbSpotRate.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$rbSpotRate.Location = New-Object System.Drawing.Point(110, 6)
$rbSpotRate.AutoSize = $true
$rbSpotRate.Checked = $true
$converterPanel.Controls.Add($rbSpotRate)

$rbCashRate = New-Object System.Windows.Forms.RadioButton
$rbCashRate.Text = "現金"
$rbCashRate.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$rbCashRate.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$rbCashRate.Location = New-Object System.Drawing.Point(170, 6)
$rbCashRate.AutoSize = $true
$converterPanel.Controls.Add($rbCashRate)

# --- Row 1: TWD input ↔ Foreign input ---
$lblTwdCurrency = New-Object System.Windows.Forms.Label
$lblTwdCurrency.Text = "TWD 台幣"
$lblTwdCurrency.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
$lblTwdCurrency.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
$lblTwdCurrency.Location = New-Object System.Drawing.Point(10, 30)
$lblTwdCurrency.AutoSize = $true
$converterPanel.Controls.Add($lblTwdCurrency)

$txtTwdAmount = New-Object System.Windows.Forms.TextBox
$txtTwdAmount.Name = 'txtTwdAmount'
$txtTwdAmount.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$txtTwdAmount.Location = New-Object System.Drawing.Point(80, 27)
$txtTwdAmount.Size = New-Object System.Drawing.Size(120, 24)
$txtTwdAmount.BackColor = [System.Drawing.Color]::FromArgb(25, 28, 42)
$txtTwdAmount.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 136)
$txtTwdAmount.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtTwdAmount.Text = '1'
$txtTwdAmount.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
$converterPanel.Controls.Add($txtTwdAmount)

# Swap icon
$lblSwapIcon = New-Object System.Windows.Forms.Label
$lblSwapIcon.Text = "⟷"
$lblSwapIcon.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 14)
$lblSwapIcon.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblSwapIcon.Location = New-Object System.Drawing.Point(208, 25)
$lblSwapIcon.Size = New-Object System.Drawing.Size(30, 28)
$lblSwapIcon.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$converterPanel.Controls.Add($lblSwapIcon)

$lblForeignCurrency = New-Object System.Windows.Forms.Label
$lblForeignCurrency.Text = "USD 美金"
$lblForeignCurrency.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
$lblForeignCurrency.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
$lblForeignCurrency.Location = New-Object System.Drawing.Point(240, 30)
$lblForeignCurrency.AutoSize = $true
$converterPanel.Controls.Add($lblForeignCurrency)

$txtForeignAmount = New-Object System.Windows.Forms.TextBox
$txtForeignAmount.Name = 'txtForeignAmount'
$txtForeignAmount.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$txtForeignAmount.Location = New-Object System.Drawing.Point(330, 27)
$txtForeignAmount.Size = New-Object System.Drawing.Size(120, 24)
$txtForeignAmount.BackColor = [System.Drawing.Color]::FromArgb(25, 28, 42)
$txtForeignAmount.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 50)
$txtForeignAmount.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtForeignAmount.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
$converterPanel.Controls.Add($txtForeignAmount)

# --- Info Label (rate reference) ---
$lblConverterInfo = New-Object System.Windows.Forms.Label
$lblConverterInfo.Name = 'lblConverterInfo'
$lblConverterInfo.Text = "即期賣出: -- | 即期買入: --"
$lblConverterInfo.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$lblConverterInfo.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 155)
$lblConverterInfo.Location = New-Object System.Drawing.Point(10, 57)
$lblConverterInfo.AutoSize = $true
$converterPanel.Controls.Add($lblConverterInfo)

# --- Period Selector Bar ---
$periodBar = New-Object System.Windows.Forms.Panel
$periodBar.Dock = [System.Windows.Forms.DockStyle]::Top
$periodBar.Height = 45
$periodBar.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)
$periodBar.Padding = New-Object System.Windows.Forms.Padding(5)

# FlowLayoutPanel for period buttons
$flowPeriod = New-Object System.Windows.Forms.FlowLayoutPanel
$flowPeriod.Dock = [System.Windows.Forms.DockStyle]::Fill
$flowPeriod.Padding = New-Object System.Windows.Forms.Padding(5)
$flowPeriod.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)
$periodBar.Controls.Add($flowPeriod)

# Create period buttons
$periodNames = @('本日', '本月', '3個月', '半年', '1年', '3年', '5年', '10年')
$periodButtons = @()

foreach ($pn in $periodNames) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Name = "btnPeriod_$pn"
    $btn.Text = $pn
    $btn.Tag = $pn
    $btn.Width = 70
    $btn.Height = 30
    $btn.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    # Default styling: first button (本日) is active
    if ($pn -eq '本日') {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(0, 212, 255)   # Neon cyan
        $btn.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 45)
    } else {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 75) # Dark gray
        $btn.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
    }

    $periodButtons += $btn
    $flowPeriod.Controls.Add($btn)
}

# Right panel container
$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$rightPanel.Padding = New-Object System.Windows.Forms.Padding(5, 0, 5, 0)

# --- AI Analysis Panel (below period buttons, fills remaining space) ---
$aiPanel = New-Object System.Windows.Forms.Panel
$aiPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$aiPanel.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 58)
$aiPanel.Padding = New-Object System.Windows.Forms.Padding(5)

$lblAiHeader = New-Object System.Windows.Forms.Label
$lblAiHeader.Text = "📊 匯率智能分析"
$lblAiHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$lblAiHeader.Height = 28
$lblAiHeader.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10, [System.Drawing.FontStyle]::Bold)
$lblAiHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblAiHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$aiPanel.Controls.Add($lblAiHeader)

# Action button bar (Dock.Bottom)
$apiKeyBar = New-Object System.Windows.Forms.Panel
$apiKeyBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$apiKeyBar.Height = 32
$apiKeyBar.BackColor = [System.Drawing.Color]::FromArgb(35, 38, 52)

$btnAiEnhance = New-Object System.Windows.Forms.Button
$btnAiEnhance.Text = "🤖 AI 增強分析"
$btnAiEnhance.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAiEnhance.BackColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$btnAiEnhance.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 45)
$btnAiEnhance.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$btnAiEnhance.Size = New-Object System.Drawing.Size(110, 26)
$btnAiEnhance.Location = New-Object System.Drawing.Point(5, 3)
$apiKeyBar.Controls.Add($btnAiEnhance)

$lblAiProvider = New-Object System.Windows.Forms.Label
$lblAiProvider.Text = "Design by LWY"
$lblAiProvider.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$lblAiProvider.ForeColor = [System.Drawing.Color]::FromArgb(80, 90, 115)
$lblAiProvider.AutoSize = $true
$lblAiProvider.Location = New-Object System.Drawing.Point(125, 7)
$apiKeyBar.Controls.Add($lblAiProvider)

$aiPanel.Controls.Add($apiKeyBar)

$txtAiAnalysis = New-Object System.Windows.Forms.RichTextBox
$txtAiAnalysis.Name = 'txtAiAnalysis'
$txtAiAnalysis.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtAiAnalysis.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
$txtAiAnalysis.BackColor = [System.Drawing.Color]::FromArgb(25, 28, 42)
$txtAiAnalysis.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$txtAiAnalysis.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txtAiAnalysis.ReadOnly = $true
$txtAiAnalysis.Text = "選擇貨幣與期間後，將自動分析匯率趨勢並提供買入/賣出建議..."
$txtAiAnalysis.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$aiPanel.Controls.Add($txtAiAnalysis)

# Add controls to right panel in reverse Dock order (Fill first, then Top)
$rightPanel.Controls.Add($aiPanel)
$rightPanel.Controls.Add($periodBar)
$rightPanel.Controls.Add($converterPanel)
$rightPanel.Controls.Add($infoPanel)

$mainTable.Controls.Add($rightPanel, 1, 0)

# --- Status Bar Panel (larger, more visible than StatusStrip) ---
$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusPanel.Height = 42
$statusPanel.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 28)
$statusPanel.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "就緒"
$lblStatus.Name = 'lblStatus'
$lblStatus.AutoSize = $true
$lblStatus.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9.5, [System.Drawing.FontStyle]::Bold)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblStatus.Location = New-Object System.Drawing.Point(10, 3)
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusPanel.Controls.Add($lblStatus)

$lblFetchProgress = New-Object System.Windows.Forms.Label
$lblFetchProgress.Text = ""
$lblFetchProgress.Name = 'lblFetchProgress'
$lblFetchProgress.AutoSize = $true
$lblFetchProgress.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
$lblFetchProgress.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 136)
$lblFetchProgress.Location = New-Object System.Drawing.Point(400, 5)
$lblFetchProgress.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusPanel.Controls.Add($lblFetchProgress)

$statusProgressBar = New-Object System.Windows.Forms.ProgressBar
$statusProgressBar.Name = 'statusProgressBar'
$statusProgressBar.Location = New-Object System.Drawing.Point(10, 24)
$statusProgressBar.Size = New-Object System.Drawing.Size(1160, 12)
$statusProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$statusProgressBar.Minimum = 0
$statusProgressBar.Maximum = 100
$statusProgressBar.Value = 0
$statusProgressBar.Visible = $false
$statusPanel.Controls.Add($statusProgressBar)

$form.Controls.Add($statusPanel)

# Resize progress bar when form is resized
$form.Add_Resize({
    $statusProgressBar.Width = $form.ClientSize.Width - 20
})

# =============================================================================
# 9. Event Handlers
# =============================================================================

# --- Search Box: Placeholder behavior ---
$txtSearch.Add_Enter({
    if ($txtSearch.Text -eq "搜尋貨幣...") {
        $txtSearch.Text = ""
        $txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
    }
})

$txtSearch.Add_Leave({
    if ([string]::IsNullOrWhiteSpace($txtSearch.Text)) {
        $txtSearch.Text = "搜尋貨幣..."
        $txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(100, 110, 135)
    }
})

# --- Search Box: Filter currency list ---
$txtSearch.Add_TextChanged({
    if ($txtSearch.Text -eq "搜尋貨幣...") { return }
    $filter = $txtSearch.Text.Trim()
    if ($filter -eq "搜尋貨幣...") { $filter = "" }

    $cmbCurrency.Items.Clear()
    foreach ($cur in $Currencies) {
        $display = "$($cur.Code) $($cur.Name)"
        if ([string]::IsNullOrEmpty($filter) -or
            $display -like "*$filter*" -or
            $cur.Code -like "*$filter*" -or
            $cur.Name -like "*$filter*") {
            $cmbCurrency.Items.Add($display) | Out-Null
        }
    }
    if ($cmbCurrency.Items.Count -gt 0) {
        $cmbCurrency.SelectedIndex = 0
    }
})

# --- ComboBox: Selection Changed ---
$cmbCurrency.Add_SelectedIndexChanged({
    if ($cmbCurrency.SelectedItem) {
        $script:SelectedCurrency = ($cmbCurrency.SelectedItem -split ' ')[0]
        Update-RateDisplay
        Load-ChartData
        Start-AiAnalysis

        # Persist selected currency
        $settings = Get-AppSettings
        $settings.LastSelectedCurrency = $script:SelectedCurrency
        Set-AppSettings -Settings $settings
    }
})

# --- Period Buttons: Shared Click Handler ---
$periodHandler = {
    $btn = $this
    $script:SelectedPeriod = $btn.Tag

    # Update button styling
    foreach ($ctrl in $flowPeriod.Controls) {
        if ($ctrl -is [System.Windows.Forms.Button]) {
            if ($ctrl.Tag -eq $script:SelectedPeriod) {
                $ctrl.BackColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
                $ctrl.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 45)
            } else {
                $ctrl.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 75)
                $ctrl.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
            }
        }
    }

    Load-ChartData
    Start-AiAnalysis
}

foreach ($btn in $periodButtons) {
    $btn.Add_Click($periodHandler)
}

# --- Converter: TWD TextBox events ---
$txtTwdAmount.Add_Enter({
    $script:ConverterDirection = 'TWD'
})

$txtTwdAmount.Add_TextChanged({
    if ($script:ConverterUpdating) { return }
    $script:ConverterDirection = 'TWD'
    Update-Converter
})

$txtTwdAmount.Add_KeyPress({
    # Allow only digits, decimal point, and backspace
    if ($_.KeyChar -eq '.' -and $txtTwdAmount.Text.Contains('.')) {
        $_.Handled = $true  # Prevent second decimal point
    }
    elseif (-not [char]::IsDigit($_.KeyChar) -and $_.KeyChar -ne '.' -and $_.KeyChar -ne "`b") {
        $_.Handled = $true
    }
})

# --- Converter: Foreign Currency TextBox events ---
$txtForeignAmount.Add_Enter({
    $script:ConverterDirection = 'Foreign'
})

$txtForeignAmount.Add_TextChanged({
    if ($script:ConverterUpdating) { return }
    $script:ConverterDirection = 'Foreign'
    Update-Converter
})

$txtForeignAmount.Add_KeyPress({
    # Allow only digits, decimal point, and backspace
    if ($_.KeyChar -eq '.' -and $txtForeignAmount.Text.Contains('.')) {
        $_.Handled = $true  # Prevent second decimal point
    }
    elseif (-not [char]::IsDigit($_.KeyChar) -and $_.KeyChar -ne '.' -and $_.KeyChar -ne "`b") {
        $_.Handled = $true
    }
})

# --- Converter: Spot/Cash Radio Buttons ---
$rbSpotRate.Add_CheckedChanged({
    if ($rbSpotRate.Checked) {
        $script:ConverterRateType = 'Spot'
        Update-Converter
    }
})

$rbCashRate.Add_CheckedChanged({
    if ($rbCashRate.Checked) {
        $script:ConverterRateType = 'Cash'
        Update-Converter
    }
})

# --- CheckBox: Always on Top ---
$chkTopMost.Add_CheckedChanged({
    $form.TopMost = $chkTopMost.Checked
})

# --- Button: AI Enhancement ---
$btnAiEnhance.Add_Click({
    Start-AiEnhancement
})

# --- Button: Refresh ---
$btnRefresh.Add_Click({
    $lblStatus.Text = "重新整理中..."
    $lblFetchProgress.Text = ""
    [System.Windows.Forms.Application]::DoEvents()

    try {
        # Expire the DataFetcher in-memory cache
        Expire-Cache

        $script:CurrentRates = Get-CurrentRates
        Update-RateDisplay
        $lblStatus.Text = "就緒 ✓"
    } catch {
        $lblStatus.Text = "重新整理失敗: $($_.Exception.Message)"
    }
})

# --- Form: Closing cleanup ---
$form.Add_FormClosing({
    # Set flag FIRST so all timer ticks and UI updates bail out immediately
    $script:IsClosing = $true
    $script:IsFetching = $false

    Stop-FetchJob
    if ($null -ne $script:AutoRefreshTimer) {
        $script:AutoRefreshTimer.Stop()
        $script:AutoRefreshTimer.Dispose()
        $script:AutoRefreshTimer = $null
    }
    if ($null -ne $script:AiDebounceTimer) {
        $script:AiDebounceTimer.Stop()
        $script:AiDebounceTimer.Dispose()
        $script:AiDebounceTimer = $null
    }
    if ($null -ne $script:AiWaitTimer) {
        $script:AiWaitTimer.Stop()
        $script:AiWaitTimer.Dispose()
        $script:AiWaitTimer = $null
    }
    if ($null -ne $script:AiPollTimer) {
        $script:AiPollTimer.Stop()
        $script:AiPollTimer.Dispose()
        $script:AiPollTimer = $null
    }
    if ($null -ne $script:SpinnerTimer) {
        $script:SpinnerTimer.Stop()
        $script:SpinnerTimer.Dispose()
        $script:SpinnerTimer = $null
    }
    if ($null -ne $script:AiPS) {
        $script:AiPS.Stop()
        $script:AiPS.Dispose()
        $script:AiPS = $null
    }
    if ($null -ne $script:RunspacePool) {
        try {
            $script:RunspacePool.Close()
            $script:RunspacePool.Dispose()
        } catch { }
        $script:RunspacePool = $null
    }
})

# =============================================================================
# 10. Startup Sequence
# =============================================================================

# Select currency from saved settings (or default USD)
$settings = Get-AppSettings
$savedCurrency = $settings.LastSelectedCurrency
if ([string]::IsNullOrWhiteSpace($savedCurrency)) { $savedCurrency = 'USD' }

$selectItem = $cmbCurrency.Items | Where-Object { $_ -like "$savedCurrency *" } | Select-Object -First 1
if ($null -ne $selectItem) {
    $cmbCurrency.SelectedItem = $selectItem
} else {
    # Fallback to USD
    $selectUsd = $cmbCurrency.Items | Where-Object { $_ -like 'USD *' } | Select-Object -First 1
    if ($null -ne $selectUsd) {
        $cmbCurrency.SelectedItem = $selectUsd
    }
}

# Fetch current rates
$lblStatus.Text = "讀取即時匯率..."
$lblFetchProgress.Text = ""
[System.Windows.Forms.Application]::DoEvents()

try {
    $script:CurrentRates = @(Get-CurrentRates)
    Update-RateDisplay
    $lblStatus.Text = "就緒 ✓"
} catch {
    $script:CurrentRates = @()
    $lblStatus.Text = "讀取失敗 (網路問題)"
    $lblCurrencyTitle.Text = "$($script:SelectedCurrency) $(Get-CurrencyName -Code $script:SelectedCurrency)"
    $lblCashBuy.Text = "現金買入: --"
    $lblCashSell.Text = "現金賣出: --"
    $lblSpotBuy.Text = "即期買入: --"
    $lblSpotSell.Text = "即期賣出: --"
    $lblUpdateTime.Text = "更新時間: --"
}

# Load default chart data (本日 for USD)
Load-ChartData

# Start auto-refresh timer
$script:AutoRefreshTimer.Start()

# Trigger initial AI analysis
Start-AiAnalysis

# =============================================================================
# 11. Run Application
# =============================================================================
[System.Windows.Forms.Application]::Run($form)
