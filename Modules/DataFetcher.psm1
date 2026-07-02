# =============================================================================
# DataFetcher.psm1
# Bank of Taiwan FX Rate Data Fetching and Caching Module
# =============================================================================

# -----------------------------------------------------------------------------
# Module-Level Variables
# -----------------------------------------------------------------------------

$script:CurrentRatesCache = $null
$script:CurrentRatesCacheTime = $null
$script:CurrentRatesCacheTTL = [TimeSpan]::FromMinutes(30)
$script:RequestDelay = 5
$script:LastRequestTime = $null
$script:CacheRootPath = $null

# --- WAF bypass: browser-like headers for rate.bot.com.tw ---
# The site uses a WAF (Challenge Validation) that blocks non-browser clients.
# Adding Sec-Fetch headers and a browser User-Agent bypasses this check.
$script:BotHeaders = @{
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

$script:CurrencyCodes = @(
    'USD', 'JPY', 'EUR', 'GBP', 'CNY', 'HKD', 'SGD', 'AUD',
    'CAD', 'CHF', 'NZD', 'THB', 'PHP', 'IDR', 'KRW', 'VND',
    'MYR', 'ZAR', 'SEK'
)

# =============================================================================
# Function: Initialize-Cache
# =============================================================================

<#
.SYNOPSIS
    Initializes the file-based cache directory structure.
.DESCRIPTION
    Creates the cache root directory and a subdirectory for each supported
    currency code.  Each subdirectory will hold per-date JSON files in the
    pattern  {CacheRoot}\{CURRENCY}\{YYYY-MM-DD}.json.
.PARAMETER CacheRootPath
    Root directory for the cache (e.g. "D:\...\Cache").
.EXAMPLE
    Initialize-Cache -CacheRootPath "D:\Willy_Desige_CODE\Foreign_Exchange_rate\Cache"
#>
function Initialize-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheRootPath
    )

    $script:CacheRootPath = $CacheRootPath

    if (-not (Test-Path -Path $CacheRootPath)) {
        New-Item -Path $CacheRootPath -ItemType Directory -Force | Out-Null
    }

    foreach ($code in $script:CurrencyCodes) {
        $currencyDir = Join-Path -Path $CacheRootPath -ChildPath $code
        if (-not (Test-Path -Path $currencyDir)) {
            New-Item -Path $currencyDir -ItemType Directory -Force | Out-Null
        }
    }
}

# =============================================================================
# Function: Invoke-BotWebRequest  (PRIVATE – not exported)
# =============================================================================

<#
.SYNOPSIS
    Makes an HTTP GET request to rate.bot.com.tw with browser-like headers.
.DESCRIPTION
    Uses [System.Net.HttpWebRequest] with Sec-Fetch and Chrome User-Agent headers
    to bypass the WAF (Challenge Validation) that rate.bot.com.tw deploys.
    Supports automatic decompression (gzip/deflate) and proper encoding detection
    (Big5 codepage 950 for CSV, UTF-8 for HTML).
.PARAMETER Uri
    The URL to request.
.OUTPUTS
    [string] The decoded response content.
