# RateParser.psm1 - Bank of Taiwan FX Rate Parsing Module
# Parses CSV and HTML data from rate.bot.com.tw into structured PowerShell objects

# Import i18n module for localized strings
$modDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modDir 'i18n.psm1') -Force

<#
.SYNOPSIS
    Returns the Chinese display name for a currency code.

.DESCRIPTION
    Looks up a 3-letter currency code (e.g. USD, JPY) in the Bank of Taiwan
    currency mapping and returns the corresponding Chinese name (e.g. 美金, 日圓).
    If the code is not found, returns an empty string.

.PARAMETER Code
    The 3-letter ISO currency code (e.g. USD, JPY, EUR).

.OUTPUTS
    System.String. The Chinese name for the currency, or empty string if not found.

.EXAMPLE
    Get-CurrencyName -Code USD
    # Returns: 美金

.EXAMPLE
    Get-CurrencyName -Code JPY
    # Returns: 日圓
#>
function Get-CurrencyName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code
    )
    $key = "currency_$($Code.ToLower())"
    $result = L $key
    # If L returns the key name (fallback), return empty string
    if ($result -eq $key) { return '' }
    return $result
}

<#
.SYNOPSIS
    Parses Bank of Taiwan daily FX rate CSV into structured objects.

.DESCRIPTION
    Converts raw CSV content from the Bank of Taiwan daily rate endpoint
    (https://rate.bot.com.tw/xrt/flcsv/0/day) into an array of PSCustomObject.
    Each object contains Currency, CashBuy, CashSell, SpotBuy, SpotSell, and DisplayName.

    The CSV from Bank of Taiwan has duplicate column names (Rate, Cash, Spot
    appear twice for Buying and Selling), so ConvertFrom-Csv cannot be used.
    Instead, this function manually splits rows and uses fixed column indices.

.PARAMETER RawCsv
    The raw CSV content as a string. The caller is responsible for decoding
    the response (which may be in Big5 or UTF-8 encoding).

.OUTPUTS
    PSCustomObject[]. Array of rate objects with properties:
    - Currency  : 3-letter currency code (e.g. USD)
    - CashBuy   : Cash buying rate [decimal]
    - CashSell  : Cash selling rate [decimal]
    - SpotBuy   : Spot buying rate [decimal]
    - SpotSell  : Spot selling rate [decimal]
    - DisplayName: Currency code + Chinese name (e.g. "USD 美金")

.EXAMPLE
    $rates = ConvertFrom-BotCsv -RawCsv (Get-Content -Raw .\rates.csv)
    $rates | Where-Object Currency -eq 'USD'

.NOTES
    Column indices (0-based) in the CSV:
    [0]  = Currency code
    [2]  = Cash Buying rate
    [3]  = Spot Buying rate
    [12] = Cash Selling rate
    [13] = Spot Selling rate
#>
function ConvertFrom-BotCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawCsv
    )

    $lines = $RawCsv -split "`n"
    if ($lines.Count -lt 2) {
        return @()
    }

    $results = @()

    # Skip header row (index 0), process data rows
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $fields = $line -split ','
        if ($fields.Count -lt 14) {
            continue
        }

        $code = $fields[0].Trim()

        # Skip if no valid currency code
        if ([string]::IsNullOrWhiteSpace($code)) {
            continue
        }

        # Column indices: [2]=Cash Buy, [3]=Spot Buy, [12]=Cash Sell, [13]=Spot Sell
        $cashBuyStr  = $fields[2].Trim()
        $spotBuyStr  = $fields[3].Trim()
        $cashSellStr = $fields[12].Trim()
        $spotSellStr = $fields[13].Trim()

        # Parse decimals; treat empty/invalid as 0
        $cashBuy  = if ([decimal]::TryParse($cashBuyStr,  [ref]0)) { [decimal]$cashBuyStr  } else { 0 }
        $spotBuy  = if ([decimal]::TryParse($spotBuyStr,  [ref]0)) { [decimal]$spotBuyStr  } else { 0 }
        $cashSell = if ([decimal]::TryParse($cashSellStr, [ref]0)) { [decimal]$cashSellStr } else { 0 }
        $spotSell = if ([decimal]::TryParse($spotSellStr, [ref]0)) { [decimal]$spotSellStr } else { 0 }

        $chineseName = Get-CurrencyName -Code $code
        $displayName = if ($chineseName) { "$code $chineseName" } else { $code }

        $results += [PSCustomObject]@{
            Currency    = $code
            CashBuy     = $cashBuy
            CashSell    = $cashSell
            SpotBuy     = $spotBuy
            SpotSell    = $spotSell
            DisplayName = $displayName
        }
    }

    return $results
}

<#
.SYNOPSIS
    Parses Bank of Taiwan intraday FX rate HTML into structured objects.

