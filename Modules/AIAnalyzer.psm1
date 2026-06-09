# =============================================================================
# AIAnalyzer.psm1
# OpenAI-Compatible API Integration for FX Rate Analysis
# =============================================================================

# -----------------------------------------------------------------------------
# Module-Level Variables
# -----------------------------------------------------------------------------

# Warning prefix for error messages
$script:WarningPrefix = [char]0x26A0

# System prompt for FX analysis (here-string at module scope, column 1)
$script:SystemPrompt = @'
你是一位專業的外匯匯率分析師。請根據提供的統計指標進行分析，並給出簡潔的買入/賣出/觀望建議（3-5 句話），使用繁體中文回覆。

你的分析必須：
1. 引用具體數字（目前匯率、SMA 值、RSI、百分位數）來支持你的判斷
2. 提及目前匯率是否接近近期高點或低點
3. 結合 RSI 指標判斷超買或超賣狀態
4. 結合 SMA 均線判斷趨勢方向
5. 在建議末尾加上免責聲明：「以上分析僅供參考，不構成任何投資建議。投資有風險，請自行審慎評估。」
'@

# =============================================================================
# Function: Get-AIAnalysis
# =============================================================================

<#
.SYNOPSIS
    Generates FX rate analysis and buy/sell recommendation via OpenAI-compatible API.

.DESCRIPTION
    Takes a statistics object (output from Get-RateStatistics) and sends it
    to an OpenAI-compatible Chat Completions API endpoint with a system
    prompt that instructs the AI to act as a professional FX rate analyst,
    and returns the analysis text string in Traditional Chinese.

    Requires ApiKey, Model, and BaseUrl to be provided explicitly.

.PARAMETER Statistics
    A PSCustomObject containing rate statistics, typically the output from
    Get-RateStatistics.  The object is serialized to JSON and sent to the
    API as the user message.

.PARAMETER ApiKey
    API key (Bearer token).  Required.

.PARAMETER Model
    The model to use for the chat completion.  Required.

.PARAMETER BaseUrl
    The API base URL (e.g. "https://api.openai.com/v1").  Required.

.PARAMETER BypassProxy
    Switch to bypass system proxy.  Use for internal endpoints.

.OUTPUTS
    [string] The AI-generated analysis text in Traditional Chinese.  On error,
    returns a friendly Chinese error message prefixed with a warning symbol.

.EXAMPLE
    $stats = Get-RateStatistics -Currency 'USD' -DataPoints $rates -Period '3個月'
    $analysis = Get-AIAnalysis -Statistics $stats -ApiKey 'sk-...' -Model 'gpt-4o-mini' -BaseUrl 'https://api.openai.com/v1'
