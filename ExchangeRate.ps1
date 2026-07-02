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

# Force TLS 1.2 for rate.bot.com.tw compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =============================================================================
# WAF Bypass Helper: Browser-like headers for rate.bot.com.tw
# The site uses a WAF (Challenge Validation) that blocks non-browser clients.
# Adding Sec-Fetch headers and a Chrome User-Agent bypasses this check.
# =============================================================================
$script:BotWafHeaders = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
    'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8'
    'Accept-Language' = 'zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7'
    'Sec-Ch-Ua' = '"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"'
    'Sec-Ch-Ua-Mobile' = '?0'
    'Sec-Ch-Ua-Platform' = '"Windows"'
    'Sec-Fetch-Dest' = 'document'
    'Sec-Fetch-Mode' = 'navigate'
    'Sec-Fetch-Site' = 'none'
    'Sec-Fetch-User' = '?1'
    'Upgrade-Insecure-Requests' = '1'
}

function Invoke-BotWebRequest {
    <#
    .SYNOPSIS
        Makes an HTTP GET request to rate.bot.com.tw with browser-like headers to bypass WAF.
    .PARAMETER Uri
        The URL to request.
    .OUTPUTS
        [string] The decoded response content.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $req.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $req.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $req.Timeout = 30000
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    $req.UserAgent = $script:BotWafHeaders['User-Agent']
    $req.Accept = $script:BotWafHeaders['Accept']
    $req.Headers.Add('Accept-Language', $script:BotWafHeaders['Accept-Language'])
    $req.Headers.Add('Sec-Ch-Ua', $script:BotWafHeaders['Sec-Ch-Ua'])
    $req.Headers.Add('Sec-Ch-Ua-Mobile', $script:BotWafHeaders['Sec-Ch-Ua-Mobile'])
    $req.Headers.Add('Sec-Ch-Ua-Platform', $script:BotWafHeaders['Sec-Ch-Ua-Platform'])
    $req.Headers.Add('Sec-Fetch-Dest', $script:BotWafHeaders['Sec-Fetch-Dest'])
    $req.Headers.Add('Sec-Fetch-Mode', $script:BotWafHeaders['Sec-Fetch-Mode'])
    $req.Headers.Add('Sec-Fetch-Site', $script:BotWafHeaders['Sec-Fetch-Site'])
    $req.Headers.Add('Sec-Fetch-User', $script:BotWafHeaders['Sec-Fetch-User'])
    $req.Headers.Add('Upgrade-Insecure-Requests', $script:BotWafHeaders['Upgrade-Insecure-Requests'])

    $resp = $req.GetResponse()
    $stream = $resp.GetResponseStream()

    # Read raw bytes for encoding detection
    $ms = New-Object System.IO.MemoryStream
    $stream.CopyTo($ms)
    $bytes = $ms.ToArray()
    $ms.Close()
    $stream.Close()
    $resp.Close()

    # HTML pages from rate.bot.com.tw are UTF-8
    $encoding = [System.Text.Encoding]::UTF8

    # Check Content-Type for charset
    $contentType = $resp.Headers['Content-Type']
    if ($contentType -match 'charset=([\w-]+)') {
        $charset = $Matches[1].Trim().ToUpper()
        if ($charset -eq 'BIG5' -or $charset -eq 'CP950') {
            $encoding = [System.Text.Encoding]::GetEncoding(950)
        }
    }

    $content = $encoding.GetString($bytes)

    # Detect WAF challenge page
    if ($content -match 'Challenge Validation') {
        return ''
    }

    return $content
}

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
Import-Module (Join-Path $scriptDir "Modules\i18n.psm1") -Force

$cachePath = Join-Path $scriptDir "Cache"
Initialize-Cache -CacheRootPath $cachePath

# =============================================================================
# 3. Currency Data
# =============================================================================
$Currencies = @(
    @{ Code = 'USD' }
    @{ Code = 'JPY' }
    @{ Code = 'EUR' }
    @{ Code = 'GBP' }
    @{ Code = 'CNY' }
    @{ Code = 'HKD' }
    @{ Code = 'SGD' }
    @{ Code = 'AUD' }
    @{ Code = 'CAD' }
    @{ Code = 'CHF' }
    @{ Code = 'NZD' }
    @{ Code = 'THB' }
    @{ Code = 'PHP' }
    @{ Code = 'IDR' }
    @{ Code = 'KRW' }
    @{ Code = 'VND' }
    @{ Code = 'MYR' }
    @{ Code = 'ZAR' }
    @{ Code = 'SEK' }
)

