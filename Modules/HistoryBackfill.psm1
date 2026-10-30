# =============================================================================
# HistoryBackfill.psm1
# Historical FX backfill from alternate sources (TCB / Yahoo Finance).
#
# Purpose
# -------
# The primary source (Bank of Taiwan, rate.bot.com.tw) is frequently blocked by
# its WAF ("Challenge Validation" page), so the tool can no longer fetch old
# daily rates.  This module fills the missing dates of the requested range from
# two decline-proof sources, in one request per currency:
#
#   1. TCB (合作金庫銀行, www.tcb-bank.com.tw) - daily ask/bid with cash and
#      spot prices.  Preferred for the 14 currencies it lists:
#        USD HKD GBP AUD SGD CHF CAD JPY SEK EUR NZD THB ZAR CNY
#      Server history: >= 5 years (CNY is capped at ~1 year by the server).
#      Each date returns two rows (buy / sell); CashExchange = 現金 rate,
#      PromptExchange = 即期 rate.  Buy rates are always lower than sell rates,
#      so the buy/sell role is derived by numeric order (encoding-proof).
#
#   2. Yahoo Finance v8 chart API (query1.finance.yahoo.com) - daily close for
#      the currencies 台銀 quotes as per-unit (IDR, KRW, MYR) that TCB lacks.
#      Yahoo provides a single close price per day only, so all four fields
#      (CashBuy/CashSell/SpotBuy/SpotSell) are filled with that close so the
#      curve still renders over the whole range.
#
# Currencies with NO alternate source available (VND, PHP) are left untouched
# and will only ever be filled when 台銀 becomes reachable again.
#
# Cache behaviour
# ---------------
# Results are written into the SAME cache used by DataFetcher
# (Cache\<CUR>\<yyyy-MM-dd>.json) via DataFetcher's Save-Cache.  Existing cache
# entries are NEVER overwritten, so 台銀 data (when available) always wins.
#
# DEPENDENCY: DataFetcher.psm1 must be imported in the session before calling
# any function of this module (uses Initialize-Cache root, Get-HistoricalRange,
# Get-CachedDate, Save-Cache).
#
# This file intentionally contains only ASCII characters so that it parses
# correctly no matter how PowerShell 5.1 reads the file encoding.
# =============================================================================

# -----------------------------------------------------------------------------
# Module-Level Configuration
# -----------------------------------------------------------------------------

# Currencies served by TCB history API (preferred source).
$script:TcbCurrencies = @(
    'USD', 'HKD', 'GBP', 'AUD', 'SGD', 'CHF', 'CAD', 'JPY',
    'SEK', 'EUR', 'NZD', 'THB', 'ZAR', 'CNY'
)

# Currencies NOT on TCB but available on Yahoo (per-unit scale, matches 台銀).
$script:YahooBackfillCurrencies = @('IDR', 'KRW', 'MYR')

$script:TcbHistoryPage = 'https://www.tcb-bank.com.tw/personal-banking/deposit-exchange/exchange-rate/historical-rate'
$script:TcbHistoryApi  = 'https://www.tcb-bank.com.tw/api/client/ForeignExchange/GetHistoryForeignExchange'

$script:BackfillUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'

# =============================================================================
# Function: Get-AltSourceForCurrency  (PRIVATE helpers below use it too)
# =============================================================================

<#
.SYNOPSIS
    Returns the alternate history source for a currency code.
.DESCRIPTION
    'TCB'    -> use 合庫 history API (14 currencies, preferred, has cash+spot).
    'Yahoo'  -> use Yahoo Finance close (IDR/KRW/MYR only).
    $null    -> no alternate source available (VND, PHP).
#>
function Get-AltSourceForCurrency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode
    )

    if ($script:TcbCurrencies -contains $CurrencyCode) { return 'TCB' }
    if ($script:YahooBackfillCurrencies -contains $CurrencyCode) { return 'Yahoo' }
    return $null
}

# =============================================================================
# Function: Invoke-BackfillWebRequest  (PRIVATE)
# =============================================================================