#>
function Get-AIAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Statistics,

        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter()]
        [switch]$BypassProxy
    )

    # --- User Prompt (serialize statistics as JSON) ---
    $userPrompt = $Statistics | ConvertTo-Json -Depth 5

    # --- Build request body ---
    $systemContent = $script:SystemPrompt
    $body = @{
        model       = $Model
        messages    = @(
            @{ role = 'system'; content = $systemContent },
            @{ role = 'user';   content = $userPrompt }
        )
        max_tokens  = 800
        temperature = 0.3
    } | ConvertTo-Json -Depth 5 -Compress

    # --- Make API call via System.Net.WebClient ---
    $url = "$BaseUrl/chat/completions"

    try {
        $wc = New-Object System.Net.WebClient
        # Internal URL — bypass proxy for corporate gateway; external URLs use system proxy
        if ($BypassProxy) {
            $wc.Proxy = [System.Net.WebProxy]::new($null)
        }
        $wc.Encoding = [System.Text.Encoding]::UTF8

        $wc.Headers.Add('Authorization', "Bearer $ApiKey")
        $wc.Headers.Add('Content-Type', 'application/json')

        $responseText = $wc.UploadString($url, 'POST', $body)
    }
    catch [System.Net.WebException] {
        $ex = $_.Exception
        $statusCode = $null
        $reasonPhrase = ''

        if ($null -ne $ex.Response) {
            $statusCode = [int]$ex.Response.StatusCode
            $reasonPhrase = $ex.Response.StatusDescription

            # Try to read error body for more detail
            try {
                $stream = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $errorBody = $reader.ReadToEnd()
                $reader.Close()

                $errorObj = $errorBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($null -ne $errorObj -and $null -ne $errorObj.error -and $null -ne $errorObj.error.message) {
                    $reasonPhrase = $errorObj.error.message
                }
            }
            catch {
                # Could not read error body -- use status description
            }
        }

        $wp = $script:WarningPrefix
        switch ($statusCode) {
            401 { return "$wp AI 分析暫時無法使用：API 金鑰無效或已過期，請檢查設定。" }
            429 { return "$wp AI 分析暫時無法使用：API 請求頻率過高，請稍後再試。" }
            500 { return "$wp AI 分析暫時無法使用：AI 伺服器發生錯誤，請稍後再試。" }
            503 { return "$wp AI 分析暫時無法使用：AI 服務暫時無法使用，請稍後再試。" }
            default {
                if ($statusCode) {
                    return "$wp AI 分析暫時無法使用：HTTP $statusCode - $reasonPhrase"
                }
                return "$wp AI 分析暫時無法使用：網路連線失敗 - $($ex.Message)"
            }
        }
    }
    catch {
        $wp = $script:WarningPrefix
        return "$wp AI 分析暫時無法使用：$($_.Exception.Message)"
    }

    # --- Parse response ---
    try {
        $responseObj = $responseText | ConvertFrom-Json

        if ($null -ne $responseObj.choices -and $responseObj.choices.Count -gt 0) {
            $content = $responseObj.choices[0].message.content
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                return $content.Trim()
            }
        }

        $wp = $script:WarningPrefix
        return "$wp AI 分析暫時無法使用：API 回應格式異常，無法取得分析結果。"
    }
    catch {
        $wp = $script:WarningPrefix
        return "$wp AI 分析暫時無法使用：無法解析 API 回應 - $($_.Exception.Message)"
    }
}

# =============================================================================
# Function: Test-OpenAiApiKey
# =============================================================================

<#
.SYNOPSIS
    Validates an API key by making a minimal API call.

.DESCRIPTION
    Calls the /models endpoint with the provided Bearer token.
    Returns $true if the response status is 200 (OK), indicating the key is
    valid.  Returns $false for any error (401 unauthorized, network failure,
    etc.).  This function does not throw exceptions.

.PARAMETER ApiKey
    The API key to validate.  Required.

.PARAMETER BaseUrl
    The API base URL.  Required.

.OUTPUTS
    [bool] $true if the key is valid (HTTP 200), $false otherwise.

.EXAMPLE
    if (Test-OpenAiApiKey -ApiKey 'sk-...' -BaseUrl 'https://api.openai.com/v1') { "Valid" } else { "Invalid" }
#>
function Test-OpenAiApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$BaseUrl
    )

    $url = "$BaseUrl/models"

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8

        $wc.Headers.Add('Authorization', "Bearer $ApiKey")

        $null = $wc.DownloadString($url)
        return $true
    }
    catch {
        return $false
    }
}

# =============================================================================
# Function: Get-OpenAiModels
# =============================================================================

<#
.SYNOPSIS
    Lists available models for the given API key.

.DESCRIPTION
    Calls the /models endpoint with the provided Bearer token and returns
    an array of model ID strings.  Useful for debugging which models are
    accessible.  Returns an empty array on error.

.PARAMETER ApiKey
    The API key.  Required.

.PARAMETER BaseUrl
    The API base URL.  Required.

.OUTPUTS
    [string[]] Array of model ID strings, or empty array on failure.

.EXAMPLE
    $models = Get-OpenAiModels -ApiKey 'sk-...' -BaseUrl 'https://api.openai.com/v1'
    $models | Sort-Object
#>
function Get-OpenAiModels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$BaseUrl
    )

    $url = "$BaseUrl/models"

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8

        $wc.Headers.Add('Authorization', "Bearer $ApiKey")

        $responseText = $wc.DownloadString($url)
        $responseObj = $responseText | ConvertFrom-Json

        if ($null -ne $responseObj.data -and $responseObj.data.Count -gt 0) {
            $modelIds = $responseObj.data | ForEach-Object { $_.id }
            return ,@($modelIds)
        }

        return ,@()
    }
    catch {
        return ,@()
    }
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Get-AIAnalysis',
    'Test-OpenAiApiKey',
    'Get-OpenAiModels'
)