# =============================================================================
# 4. Application State Variables
# =============================================================================
$script:CurrentRates = @()
$script:SelectedCurrency = 'USD'
$script:SelectedPeriod = 'today'
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
    $lblCurrencyTitle.Text = "$cur $(L "currency_$($cur.ToLower())")"

    if ($null -ne $rate) {
        if ($rate.CashBuy -eq 0) {
            $lblCashBuy.Text = "$(L 'label_cash_buy') $(L 'rate_na')"
        } else {
            $lblCashBuy.Text = "$(L 'label_cash_buy') $($rate.CashBuy)"
        }
        if ($rate.CashSell -eq 0) {
            $lblCashSell.Text = "$(L 'label_cash_sell') $(L 'rate_na')"
        } else {
            $lblCashSell.Text = "$(L 'label_cash_sell') $($rate.CashSell)"
        }
        if ($rate.SpotBuy -eq 0) {
            $lblSpotBuy.Text = "$(L 'label_spot_buy') $(L 'rate_na')"
        } else {
            $lblSpotBuy.Text = "$(L 'label_spot_buy') $($rate.SpotBuy)"
        }
        if ($rate.SpotSell -eq 0) {
            $lblSpotSell.Text = "$(L 'label_spot_sell') $(L 'rate_na')"
        } else {
            $lblSpotSell.Text = "$(L 'label_spot_sell') $($rate.SpotSell)"
        }
        $lblUpdateTime.Text = "$(L 'label_update_time') $(Get-Date -Format 'yyyy/MM/dd HH:mm')"
    } else {
        $lblCashBuy.Text = "$(L 'label_cash_buy') $(L 'rate_dash')"
        $lblCashSell.Text = "$(L 'label_cash_sell') $(L 'rate_dash')"
        $lblSpotBuy.Text = "$(L 'label_spot_buy') $(L 'rate_dash')"
        $lblSpotSell.Text = "$(L 'label_spot_sell') $(L 'rate_dash')"
        $lblUpdateTime.Text = "$(L 'label_update_time') $(L 'rate_dash')"
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
            $lblConverterInfo.Text = L 'converter_info_na'
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
            $lblConverterInfo.Text = L 'converter_no_type'
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
        $rateLabel = if ($script:ConverterRateType -eq 'Cash') { L 'rate_type_cash' } else { L 'rate_type_spot' }
        $lblConverterInfo.Text = L 'converter_info_format' $rateLabel $sellRate $buyRate $(Format-ConverterAmount -Value ([decimal]1 / $sellRate)) $cur
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
    $lblForeignCurrency.Text = "$cur $(L "currency_$($cur.ToLower())")"

    # Reposition textbox to avoid label overlap
    Update-ConverterLayout

    # Recalculate with current inputs
    Update-Converter
}

function Update-ConverterLayout {
    <#
    .SYNOPSIS
        Dynamically repositions converter textboxes based on label widths.
    .DESCRIPTION
        Measures the rendered width of currency labels and adjusts textbox
        positions so that long currency names (e.g. "ZAR South African Rand")
        never overlap the input fields.
    #>

    # --- TWD side ---
    $twdLabelWidth = $lblTwdCurrency.PreferredWidth
    $txtTwdAmount.Location = New-Object System.Drawing.Point(
        [Math]::Max(80, $lblTwdCurrency.Left + $twdLabelWidth + 6),
        $txtTwdAmount.Location.Y
    )

    # --- Foreign side ---
    # Measure label width; the swap icon sits between the two sides
    $foreignLabelWidth = $lblForeignCurrency.PreferredWidth
    $txtForeignAmount.Location = New-Object System.Drawing.Point(
        [Math]::Max(330, $lblForeignCurrency.Left + $foreignLabelWidth + 6),
        $txtForeignAmount.Location.Y
    )

    # If the textbox would run off the panel, apply AutoEllipsis to label
    $panelUsableWidth = $converterPanel.ClientSize.Width - 20
    if ($txtForeignAmount.Location.X + $txtForeignAmount.Width -gt $panelUsableWidth) {
        # Shrink the label to fit: anchor textbox at a safe position, limit label width
        $maxLabelWidth = $panelUsableWidth - $txtForeignAmount.Width - $lblForeignCurrency.Left - 6
        if ($maxLabelWidth -gt 0) {
            $lblForeignCurrency.AutoSize = $false
            $lblForeignCurrency.Width = $maxLabelWidth
            $lblForeignCurrency.AutoEllipsis = $true
            $txtForeignAmount.Location = New-Object System.Drawing.Point(
                $lblForeignCurrency.Left + $maxLabelWidth + 6,
                $txtForeignAmount.Location.Y
            )
        }
    } else {
        # Enough space — restore AutoSize
        $lblForeignCurrency.AutoSize = $true
        $lblForeignCurrency.AutoEllipsis = $false
    }
}