#>
function Invoke-BotWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [switch]$IsCsv
    )

    # Ensure TLS 1.2 for compatibility
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $req.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $req.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $req.Timeout = 30000
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    # Apply browser-like headers
    $req.UserAgent = $script:BotHeaders['User-Agent']
    $req.Accept = $script:BotHeaders['Accept']
    $req.Headers.Add('Accept-Language', $script:BotHeaders['Accept-Language'])
    $req.Headers.Add('Sec-Ch-Ua', $script:BotHeaders['Sec-Ch-Ua'])
    $req.Headers.Add('Sec-Ch-Ua-Mobile', $script:BotHeaders['Sec-Ch-Ua-Mobile'])
    $req.Headers.Add('Sec-Ch-Ua-Platform', $script:BotHeaders['Sec-Ch-Ua-Platform'])
    $req.Headers.Add('Sec-Fetch-Dest', $script:BotHeaders['Sec-Fetch-Dest'])
    $req.Headers.Add('Sec-Fetch-Mode', $script:BotHeaders['Sec-Fetch-Mode'])
    $req.Headers.Add('Sec-Fetch-Site', $script:BotHeaders['Sec-Fetch-Site'])
    $req.Headers.Add('Sec-Fetch-User', $script:BotHeaders['Sec-Fetch-User'])
    $req.Headers.Add('Upgrade-Insecure-Requests', $script:BotHeaders['Upgrade-Insecure-Requests'])

    $resp = $req.GetResponse()
    $stream = $resp.GetResponseStream()

    # Read raw bytes into memory for encoding detection
    $ms = New-Object System.IO.MemoryStream
    $stream.CopyTo($ms)
    $bytes = $ms.ToArray()
    $ms.Close()
    $stream.Close()
    $resp.Close()

    # Detect encoding: CSV is Big5, HTML is UTF-8
    if ($IsCsv) {
        $encoding = [System.Text.Encoding]::GetEncoding(950)  # Big5
    } else {
        # Check for charset in Content-Type header
        $charset = ''
        $contentType = $resp.Headers['Content-Type']
        if ($contentType -match 'charset=([\w-]+)') {
            $charset = $Matches[1].Trim().ToUpper()
        }
        if ($charset -eq 'BIG5' -or $charset -eq 'CP950') {
            $encoding = [System.Text.Encoding]::GetEncoding(950)
        } else {
            $encoding = [System.Text.Encoding]::UTF8
        }
    }

    $content = $encoding.GetString($bytes)

    # Detect Challenge Validation (WAF block page) — return empty to signal failure
    if ($content -match 'Challenge Validation') {
        Write-Warning "DataFetcher: WAF Challenge Validation detected for $Uri. The request was blocked by the site's anti-bot protection."
        return ''
    }

    return $content
}

# =============================================================================
# Function: Invoke-RateLimitedRequest  (PRIVATE – not exported)
# =============================================================================

<#
.SYNOPSIS
    Makes an HTTP GET request with rate-limit enforcement and retry.
.DESCRIPTION
    Ensures at least $script:RequestDelay seconds elapse between consecutive
    requests.  On timeout the request is retried once after 10 seconds.
    Uses Invoke-BotWebRequest with browser headers to bypass WAF.
    Updates $script:LastRequestTime on every successful request.
.PARAMETER Uri
    The URL to request.
.OUTPUTS
    [string] The raw response content.
#>
function Invoke-RateLimitedRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    # --- Enforce minimum delay between requests ---
    if ($null -ne $script:LastRequestTime) {
        $elapsed = (Get-Date) - $script:LastRequestTime
        $remaining = $script:RequestDelay - $elapsed.TotalSeconds
        if ($remaining -gt 0) {
            Start-Sleep -Seconds $remaining
        }
    }

    # --- First attempt ---
    try {
        $content = Invoke-BotWebRequest -Uri $Uri
        $script:LastRequestTime = Get-Date
        if ([string]::IsNullOrEmpty($content)) {
            throw "DataFetcher: WAF blocked the request to $Uri (Challenge Validation page returned)"
        }
        return $content
    }
    catch [System.Net.WebException], [System.OperationCanceledException] {
        # Timeout or connection issue – retry once
        Write-Verbose "DataFetcher: First request to $Uri failed ($($_.Exception.Message)). Retrying in 10 s..."
        Start-Sleep -Seconds 10
        try {
            $content = Invoke-BotWebRequest -Uri $Uri
            $script:LastRequestTime = Get-Date
            if ([string]::IsNullOrEmpty($content)) {
                throw "DataFetcher: WAF blocked the request to $Uri after retry"
            }
            return $content
        }
        catch {
            throw "DataFetcher: Request to $Uri failed after retry: $($_.Exception.Message)"
        }
    }
    catch {
        # If it's our own WAF-detection throw, re-throw as-is
        if ($_.Exception.Message -match 'WAF') {
            throw
        }
        throw "DataFetcher: Request to $Uri failed: $($_.Exception.Message)"
    }
}