<#
.SYNOPSIS
    Unified HTTPS request used by every backfill HTTP call.
.DESCRIPTION
    Uses HttpWebRequest with the system proxy + default credentials + TLS 1.2
    and a browser User-Agent (same transport the rest of the tool uses).
    Supports GET and urlencoded POST.  Pass a CookieContainer to keep the
    anti-forgery token/cookies between the GET (page) and POST (API) calls.
    Returns $null on any transport failure.
#>
function Invoke-BackfillWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [ValidateSet('GET', 'POST')]
        [string]$Method = 'GET',

        [string]$Body = $null,

        [string]$Referer = $null,

        [System.Net.CookieContainer]$Cookies = $null,

        [switch]$DocumentMode
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.Method = $Method
        $req.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $req.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        $req.Timeout = 30000
        $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $req.UserAgent = $script:BackfillUserAgent
        $req.Headers.Add('Accept-Language', 'zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7')

        if ($DocumentMode) {
            # Browser-document style headers (matches DataFetcher's WAF bypass).
            $req.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8'
            $req.Headers.Add('Sec-Fetch-Dest', 'document')
            $req.Headers.Add('Sec-Fetch-Mode', 'navigate')
            $req.Headers.Add('Sec-Fetch-Site', 'none')
            $req.Headers.Add('Sec-Fetch-User', '?1')
            $req.Headers.Add('Upgrade-Insecure-Requests', '1')
        }
        else {
            # JSON/XHR style headers for TCB API and Yahoo chart API.
            $req.Accept = 'application/json, text/plain, */*'
            $req.Headers.Add('Sec-Fetch-Dest', 'empty')
            $req.Headers.Add('Sec-Fetch-Mode', 'cors')
            $req.Headers.Add('Sec-Fetch-Site', 'same-origin')
        }

        if ($null -ne $Cookies) {
            $req.CookieContainer = $Cookies
        }
        if (-not [string]::IsNullOrEmpty($Referer)) {
            $req.Referer = $Referer
        }

        if ($Method -eq 'POST' -and -not [string]::IsNullOrEmpty($Body)) {
            $req.ContentType = 'application/x-www-form-urlencoded'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentLength = $bytes.Length
            $reqStream = $req.GetRequestStream()
            $reqStream.Write($bytes, 0, $bytes.Length)
            $reqStream.Close()
        }

        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $ms = New-Object System.IO.MemoryStream
        $stream.CopyTo($ms)
        $raw = $ms.ToArray()
        $ms.Close()
        $stream.Close()
        $resp.Close()
        return $raw
    }
    catch {
        Write-Verbose "HistoryBackfill: request failed for $Uri : $($_.Exception.Message)"
        return $null
    }
}

# =============================================================================
# Function: Test-BankOfTaiwanAccess
# =============================================================================

<#
.SYNOPSIS
    Canary check: is the Bank of Taiwan historical page currently reachable?
.DESCRIPTION
    Fetches one 台銀 quote URL for the given currency/date.  Returns $false when
    the request fails or returns the WAF "Challenge Validation" page; $true when
    a real page is returned.  Used by the caller to skip the doomed per-date
    台銀 batch right away and go straight to alternate-source backfill.
.PARAMETER CurrencyCode
    Currency code (e.g. "USD").
.PARAMETER Date
    Date string in YYYY-MM-DD format (any date is fine for the probe).
.OUTPUTS
    [bool] $true when Bank of Taiwan is fetchable, otherwise $false.
#>
function Test-BankOfTaiwanAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [string]$Date
    )

    # Use the CSV endpoint with browser-document headers and treat ANY HTML reply
    # (the WAF serves an HTML "Challenge Validation" page) as blocked.  A real
    # response is CSV text without a DOCTYPE, so this cannot false-positive.
    $url = 'https://rate.bot.com.tw/xrt/flcsv/0/day'
    $raw = Invoke-BackfillWebRequest -Uri $url -Method GET -DocumentMode
    if ($null -eq $raw -or $raw.Length -lt 20) { return $false }

    $text = [System.Text.Encoding]::UTF8.GetString($raw)
    if ($text -match 'Challenge Validation') { return $false }
    if ($text -match '系統維護') { return $false }
    if ($text -match '<!DOCTYPE') { return $false }

    return $true
}