# =============================================================================
# 5a. Language Switching — Update-AllLabels
# =============================================================================
function Update-AllLabels {
    <#
    .SYNOPSIS
        Refreshes ALL visible UI text to the current language.
        Called after Set-Language to re-render all labels.
    #>
    if ($script:IsClosing) { return }

    # Form title
    $form.Text = L 'form_title'

    # Currency header
    $lblCurrencyHeader.Text = L 'currency_header'

    # Pin button
    $chkTopMost.Text = L 'btn_pin'

    # Refresh button
    $btnRefresh.Text = L 'btn_refresh'

    # Converter panel
    $lblConverterHeader.Text = "💱 $(L 'converter_header')"
    $rbSpotRate.Text = L 'rate_type_spot'
    $rbCashRate.Text = L 'rate_type_cash'
    $lblTwdCurrency.Text = L 'label_twd_currency'

    # AI panel
    $lblAiHeader.Text = "📊 $(L 'ai_panel_header')"
    $btnAiEnhance.Text = "🤖 $(L 'btn_ai_enhance')"

    # Period buttons
    for ($i = 0; $i -lt $periodIds.Count; $i++) {
        $btn = $periodButtons[$i]
        $btn.Text = Get-PeriodDisplay $periodIds[$i]
    }

    # Currency comboBox items — rebuild to reflect new language names
    $savedIdx = $cmbCurrency.SelectedIndex
    $cmbCurrency.Items.Clear()
    foreach ($cur in $Currencies) {
        $cmbCurrency.Items.Add("$($cur.Code) $(L "currency_$($cur.Code.ToLower())")") | Out-Null
    }
    if ($savedIdx -ge 0 -and $savedIdx -lt $cmbCurrency.Items.Count) {
        $cmbCurrency.SelectedIndex = $savedIdx
    }

    # Search box — update placeholder if it's showing placeholder text
    # After switching language, the old placeholder is in the *previous* language
    $prevPlaceholder = if ((Get-Language) -eq 'en') { '搜尋貨幣...' } else { 'Search currency...' }
    if ($txtSearch.Text -eq $prevPlaceholder -or [string]::IsNullOrWhiteSpace($txtSearch.Text)) {
        $txtSearch.Text = L 'search_placeholder'
        $txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(100, 110, 135)
    }

    # Re-apply rate display and converter with new language
    Update-RateDisplay

    # Chart title and legend — update localized text
    if ($null -ne $script:Chart) {
        if ($script:Chart.Titles.Count -gt 0) {
            $script:Chart.Titles[0].Text = L 'chart_title'
        }
        $seriesLabels = @{
            'CashBuy'  = 'series_cash_buy'
            'CashSell' = 'series_cash_sell'
            'SpotBuy'  = 'series_spot_buy'
            'SpotSell' = 'series_spot_sell'
        }
        foreach ($series in $script:Chart.Series) {
            if ($seriesLabels.ContainsKey($series.Name)) {
                $series.LegendText = L $seriesLabels[$series.Name]
            }
        }
        $script:Chart.Invalidate()
    }

    # Re-trigger AI analysis so the report text updates in the new language
    Start-AiAnalysis

    # Status bar — re-apply current status with correct language
    # (keep the same logical status but translate it)
    # Note: $lblStatus.Text is set by Update-RateDisplay via Load-ChartData,
    # so just refresh the current rates display
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

    $txtAiAnalysis.Text = L 'ai_analyzing' $script:SelectedCurrency

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
            $txtAiAnalysis.Text = L 'ai_waiting_data'
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
            if ($period -eq 'today') {
                $date = (Get-Date).ToString('yyyy-MM-dd')
                $url = "https://rate.bot.com.tw/xrt/quote/$date/$cur/spot"
                $botResponse = Invoke-BotWebRequest -Uri $url
                if ([string]::IsNullOrEmpty($botResponse)) {
                    $txtAiAnalysis.Text = L 'ai_no_spot_data'
                    return
                }
                $intradayRates = ConvertFrom-BotHtml -RawHtml $botResponse

                if ($null -eq $intradayRates -or $intradayRates.Count -eq 0) {
                    $txtAiAnalysis.Text = L 'ai_no_spot_data'
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
                    $txtAiAnalysis.Text = L 'ai_insufficient_hist' $dataPoints.Count
                    return
                }
                $dataForAnalysis = $dataPoints
            }

            # 2. Run local recommendation engine (no API key needed)
            $recommendation = Get-RateRecommendation -DataPoints $dataForAnalysis -Currency $cur -Period $period -Lang (Get-Language)

            if ($null -ne $recommendation -and $null -ne $recommendation.DetailedReport) {
                $txtAiAnalysis.Text = $recommendation.DetailedReport
            } else {
                $txtAiAnalysis.Text = L 'ai_local_complete'
            }

        } catch {
            $txtAiAnalysis.Text = L 'ai_analysis_failed' $($_.Exception.Message)
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
        'OpenAI (GPT-4o-mini)'       = @{ BaseUrl = 'https://api.openai.com/v1';                     Model = 'gpt-4o-mini';               NeedsKey = $true;  BypassProxy = $false }
        'OpenAI (GPT-4o)'            = @{ BaseUrl = 'https://api.openai.com/v1';                     Model = 'gpt-4o';                    NeedsKey = $true;  BypassProxy = $false }
        'Google Gemini (2.0 Flash)'  = @{ BaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai'; Model = 'gemini-2.0-flash'; NeedsKey = $true;  BypassProxy = $false }
        'Google Gemini (2.5 Pro)'    = @{ BaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai'; Model = 'gemini-2.5-pro';  NeedsKey = $true;  BypassProxy = $false }
        'Meta Llama 3.3 (Together)'  = @{ BaseUrl = 'https://api.together.xyz/v1';                   Model = 'meta-llama/Llama-3.3-70B-Instruct-Turbo'; NeedsKey = $true; BypassProxy = $false }
        'Ollama (Local)'             = @{ BaseUrl = 'http://localhost:11434/v1';                     Model = 'llama3.2:3b';               NeedsKey = $false; BypassProxy = $true  }
        'Custom Endpoint...'         = @{ BaseUrl = ''; Model = ''; NeedsKey = $true;  BypassProxy = $false }
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = L 'dialog_ai_model'
    $dlg.Size = New-Object System.Drawing.Size(480, 320)
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

    # --- Label: Model ---
    $lblModel = New-Object System.Windows.Forms.Label
    $lblModel.Text = L 'label_ai_model'
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
    $chkShowKey.Text = L 'btn_show'
    $chkShowKey.Location = New-Object System.Drawing.Point(400, 76)
    $chkShowKey.Size = New-Object System.Drawing.Size(50, 22)
    $chkShowKey.Add_CheckedChanged({
        $txtKey.UseSystemPasswordChar = -not $chkShowKey.Checked
    })
    $fieldPanel.Controls.Add($chkShowKey)

    # Checkbox: bypass proxy
    $chkBypassProxy = New-Object System.Windows.Forms.CheckBox
    $chkBypassProxy.Text = L 'btn_bypass_proxy'
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
    $btnOk.Text = L 'btn_ok'
    $btnOk.Location = New-Object System.Drawing.Point(210, 250)
    $btnOk.Size = New-Object System.Drawing.Size(85, 30)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = L 'btn_cancel'
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
            $lblHint.Text = L 'hint_enter_api_key'
        } else {
            $txtKey.Text = ''
            $lblKey.Enabled = $false
            $txtKey.Enabled = $false
            $chkShowKey.Enabled = $false
            $lblHint.Text = L 'hint_no_api_key'
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
            $(L 'err_url_required'),
            $(L 'dialog_title_missing'),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        $dlg.Dispose()
        return $null
    }

    # Validate: needs key but empty
    if ($preset.NeedsKey -and [string]::IsNullOrWhiteSpace($txtKey.Text.Trim())) {
        [System.Windows.Forms.MessageBox]::Show(
            $(L 'err_key_required'),
            $(L 'dialog_title_missing'),
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
            $installDlg.Text = L 'dialog_ollama_install'
            $installDlg.Size = New-Object System.Drawing.Size(460, 280)
            $installDlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
            $installDlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $installDlg.MaximizeBox = $false
            $installDlg.MinimizeBox = $false
            $installDlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

            $installLbl = New-Object System.Windows.Forms.Label
            $installLbl.Text = L 'ollama_not_installed'
            $installLbl.Location = New-Object System.Drawing.Point(20, 15)
            $installLbl.Size = New-Object System.Drawing.Size(400, 160)
            $installDlg.Controls.Add($installLbl)

            $btnCopy = New-Object System.Windows.Forms.Button
            $btnCopy.Text = L 'btn_copy_link'
            $btnCopy.Location = New-Object System.Drawing.Point(80, 190)
            $btnCopy.Size = New-Object System.Drawing.Size(130, 32)
            $btnCopy.Add_Click({
                [System.Windows.Forms.Clipboard]::SetText('https://ollama.com/download')
                [System.Windows.Forms.MessageBox]::Show(
                    $(L 'msg_link_copied'),
                    $(L 'dialog_title_copy'),
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            })
            $installDlg.Controls.Add($btnCopy)

            $btnClose = New-Object System.Windows.Forms.Button
            $btnClose.Text = L 'btn_close'
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
                $(L 'ollama_not_running'),
                $(L 'dialog_ollama_starting'),
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            $started = Start-OllamaService -WaitSeconds 3

            if (-not $started) {
                [System.Windows.Forms.MessageBox]::Show(
                    $(L 'ollama_start_failed'),
                    $(L 'dialog_title_start_fail'),
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
            $pullDlg.Text = L 'dialog_pull_model'
            $pullDlg.Size = New-Object System.Drawing.Size(440, 220)
            $pullDlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
            $pullDlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $pullDlg.MaximizeBox = $false
            $pullDlg.MinimizeBox = $false
            $pullDlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

            $pullLbl = New-Object System.Windows.Forms.Label
            $pullLbl.Text = L 'ollama_no_models'
            $pullLbl.Location = New-Object System.Drawing.Point(20, 15)
            $pullLbl.Size = New-Object System.Drawing.Size(390, 55)
            $pullDlg.Controls.Add($pullLbl)

            $txtPullModel = New-Object System.Windows.Forms.TextBox
            $txtPullModel.Text = 'llama3.2:3b'
            $txtPullModel.Location = New-Object System.Drawing.Point(20, 75)
            $txtPullModel.Size = New-Object System.Drawing.Size(380, 24)
            $pullDlg.Controls.Add($txtPullModel)

            $btnPull = New-Object System.Windows.Forms.Button
            $btnPull.Text = L 'btn_download_model'
            $btnPull.Location = New-Object System.Drawing.Point(60, 120)
            $btnPull.Size = New-Object System.Drawing.Size(130, 32)
            $btnPull.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $pullDlg.Controls.Add($btnPull)
            $pullDlg.AcceptButton = $btnPull

            $btnSkip = New-Object System.Windows.Forms.Button
            $btnSkip.Text = L 'btn_cancel'
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
            $progressDlg.Text = L 'dialog_downloading'
            $progressDlg.Size = New-Object System.Drawing.Size(420, 150)
            $progressDlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
            $progressDlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $progressDlg.MaximizeBox = $false
            $progressDlg.MinimizeBox = $false
            $progressDlg.ControlBox = $false
            $progressDlg.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)

            $progressLbl = New-Object System.Windows.Forms.Label
            $progressLbl.Text = L 'ollama_downloading' $modelToPull
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
            $pullPS.Runspace.SessionStateProxy.SetVariable('ollamaLang', (Get-Language))
            $modulePath = Join-Path $scriptDir 'Modules'
            [void]$pullPS.AddScript(@"
                Import-Module (Join-Path '$modulePath' 'i18n.psm1') -Force
                Set-Language `$ollamaLang
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
                        $exMsg = $_.Exception.Message
                        $script:PullResult = [PSCustomObject]@{
                            Success = $false
                            Message = $exMsg
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
                $errMsg = if ($null -ne $script:PullResult) { $script:PullResult.Message } else { L 'err_unknown' }
                [System.Windows.Forms.MessageBox]::Show(
                    $(L 'err_download_failed' $errMsg),
                    $(L 'dialog_download_failed'),
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

    $txtAiAnalysis.Text = L 'ai_calling_provider' $providerName

    try {
        # Gather data for statistics
        if ($period -eq 'today') {
            $date = (Get-Date).ToString('yyyy-MM-dd')
            $url = "https://rate.bot.com.tw/xrt/quote/$date/$cur/spot"
            $botResponse = Invoke-BotWebRequest -Uri $url
            if ([string]::IsNullOrEmpty($botResponse)) {
                $txtAiAnalysis.Text = L 'ai_no_spot_data_ai'
                return
            }
            $intradayRates = ConvertFrom-BotHtml -RawHtml $botResponse
            if ($null -eq $intradayRates -or $intradayRates.Count -eq 0) {
                $txtAiAnalysis.Text = L 'ai_no_spot_data_ai'
                return
            }
            $stats = Get-RateStatistics -DataPoints $intradayRates -Currency $cur -Period $period -Lang (Get-Language)
        } else {
            if ($null -ne $script:LastChartData -and $script:LastChartData.Count -ge 5) {
                $dataPoints = $script:LastChartData
            } else {
                $range = Get-PeriodDateRange -Period $period
                $missingDates = [ref]@()
                $dataPoints = @(Get-HistoricalRange -CurrencyCode $cur -StartDate $range.StartDate -EndDate $range.EndDate -MissingDates $missingDates)
            }
            if ($null -eq $dataPoints -or $dataPoints.Count -lt 5) {
                $txtAiAnalysis.Text = L 'ai_insufficient_hist_ai'
                return
            }
            $stats = Get-RateStatistics -DataPoints $dataPoints -Currency $cur -Period $period -Lang (Get-Language)
        }

        $txtAiAnalysis.Text = L 'ai_enhancing' $providerName

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
        $script:AiPS.Runspace.SessionStateProxy.SetVariable('aiLang', (Get-Language))

        $modulePath = Join-Path $scriptDir 'Modules'

        # Unified script: all params passed explicitly from dialog
        [void]$script:AiPS.AddScript(@"
            Import-Module (Join-Path '$modulePath' 'i18n.psm1') -Force
            Set-Language `$aiLang
            Import-Module (Join-Path '$modulePath' 'RateParser.psm1') -Force
            Import-Module (Join-Path '$modulePath' 'AIAnalyzer.psm1') -Force
            `$params = @{
                Statistics = `$stats
                ApiKey     = `$aiApiKey
                Model      = `$aiModel
                BaseUrl    = `$aiBaseUrl
                Lang       = `$aiLang
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
                $txtAiAnalysis.Text = L 'ai_timeout'
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
                        $txtAiAnalysis.Text = L 'ai_enhance_error_output' $pDisplay $errMsg
                    }
                    elseif ($null -ne $results -and $results.Count -gt 0) {
                        $aiText = $results[0]
                        $txtAiAnalysis.Text = L 'ai_success' $pDisplay $aiText
                    }
                    else {
                        $txtAiAnalysis.Text = L 'ai_enhance_no_result'
                    }
                } catch {
                    $txtAiAnalysis.Text = L 'ai_enhance_failed' $($_.Exception.Message)
                } finally {
                    $script:AiPS.Dispose()
                    $script:AiPS = $null
                    $script:AiAsync = $null
                }
            }
        })

        $script:AiPollTimer.Start()

    } catch {
        $txtAiAnalysis.Text = L 'ai_enhance_failed' $($_.Exception.Message)
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

    if ($period -eq 'today') {
        # Intraday: fetch synchronously (single request)
        $lblStatus.Text = L 'status_reading_today'
        $lblFetchProgress.Text = ""
        $statusProgressBar.Visible = $true
        $statusProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $date = (Get-Date).ToString('yyyy-MM-dd')
            $url = "https://rate.bot.com.tw/xrt/quote/$date/$cur/spot"
            $botResponse = Invoke-BotWebRequest -Uri $url
            if ([string]::IsNullOrEmpty($botResponse)) {
                Update-ChartDataIntraday -Chart $script:Chart -IntradayPoints @()
                $script:LastChartData = @()
                $lblStatus.Text = L 'status_fetch_failed'
            } else {
                $intradayRates = ConvertFrom-BotHtml -RawHtml $botResponse

                if ($null -ne $intradayRates -and $intradayRates.Count -gt 0) {
                    Update-ChartDataIntraday -Chart $script:Chart -IntradayPoints $intradayRates
                    $script:LastChartData = $intradayRates
                } else {
                    Update-ChartDataIntraday -Chart $script:Chart -IntradayPoints @()
                    $script:LastChartData = @()
                }
                $lblStatus.Text = L 'status_ready'
            }
        } catch {
            $lblStatus.Text = L 'status_fetch_failed'
            # Clear chart gracefully
            foreach ($series in $script:Chart.Series) {
                $series.Points.Clear()
            }
            if ($script:Chart.Titles.Count -gt 0) {
                $script:Chart.Titles[0].Text = L 'chart_no_data'
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
        $lblStatus.Text = L 'status_ready'
        $lblFetchProgress.Text = L 'status_cached' $cachedData.Count
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
    $lblStatus.Text = L 'status_reading_in_progress' $totalMissing
    [System.Windows.Forms.Application]::DoEvents()

    # Start loading spinner in chart title
    $script:SpinnerFrames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $script:SpinnerTimer = New-Object System.Windows.Forms.Timer
    $script:SpinnerTimer.Interval = 150
    $script:SpinnerTimer.Add_Tick({
        if ($script:IsClosing -or $script:Chart.Titles.Count -eq 0 -or -not $script:IsFetching) { return }
        $script:SpinnerTimer.Tag = (([int]$script:SpinnerTimer.Tag + 1) % $script:SpinnerFrames.Count)
        $frame = $script:SpinnerFrames[[int]$script:SpinnerTimer.Tag]
        $script:Chart.Titles[0].Text = L 'status_loading_chart' $frame
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
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                # Use HttpWebRequest with browser headers to bypass WAF (Challenge Validation)
                $__req = [System.Net.HttpWebRequest]::Create($url)
                $__req.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
                $__req.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
                $__req.Timeout = 20000
                $__req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
                $__req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
                $__req.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
                $__req.Headers.Add('Accept-Language', 'zh-TW,zh;q=0.9,en;q=0.8')
                $__req.Headers.Add('Sec-Ch-Ua', '"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"')
                $__req.Headers.Add('Sec-Ch-Ua-Mobile', '?0')
                $__req.Headers.Add('Sec-Ch-Ua-Platform', '"Windows"')
                $__req.Headers.Add('Sec-Fetch-Dest', 'document')
                $__req.Headers.Add('Sec-Fetch-Mode', 'navigate')
                $__req.Headers.Add('Sec-Fetch-Site', 'none')
                $__req.Headers.Add('Sec-Fetch-User', '?1')
                $__req.Headers.Add('Upgrade-Insecure-Requests', '1')

                $__resp = $__req.GetResponse()
                $__stream = $__resp.GetResponseStream()
                $__ms = New-Object System.IO.MemoryStream
                $__stream.CopyTo($__ms)
                $__bytes = $__ms.ToArray()
                $__ms.Close()
                $__stream.Close()
                $__resp.Close()

                $__encoding = [System.Text.Encoding]::UTF8
                $__contentType = $__resp.Headers['Content-Type']
                if ($__contentType -match 'charset=([\w-]+)') {
                    $__charset = $Matches[1].Trim().ToUpper()
                    if ($__charset -eq 'BIG5' -or $__charset -eq 'CP950') {
                        $__encoding = [System.Text.Encoding]::GetEncoding(950)
                    }
                }
                $__content = $__encoding.GetString($__bytes)

                if ($__content -match 'Challenge Validation') { return $null }

                $intradayRates = ConvertFrom-BotHtml -RawHtml $__content
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
                    $lblStatus.Text = L 'status_reading_historical' $completedCount $($jobs.Count)
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
        $script:Chart.Titles[0].Text = L 'chart_title'
    }

    # Hide progress bar
    $statusProgressBar.Visible = $false
    $statusProgressBar.Value = 0

    $script:IsFetching = $false
    $lblStatus.Text = L 'status_ready'
    $lblFetchProgress.Text = L 'status_total_records' $fetchResults.Count
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
        Clear-Cache

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
$form.Text = L 'form_title'
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
$lblCurrencyHeader.Text = L 'currency_header'
$lblCurrencyHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$lblCurrencyHeader.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10, [System.Drawing.FontStyle]::Bold)
$lblCurrencyHeader.Height = 30
$lblCurrencyHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCurrencyHeader.Padding = New-Object System.Windows.Forms.Padding(5)
$lblCurrencyHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)

# TextBox: Search
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Name = 'txtSearch'
$txtSearch.Text = L 'search_placeholder'
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
    $cmbCurrency.Items.Add("$($cur.Code) $(L "currency_$($cur.Code.ToLower())")") | Out-Null
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
$lblCurrencyTitle.Text = "USD $(L 'currency_usd')"
$lblCurrencyTitle.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 16, [System.Drawing.FontStyle]::Bold)
$lblCurrencyTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblCurrencyTitle.Location = New-Object System.Drawing.Point(10, 10)
$lblCurrencyTitle.AutoSize = $true
$lblCurrencyTitle.MaximumSize = New-Object System.Drawing.Size(480, 0)
$lblCurrencyTitle.AutoEllipsis = $true
$infoPanel.Controls.Add($lblCurrencyTitle)

# Rate Labels (2x2 grid)
$lblCashBuy = New-Object System.Windows.Forms.Label
$lblCashBuy.Text = "$(L 'label_cash_buy') $(L 'rate_dash')"
$lblCashBuy.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblCashBuy.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblCashBuy.Location = New-Object System.Drawing.Point(10, 45)
$lblCashBuy.AutoSize = $true
$infoPanel.Controls.Add($lblCashBuy)

$lblCashSell = New-Object System.Windows.Forms.Label
$lblCashSell.Text = "$(L 'label_cash_sell') $(L 'rate_dash')"
$lblCashSell.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblCashSell.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblCashSell.Location = New-Object System.Drawing.Point(250, 45)
$lblCashSell.AutoSize = $true
$infoPanel.Controls.Add($lblCashSell)

$lblSpotBuy = New-Object System.Windows.Forms.Label
$lblSpotBuy.Text = "$(L 'label_spot_buy') $(L 'rate_dash')"
$lblSpotBuy.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblSpotBuy.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblSpotBuy.Location = New-Object System.Drawing.Point(10, 75)
$lblSpotBuy.AutoSize = $true
$infoPanel.Controls.Add($lblSpotBuy)

$lblSpotSell = New-Object System.Windows.Forms.Label
$lblSpotSell.Text = "$(L 'label_spot_sell') $(L 'rate_dash')"
$lblSpotSell.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10)
$lblSpotSell.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$lblSpotSell.Location = New-Object System.Drawing.Point(250, 75)
$lblSpotSell.AutoSize = $true
$infoPanel.Controls.Add($lblSpotSell)

# Update Time Label
$lblUpdateTime = New-Object System.Windows.Forms.Label
$lblUpdateTime.Name = 'lblUpdateTime'
$lblUpdateTime.Text = "$(L 'label_update_time') $(L 'rate_dash')"
$lblUpdateTime.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$lblUpdateTime.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
$lblUpdateTime.Location = New-Object System.Drawing.Point(500, 10)
$lblUpdateTime.AutoSize = $true
$infoPanel.Controls.Add($lblUpdateTime)

# Language Toggle Buttons (中文 / EN)
$btnLangZh = New-Object System.Windows.Forms.Button
$btnLangZh.Name = 'btnLangZh'
$btnLangZh.Text = '中文'
$btnLangZh.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8, [System.Drawing.FontStyle]::Bold)
$btnLangZh.Size = New-Object System.Drawing.Size(45, 24)
$btnLangZh.Location = New-Object System.Drawing.Point(500, 100)
$btnLangZh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLangZh.Cursor = [System.Windows.Forms.Cursors]::Hand
# Active language styling (default: Chinese)
$btnLangZh.BackColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$btnLangZh.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 45)