.DESCRIPTION
    Converts raw HTML content from the Bank of Taiwan intraday rate page
    (https://rate.bot.com.tw/xrt/quote/YYYY-MM-DD/CODE/spot) into an array
    of PSCustomObject. Each object contains Time, CashBuy, CashSell, SpotBuy,
    and SpotSell.

    Uses regex to extract table rows since the HTML structure may vary.
    Returns an empty array if no rate data is found or if the page shows
    "查無資料" (no data) or "系統維護" (system maintenance).

.PARAMETER RawHtml
    The raw HTML content as a string.

.OUTPUTS
    PSCustomObject[]. Array of intraday rate objects with properties:
    - Time     : Time string in HH:mm:ss format
    - CashBuy  : Cash buying rate [decimal]
    - CashSell : Cash selling rate [decimal]
    - SpotBuy  : Spot buying rate [decimal]
    - SpotSell : Spot selling rate [decimal]

.EXAMPLE
    $rates = ConvertFrom-BotHtml -RawHtml (Invoke-WebRequest -Uri $url).Content
    $rates | Format-Table
#>
function ConvertFrom-BotHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawHtml
    )

    # Check for no-data or maintenance pages
    if ($RawHtml -match '查無資料' -or $RawHtml -match '系統維護') {
        return @()
    }

    # Regex pattern to match table rows with 6 td cells:
    # Time, Currency Name, Cash Buy, Cash Sell, Spot Buy, Spot Sell
    $rowPattern = '<tr[^>]*>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?<td[^>]*>(.*?)</td>.*?</tr>'

    $matches = [regex]::Matches($RawHtml, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($matches.Count -eq 0) {
        return @()
    }

    $results = @()
    $isFirstRow = $true

    foreach ($match in $matches) {
        # Skip header row (first match)
        if ($isFirstRow) {
            $isFirstRow = $false
            continue
        }

        $rawTime     = $match.Groups[1].Value.Trim()
        # Group 2 is currency name - not needed for output
        $cashBuyStr  = $match.Groups[3].Value.Trim()
        $cashSellStr = $match.Groups[4].Value.Trim()
        $spotBuyStr  = $match.Groups[5].Value.Trim()
        $spotSellStr = $match.Groups[6].Value.Trim()

        # Strip any HTML tags from extracted values
        $rawTime     = [regex]::Replace($rawTime,     '<[^>]+>', '')
        $cashBuyStr  = [regex]::Replace($cashBuyStr,  '<[^>]+>', '')
        $cashSellStr = [regex]::Replace($cashSellStr, '<[^>]+>', '')
        $spotBuyStr  = [regex]::Replace($spotBuyStr,  '<[^>]+>', '')
        $spotSellStr = [regex]::Replace($spotSellStr, '<[^>]+>', '')

        # Extract HH:mm:ss from "YYYY/MM/DD HH:mm:ss" format
        $time = ''
        if ($rawTime -match '(\d{2}:\d{2}:\d{2})') {
            $time = $Matches[1]
        }
        elseif ($rawTime -match '(\d{1,2}:\d{2}:\d{2})') {
            $time = $Matches[1]
        }

        # Parse decimal values; treat dash or empty as 0
        $cashBuy  = if ([decimal]::TryParse($cashBuyStr,  [ref]0)) { [decimal]$cashBuyStr  } else { 0 }
        $cashSell = if ([decimal]::TryParse($cashSellStr, [ref]0)) { [decimal]$cashSellStr } else { 0 }
        $spotBuy  = if ([decimal]::TryParse($spotBuyStr,  [ref]0)) { [decimal]$spotBuyStr  } else { 0 }
        $spotSell = if ([decimal]::TryParse($spotSellStr, [ref]0)) { [decimal]$spotSellStr } else { 0 }

        $results += [PSCustomObject]@{
            Time     = $time
            CashBuy  = $cashBuy
            CashSell = $cashSell
            SpotBuy  = $spotBuy
            SpotSell = $spotSell
        }
    }

    return $results
}

<#
.SYNOPSIS
    Returns the closing (last) intraday FX rate for a given date.

.DESCRIPTION
    Takes an array of intraday rate objects (from ConvertFrom-BotHtml) and
    a date string, and returns the LAST element as the closing rate for that day.
    Returns $null if the input array is empty.

.PARAMETER IntradayRates
    Array of PSCustomObject from ConvertFrom-BotHtml output.

.PARAMETER Date
    The date string in YYYY-MM-DD format.

.OUTPUTS
    PSCustomObject with properties:
    - Date     : Date string in YYYY-MM-DD format
    - CashBuy  : Cash buying rate [decimal]
    - CashSell : Cash selling rate [decimal]
    - SpotBuy  : Spot buying rate [decimal]
    - SpotSell : Spot selling rate [decimal]

    Returns $null if IntradayRates is empty.

.EXAMPLE
    $closing = Get-ClosingRate -IntradayRates $rates -Date '2025-01-15'
#>
function Get-ClosingRate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$IntradayRates,

        [Parameter(Mandatory = $true)]
        [string]$Date
    )

    if ($null -eq $IntradayRates -or $IntradayRates.Count -eq 0) {
        return $null
    }

    $last = $IntradayRates[-1]

    return [PSCustomObject]@{
        Date     = $Date
        CashBuy  = $last.CashBuy
        CashSell = $last.CashSell
        SpotBuy  = $last.SpotBuy
        SpotSell = $last.SpotSell
    }
}

# Export all public functions
Export-ModuleMember -Function ConvertFrom-BotCsv, ConvertFrom-BotHtml, Get-ClosingRate, Get-CurrencyName
