# =============================================================================
# AIAnalyzer.psm1
# OpenAI-Compatible API Integration for FX Rate Analysis
# =============================================================================

# Import i18n module for localization
Import-Module (Join-Path $PSScriptRoot 'i18n.psm1') -Force

# -----------------------------------------------------------------------------
# Module-Level Variables
# -----------------------------------------------------------------------------

# Warning prefix for error messages
$script:WarningPrefix = [char]0x26A0

# System prompt for FX analysis - dynamically selects based on current language
$script:SystemPrompt = $null  # Set lazily in Get-AIAnalysis based on current language

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
        [switch]$BypassProxy,

        [Parameter()]
        [ValidateSet('zh', 'en')]
        [string]$Lang
    )

    # Sync language for this module scope if explicitly provided
    if ($PSBoundParameters.ContainsKey('Lang')) {
        Set-Language $Lang
    }

    # --- User Prompt (serialize statistics as JSON) ---
    $userPrompt = $Statistics | ConvertTo-Json -Depth 5

    # --- Build request body ---
    # Select system prompt based on current language
    $currentLang = Get-Language
    if ($currentLang -eq 'en') {
        $systemContent = L 'ai_system_prompt_en'
    } else {
        $systemContent = L 'ai_system_prompt_zh'
    }
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
        if ($statusCode -and $statusCode -ge 400 -and $statusCode -lt 600) {
            return "$wp $(L 'ai_analysis_failed' $reasonPhrase)"
        }
        return "$wp $(L 'ai_analysis_failed' $ex.Message)"
    }
    catch {
        $wp = $script:WarningPrefix
        return "$wp $(L 'ai_analysis_failed' $_.Exception.Message)"
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
        return "$wp $(L 'ai_analysis_failed' 'API response format error')"
    }
    catch {
        $wp = $script:WarningPrefix
        return "$wp $(L 'ai_analysis_failed' $_.Exception.Message)"
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