$btnLangEn = New-Object System.Windows.Forms.Button
$btnLangEn.Name = 'btnLangEn'
$btnLangEn.Text = 'EN'
$btnLangEn.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8, [System.Drawing.FontStyle]::Bold)
$btnLangEn.Size = New-Object System.Drawing.Size(40, 24)
$btnLangEn.Location = New-Object System.Drawing.Point(547, 100)
$btnLangEn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLangEn.Cursor = [System.Windows.Forms.Cursors]::Hand
# Inactive language styling
$btnLangEn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 75)
$btnLangEn.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)

$btnLangZh.Add_Click({
    Set-Language 'zh'
    # Update button styling
    $btnLangZh.BackColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
    $btnLangZh.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 45)
    $btnLangEn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 75)
    $btnLangEn.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
    Update-AllLabels
})

$btnLangEn.Add_Click({
    Set-Language 'en'
    # Update button styling
    $btnLangEn.BackColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
    $btnLangEn.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 45)
    $btnLangZh.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 75)
    $btnLangZh.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)
    Update-AllLabels
})

$infoPanel.Controls.Add($btnLangZh)
$infoPanel.Controls.Add($btnLangEn)

# CheckBox: 置頂 (Always on Top)
$chkTopMost = New-Object System.Windows.Forms.CheckBox
$chkTopMost.Name = 'chkTopMost'
$chkTopMost.Text = L 'btn_pin'
$chkTopMost.Checked = $false
$chkTopMost.Location = New-Object System.Drawing.Point(650, 10)
$chkTopMost.AutoSize = $true
$infoPanel.Controls.Add($chkTopMost)