# =============================================================================
# Function: Get-TcbHistoryRates
# =============================================================================

<#
.SYNOPSIS
    Fetches a full date range of daily rates from TCB (合庫) in one request.
.DESCRIPTION
    GETs the historical-rate page to obtain a fresh __RequestVerificationToken
    and cookies, then POSTs a "custom" range request to the internal API.  The
    server ignores the UI 365-day cap and returns every trading day between
    StartDate and EndDate.  Each date yields a buy and a sell row; cash/spot
    fields come from CashExchange/PromptExchange.  The lower PromptExchange of
    the date pair is treated as the buy rate (bank buy < sell, by definition),
    which sidesteps the Big5-encoded Type field entirely.
.PARAMETER CurrencyCode
    One of the 14 TCB-listed codes.
.PARAMETER StartDate
    Beginning of the range (inclusive).
.PARAMETER EndDate
    End of the range (inclusive).
.OUTPUTS
    PSCustomObject[] with Date (yyyy-MM-dd), CashBuy, CashSell, SpotBuy, SpotSell.
    Empty array on failure or no data.
#>
function Get-TcbHistoryRates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate
    )

    $cookies = New-Object System.Net.CookieContainer

    # 1. GET the page to obtain the anti-forgery token + cookies.
    $pageRaw = Invoke-BackfillWebRequest -Uri $script:TcbHistoryPage -Method GET -Cookies $cookies
    if ($null -eq $pageRaw -or $pageRaw.Length -eq 0) {
        Write-Verbose "HistoryBackfill: cannot load TCB history page for $CurrencyCode"
        return @()
    }

    $pageText = [System.Text.Encoding]::UTF8.GetString($pageRaw)
    $token = $null
    $inputMatch = [regex]::Match($pageText, '(?is)<input[^>]*name=["'']__RequestVerificationToken["''][^>]*>')
    if (-not $inputMatch.Success) {
        # Attribute order may be reversed (value before name).
        $inputMatch = [regex]::Match($pageText, '(?is)<input[^>]*value=["''][^"'']*["''][^>]*name=["'']__RequestVerificationToken["''][^>]*>')
    }
    if ($inputMatch.Success) {
        $valueMatch = [regex]::Match($inputMatch.Value, 'value=["'']([^"'']*)["'']')
        if ($valueMatch.Success) { $token = $valueMatch.Groups[1].Value }
    }

    if ([string]::IsNullOrEmpty($token)) {
        Write-Verbose "HistoryBackfill: no __RequestVerificationToken on TCB page for $CurrencyCode"
        return @()
    }

    # 2. POST the custom range history request.
    $body = "__RequestVerificationToken=$([Uri]::EscapeDataString($token))" +
            "&currency=$CurrencyCode" +
            '&dateoptions=custom' +
            "&startdate=$($StartDate.ToString('yyyy/MM/dd'))" +
            "&enddate=$($EndDate.ToString('yyyy/MM/dd'))"

    $apiRaw = Invoke-BackfillWebRequest -Uri $script:TcbHistoryApi -Method POST -Body $body -Referer $script:TcbHistoryPage -Cookies $cookies
    if ($null -eq $apiRaw -or $apiRaw.Length -eq 0) {
        Write-Verbose "HistoryBackfill: TCB API returned nothing for $CurrencyCode"
        return @()
    }

    $apiText = [System.Text.Encoding]::UTF8.GetString($apiRaw)
    $json = $null
    try {
        $json = $apiText | ConvertFrom-Json
    }
    catch {
        Write-Verbose "HistoryBackfill: TCB API returned non-JSON for $CurrencyCode"
        return @()
    }

    $rows = @($json.result)
    if ($rows.Count -eq 0) {
        Write-Verbose "HistoryBackfill: TCB API returned no rows for $CurrencyCode"
        return @()
    }

    # 3. Group by date; within each date pick the lower PromptExchange as buy.
    $byDate = @($rows | Group-Object -Property CardDate)
    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($g in $byDate) {
        if ($null -eq $g -or $null -eq $g.Group) { continue }
        $pair = @($g.Group)
        if ($pair.Count -lt 2) { continue }

        $ordered = @($pair | Sort-Object { [double]$_.PromptExchange })
        $buyRow  = $ordered[0]
        $sellRow = $ordered[$ordered.Count - 1]

        $dateStr = "$($g.Name)"
        # CardDate arrives as "2021-01-04"; normalise in case of time suffix.
        if ($dateStr -match '^(\d{4})-(\d{2})-(\d{2})') {
            $dateStr = '{0}-{1}-{2}' -f $Matches[1], $Matches[2], $Matches[3]
        }

        $result.Add([PSCustomObject]@{
            Date     = $dateStr
            CashBuy  = [double]$buyRow.CashExchange
            CashSell = [double]$sellRow.CashExchange
            SpotBuy  = [double]$buyRow.PromptExchange
            SpotSell = [double]$sellRow.PromptExchange
        })
    }

    return @($result | Sort-Object -Property Date)
}