# =============================================================================
# Function: Get-CurrentRates
# =============================================================================

<#
.SYNOPSIS
    Fetches the current (today's) FX rates from Bank of Taiwan.
.DESCRIPTION
    Returns an array of PSCustomObject produced by the RateParser module's
    ConvertFrom-BotCsv function.  Results are cached in memory with a 30-minute
    TTL.  If the Bank site is under maintenance or a network error occurs,
    the stale cache (if any) is returned with a warning; otherwise an exception
    is thrown.
.OUTPUTS
    PSCustomObject[]  Parsed rate objects from ConvertFrom-BotCsv.
#>
function Get-CurrentRates {
    [CmdletBinding()]
    param()

    # 1. Return in-memory cache if still valid
    if ($null -ne $script:CurrentRatesCache -and $null -ne $script:CurrentRatesCacheTime) {
        $age = (Get-Date) - $script:CurrentRatesCacheTime
        if ($age -lt $script:CurrentRatesCacheTTL) {
            return $script:CurrentRatesCache
        }
    }

    # 2. Fetch CSV using HttpWebRequest with browser headers (bypass WAF)
    $url = 'https://rate.bot.com.tw/xrt/flcsv/0/day'
    $rawText = $null

    try {
        $rawText = Invoke-BotWebRequest -Uri $url -IsCsv

        # WAF detection — return stale cache if blocked
        if ([string]::IsNullOrEmpty($rawText)) {
            if ($null -ne $script:CurrentRatesCache) {
                Write-Warning "DataFetcher: WAF blocked current rates fetch. Returning stale cache."
                return $script:CurrentRatesCache
            }
            throw "DataFetcher: WAF blocked current rates fetch and no cache available."
        }
    }
    catch {
        # Network error – return stale cache if available
        if ($null -ne $script:CurrentRatesCache) {
            Write-Warning "DataFetcher: Network error fetching current rates. Returning stale cache (age: $(((Get-Date) - $script:CurrentRatesCacheTime).ToString()))"
            return $script:CurrentRatesCache
        }
        throw "DataFetcher: Network error fetching current rates and no cache available: $($_.Exception.Message)"
    }

    # 3. Detect Bank maintenance page or WAF challenge
    if ($rawText -match '系統維護' -or $rawText -match 'Challenge Validation') {
        if ($null -ne $script:CurrentRatesCache) {
            Write-Warning "DataFetcher: Bank site is under maintenance or WAF-protected. Returning stale cache."
            return $script:CurrentRatesCache
        }
        throw "DataFetcher: Bank site is under maintenance or WAF-protected and no cache available."
    }

    # 4. Parse via RateParser (must be imported before this module)
    $rates = ConvertFrom-BotCsv -RawCsv $rawText

    # 5. Update cache
    $script:CurrentRatesCache = $rates
    $script:CurrentRatesCacheTime = Get-Date

    return $rates
}

# =============================================================================
# Function: Get-CachedDate
# =============================================================================

<#
.SYNOPSIS
    Reads a cached rate entry from disk.
.DESCRIPTION
    Loads the JSON cache file for the given currency and date.  Returns $null
    if the file does not exist or contains corrupt JSON (corrupt files are
    deleted automatically).
.PARAMETER CurrencyCode
    Currency code (e.g. "USD").
.PARAMETER Date
    Date string in YYYY-MM-DD format.
.OUTPUTS
    PSCustomObject or $null
#>
function Get-CachedDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [string]$Date
    )

    $filePath = Join-Path -Path $script:CacheRootPath -ChildPath "$CurrencyCode\$Date.json"

    if (-not (Test-Path -Path $filePath)) {
        return $null
    }

    try {
        $json = Get-Content -Path $filePath -Raw -Encoding UTF8
        $obj = $json | ConvertFrom-Json
        return $obj
    }
    catch {
        # Corrupt JSON – delete and return null
        try {
            Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Best-effort delete
        }
        return $null
    }
}