# Button: 重新整理 (Refresh)
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Name = 'btnRefresh'
$btnRefresh.Text = L 'btn_refresh'
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
$lblConverterHeader.Text = "💱 $(L 'converter_header')"
$lblConverterHeader.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 10, [System.Drawing.FontStyle]::Bold)
$lblConverterHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblConverterHeader.Location = New-Object System.Drawing.Point(10, 5)
$lblConverterHeader.AutoSize = $true
$converterPanel.Controls.Add($lblConverterHeader)

# --- Radio Buttons: Spot / Cash ---
$rbSpotRate = New-Object System.Windows.Forms.RadioButton
$rbSpotRate.Text = L 'rate_type_spot'
$rbSpotRate.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$rbSpotRate.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$rbSpotRate.Location = New-Object System.Drawing.Point(110, 6)
$rbSpotRate.AutoSize = $true
$rbSpotRate.Checked = $true
$converterPanel.Controls.Add($rbSpotRate)

$rbCashRate = New-Object System.Windows.Forms.RadioButton
$rbCashRate.Text = L 'rate_type_cash'
$rbCashRate.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 8)
$rbCashRate.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$rbCashRate.Location = New-Object System.Drawing.Point(170, 6)
$rbCashRate.AutoSize = $true
$converterPanel.Controls.Add($rbCashRate)