# =============================================================================
# Function: Get-YahooHistoryRates
# =============================================================================

<#
.SYNOPSIS
    Fetches daily closes for one currency pair against TWD from Yahoo Finance.
.DESCRIPTION
    Calls the v8 chart API for {Currency}TWD=X with interval=1d over the whole
    requested range in a single request.  Yahoo returns only ONE close price
    per trading day; to keep the 4-series chart rendering we fill all four
    fields (CashBuy/CashSell/SpotBuy/SpotSell) with that close value.  The rate
    scale is per-unit, which matches the 台銀 per-unit convention for the three
    currencies that use this source (IDR, KRW, MYR).
.PARAMETER CurrencyCode
    One of the Yahoo backfill codes (IDR, KRW, MYR).
.PARAMETER StartDate
    Beginning of the range (inclusive).
.PARAMETER EndDate
    End of the range (inclusive).
.OUTPUTS
    PSCustomObject[] with Date (yyyy-MM-dd), CashBuy, CashSell, SpotBuy, SpotSell.
    Empty array on failure or no data.
#>
function Get-YahooHistoryRates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate
    )

    # period2 is exclusive; add one day so the EndDate itself is included.
    $p1 = [DateTimeOffset]::new([datetime]::SpecifyKind($StartDate.Date, [DateTimeKind]::Utc)).ToUnixTimeSeconds()
    $p2 = [DateTimeOffset]::new([datetime]::SpecifyKind($EndDate.Date.AddDays(1), [DateTimeKind]::Utc)).ToUnixTimeSeconds()

    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${CurrencyCode}TWD=X?period1=$p1&period2=$p2&interval=1d&events=history"

    $raw = Invoke-BackfillWebRequest -Uri $url -Method GET
    if ($null -eq $raw -or $raw.Length -eq 0) {
        Write-Verbose "HistoryBackfill: Yahoo returned nothing for $CurrencyCode"
        return @()
    }

    $text = [System.Text.Encoding]::UTF8.GetString($raw)
    $json = $null
    try {
        $json = $text | ConvertFrom-Json
    }
    catch {
        Write-Verbose "HistoryBackfill: Yahoo returned non-JSON for $CurrencyCode"
        return @()
    }

    # Valid payload has "result": [ ... ]; a missing symbol yields "result": null.
    if ($null -eq $json.chart -or $null -eq $json.chart.result -or $json.chart.result.Count -eq 0) {
        Write-Verbose "HistoryBackfill: Yahoo has no symbol $CurrencyCode TWD=X"
        return @()
    }

    $chart = $json.chart.result[0]
    $timestamps = @($chart.timestamp)
    $closes = @($chart.indicators.quote[0].close)

    $result = [System.Collections.Generic.List[object]]::new()
    $count = [Math]::Min($timestamps.Count, $closes.Count)

    for ($i = 0; $i -lt $count; $i++) {
        $close = $closes[$i]
        if ($null -eq $close) { continue }

        $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$timestamps[$i]).UtcDateTime
        $dateStr = $dt.ToString('yyyy-MM-dd')
        $closeVal = [double]$close

        $result.Add([PSCustomObject]@{
            Date     = $dateStr
            CashBuy  = $closeVal
            CashSell = $closeVal
            SpotBuy  = $closeVal
            SpotSell = $closeVal
        })
    }

    return @($result | Sort-Object -Property Date)
}