# =============================================================================
# Function: Save-Cache
# =============================================================================

<#
.SYNOPSIS
    Persists a rate object to the file-based cache.
.DESCRIPTION
    Serializes $Data to JSON (depth 5) and writes it to
    {CacheRoot}\{CurrencyCode}\{Date}.json.
.PARAMETER CurrencyCode
    Currency code (e.g. "USD").
.PARAMETER Date
    Date string in YYYY-MM-DD format.
.PARAMETER Data
    The rate object to cache.
#>
function Save-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [string]$Date,

        [Parameter(Mandatory)]
        [object]$Data
    )

    $filePath = Join-Path -Path $script:CacheRootPath -ChildPath "$CurrencyCode\$Date.json"

    # Ensure currency subdirectory exists
    $dir = Split-Path -Path $filePath -Parent
    if (-not (Test-Path -Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $json = $Data | ConvertTo-Json -Depth 5
    Set-Content -Path $filePath -Value $json -Encoding UTF8 -NoNewline
}

# =============================================================================
# Function: Get-HistoricalRate
# =============================================================================

<#
.SYNOPSIS
    Retrieves a historical FX rate for a single currency and date.
.DESCRIPTION
    Checks the file cache first.  If a valid cached entry exists it is
    returned immediately without any HTTP request.  Otherwise the Bank of
    Taiwan historical-rate page is fetched (with rate limiting), parsed via
    RateParser functions, and the result is cached.  Returns $null when the
    target date has no data (non-business day / holiday).
.PARAMETER CurrencyCode
    Currency code (e.g. "USD").
.PARAMETER Date
    Date string in YYYY-MM-DD format.
.OUTPUTS
    PSCustomObject with Date, CashBuy, CashSell, SpotBuy, SpotSell; or $null.
#>
function Get-HistoricalRate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [string]$Date
    )

    # 1. Check cache
    $cached = Get-CachedDate -CurrencyCode $CurrencyCode -Date $Date
    if ($null -ne $cached) {
        # Reconstruct the return object from cache
        $result = [PSCustomObject]@{
            Date     = $cached.date
            CashBuy  = $cached.closeRate.CashBuy
            CashSell = $cached.closeRate.CashSell
            SpotBuy  = $cached.closeRate.SpotBuy
            SpotSell = $cached.closeRate.SpotSell
        }
        return $result
    }

    # 2. Fetch HTML
    $url = "https://rate.bot.com.tw/xrt/quote/$Date/$CurrencyCode/spot"
    $html = $null

    try {
        $html = Invoke-RateLimitedRequest -Uri $url
    }
    catch {
        throw "DataFetcher: Failed to fetch historical rate for $CurrencyCode on $Date : $($_.Exception.Message)"
    }

    # 3. Parse via RateParser
    $intradayRates = ConvertFrom-BotHtml -RawHtml $html
    $closingRate = Get-ClosingRate -IntradayRates $intradayRates -Date $Date

    # 4. No data (non-business day / holiday)
    if ($null -eq $closingRate) {
        return $null
    }

    # 5. Build cache entry
    $cacheData = [PSCustomObject]@{
        date      = $Date
        currency  = $CurrencyCode
        closeRate = $closingRate
        fetchedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    }

    Save-Cache -CurrencyCode $CurrencyCode -Date $Date -Data $cacheData

    # 6. Return object with Date included
    $result = [PSCustomObject]@{
        Date     = $Date
        CashBuy  = $closingRate.CashBuy
        CashSell = $closingRate.CashSell
        SpotBuy  = $closingRate.SpotBuy
        SpotSell = $closingRate.SpotSell
    }

    return $result
}