# --- Row 1: TWD input ↔ Foreign input ---
$lblTwdCurrency = New-Object System.Windows.Forms.Label
$lblTwdCurrency.Text = L 'label_twd_currency'
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
$lblForeignCurrency.Text = "USD $(L 'currency_usd')"
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
$lblConverterInfo.Text = L 'converter_info_na'
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
$periodIds = @('today', '1m', '3m', '6m', '1y', '3y', '5y', '10y')
$periodButtons = @()

foreach ($periodId in $periodIds) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Name = "btnPeriod_$periodId"
    $btn.Text = Get-PeriodDisplay $periodId
    $btn.Tag = $periodId
    $btn.AutoSize = $true
    $btn.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowOnly
    $btn.MinimumSize = New-Object System.Drawing.Size(60, 30)
    $btn.Height = 30
    $btn.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    # Default styling: first button (today) is active
    if ($periodId -eq 'today') {
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
$lblAiHeader.Text = "📊 $(L 'ai_panel_header')"
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
$btnAiEnhance.Text = "🤖 $(L 'btn_ai_enhance')"
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
$txtAiAnalysis.Text = L 'ai_initial'
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
$lblStatus.Text = L 'status_ready'
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
    if ($txtSearch.Text -eq (L 'search_placeholder')) {
        $txtSearch.Text = ""
        $txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
    }
})