# =============================================================================
# Function: Backfill-HistoricalRates
# =============================================================================

<#
.SYNOPSIS
    Backfills the missing dates of a range for one currency from its alternate
    source and writes them into the shared cache.
.DESCRIPTION
    1. Determines the alternate source for the currency (TCB / Yahoo / none).
    2. Re-scans the range against the cache to find the truly missing dates
       (dates 台銀 already cached are left untouched).
    3. Fetches the whole range from the source in ONE request.
    4. Saves only the still-missing dates via DataFetcher.Save-Cache — existing
       台銀 entries are NEVER overwritten.
    5. Returns the newly-added flat rate objects (Date, CashBuy, CashSell,
       SpotBuy, SpotSell) for the caller to merge into the chart.
    Returns an empty array quickly when there is nothing missing or no source.
.PARAMETER CurrencyCode
    Currency code (e.g. "USD").
.PARAMETER StartDate
    Beginning of the range (inclusive).
.PARAMETER EndDate
    End of the range (inclusive).
.OUTPUTS
    PSCustomObject[] of newly cached rate objects, or an empty array.
#>
function Invoke-HistoricalBackfill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate
    )

    $source = Get-AltSourceForCurrency -CurrencyCode $CurrencyCode
    if ($null -eq $source) {
        Write-Verbose "HistoryBackfill: no alternate source for $CurrencyCode (VND/PHP stay 台銀-only)"
        return @()
    }

    # Re-scan the range against the cache: only genuinely missing dates matter.
    $missingRef = @()
    Get-HistoricalRange -CurrencyCode $CurrencyCode -StartDate $StartDate -EndDate $EndDate -MissingDates ([ref]$missingRef) | Out-Null
    if ($missingRef.Count -eq 0) {
        Write-Verbose "HistoryBackfill: nothing missing for $CurrencyCode in range"
        return @()
    }

    # Fetch the whole range from the selected source (one request).
    $fetched = @()
    if ($source -eq 'TCB') {
        $fetched = @(Get-TcbHistoryRates -CurrencyCode $CurrencyCode -StartDate $StartDate -EndDate $EndDate)
    }
    else {
        $fetched = @(Get-YahooHistoryRates -CurrencyCode $CurrencyCode -StartDate $StartDate -EndDate $EndDate)
    }

    $saved = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $fetched) {
        # Never overwrite existing cache entries (台銀 data wins when present).
        $existing = Get-CachedDate -CurrencyCode $CurrencyCode -Date $r.Date
        if ($null -ne $existing) { continue }

        $cacheData = [PSCustomObject]@{
            date      = $r.Date
            currency  = $CurrencyCode
            closeRate = [PSCustomObject]@{
                Date     = $r.Date
                CashBuy  = $r.CashBuy
                CashSell = $r.CashSell
                SpotBuy  = $r.SpotBuy
                SpotSell = $r.SpotSell
            }
            fetchedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        }

        Save-Cache -CurrencyCode $CurrencyCode -Date $r.Date -Data $cacheData
        $saved.Add($r)
    }

    Write-Verbose "HistoryBackfill: saved $($saved.Count) dates for $CurrencyCode (source: $source)"
    return @($saved)
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Get-AltSourceForCurrency',
    'Test-BankOfTaiwanAccess',
    'Get-TcbHistoryRates',
    'Get-YahooHistoryRates',
    'Invoke-HistoricalBackfill'
)