# =============================================================================
# Function: Get-BusinessDays
# =============================================================================

<#
.SYNOPSIS
    Returns the business days (Mon-Fri) between two dates.
.DESCRIPTION
    Iterates from StartDate to EndDate (inclusive) and skips Saturdays and
    Sundays.  Taiwanese public holidays are NOT excluded – the API will return
    no data for holidays and the cache layer handles that.
.PARAMETER StartDate
    Start of the date range.
.PARAMETER EndDate
    End of the date range (inclusive).
.OUTPUTS
    [datetime[]]  Array of business-day datetimes, sorted ascending.
#>
function Get-BusinessDays {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate
    )

    $days = [System.Collections.Generic.List[datetime]]::new()
    $current = $StartDate.Date

    while ($current -le $EndDate.Date) {
        $dow = $current.DayOfWeek
        if ($dow -ne [DayOfWeek]::Saturday -and $dow -ne [DayOfWeek]::Sunday) {
            $days.Add($current)
        }
        $current = $current.AddDays(1)
    }

    return @($days)
}

# =============================================================================
# Function: Get-HistoricalRange
# =============================================================================

<#
.SYNOPSIS
    Loads cached historical rates for a date range.
.DESCRIPTION
    For each business day in the range, checks the file cache.  Cached entries
    are included in the return array.  Dates without a cache entry are
    appended to the $MissingDates reference parameter so the caller can
    schedule background fetching.  No HTTP requests are made by this function.
.PARAMETER CurrencyCode
    Currency code (e.g. "USD").
.PARAMETER StartDate
    Start of the date range.
.PARAMETER EndDate
    End of the date range (inclusive).
.PARAMETER MissingDates
    A [ref] to an array.  Dates with no cache entry will be appended here.
.OUTPUTS
    PSCustomObject[]  Array of rate objects (Date, CashBuy, CashSell, SpotBuy, SpotSell)
    sorted by Date.  Only cached/available data is included.
#>
function Get-HistoricalRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrencyCode,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [datetime]$EndDate,

        [Parameter(Mandatory)]
        [ref]$MissingDates
    )

    $businessDays = Get-BusinessDays -StartDate $StartDate -EndDate $EndDate
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($day in $businessDays) {
        $dateStr = $day.ToString('yyyy-MM-dd')
        $cached = Get-CachedDate -CurrencyCode $CurrencyCode -Date $dateStr

        if ($null -ne $cached) {
            $entry = [PSCustomObject]@{
                Date     = $dateStr
                CashBuy  = $cached.closeRate.CashBuy
                CashSell = $cached.closeRate.CashSell
                SpotBuy  = $cached.closeRate.SpotBuy
                SpotSell = $cached.closeRate.SpotSell
            }
            $results.Add($entry)
        }
        else {
            $MissingDates.Value += $dateStr
        }
    }

    # Sort by Date and return as guaranteed array (never $null)
    if ($results.Count -gt 0) {
        $sorted = @($results) | Sort-Object -Property { [datetime]::ParseExact($_.Date, 'yyyy-MM-dd', $null) }
        @($sorted)
    } else {
        @()
    }
}

# =============================================================================
# Function: Expire-Cache
# =============================================================================

<#
.SYNOPSIS
    Expires the in-memory current rates cache so the next call fetches fresh data.
.DESCRIPTION
    Sets the cache timestamp to [datetime]::MinValue, forcing Get-CurrentRates
    to re-fetch from the network on its next call.
.EXAMPLE
    Expire-Cache
#>
function Clear-Cache {
    [CmdletBinding()]
    param()

    $script:CurrentRatesCacheTime = [datetime]::MinValue
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Initialize-Cache',
    'Get-CurrentRates',
    'Get-HistoricalRate',
    'Get-HistoricalRange',
    'Get-BusinessDays',
    'Get-CachedDate',
    'Save-Cache',
    'Clear-Cache'
)