$txtSearch.Add_Leave({
    if ([string]::IsNullOrWhiteSpace($txtSearch.Text)) {
        $txtSearch.Text = L 'search_placeholder'
        $txtSearch.ForeColor = [System.Drawing.Color]::FromArgb(100, 110, 135)
    }
})

# --- Search Box: Filter currency list ---
$txtSearch.Add_TextChanged({
    $ph = L 'search_placeholder'
    if ($txtSearch.Text -eq $ph) { return }
    $filter = $txtSearch.Text.Trim()
    if ($filter -eq $ph) { $filter = "" }

    $cmbCurrency.Items.Clear()
    foreach ($cur in $Currencies) {
        $display = "$($cur.Code) $(L "currency_$($cur.Code.ToLower())")"
        $curNameLocalized = L "currency_$($cur.Code.ToLower())"
        if ([string]::IsNullOrEmpty($filter) -or
            $display -like "*$filter*" -or
            $cur.Code -like "*$filter*" -or
            $curNameLocalized -like "*$filter*") {
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
    $lblStatus.Text = L 'status_refreshing'
    $lblFetchProgress.Text = ""
    [System.Windows.Forms.Application]::DoEvents()

    try {
        # Expire the DataFetcher in-memory cache
        Clear-Cache

        $script:CurrentRates = Get-CurrentRates
        Update-RateDisplay
        $lblStatus.Text = L 'status_ready'
    } catch {
        $lblStatus.Text = L 'status_refresh_failed' $($_.Exception.Message)
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
$lblStatus.Text = L 'status_fetching_rates'
$lblFetchProgress.Text = ""
[System.Windows.Forms.Application]::DoEvents()

try {
    $script:CurrentRates = @(Get-CurrentRates)
    Update-RateDisplay
    $lblStatus.Text = L 'status_ready'
} catch {
    $script:CurrentRates = @()
    $lblStatus.Text = L 'status_fetch_failed'
    $lblCurrencyTitle.Text = "$($script:SelectedCurrency) $(L "currency_$($script:SelectedCurrency.ToLower())")"
    $lblCashBuy.Text = "$(L 'label_cash_buy') $(L 'rate_dash')"
    $lblCashSell.Text = "$(L 'label_cash_sell') $(L 'rate_dash')"
    $lblSpotBuy.Text = "$(L 'label_spot_buy') $(L 'rate_dash')"
    $lblSpotSell.Text = "$(L 'label_spot_sell') $(L 'rate_dash')"
    $lblUpdateTime.Text = "$(L 'label_update_time') $(L 'rate_dash')"
}

# Load default chart data (today for USD)
Load-ChartData

# Start auto-refresh timer
$script:AutoRefreshTimer.Start()

# Trigger initial AI analysis
Start-AiAnalysis

# =============================================================================
# 11. Run Application
# =============================================================================
[System.Windows.Forms.Application]::Run($form)
