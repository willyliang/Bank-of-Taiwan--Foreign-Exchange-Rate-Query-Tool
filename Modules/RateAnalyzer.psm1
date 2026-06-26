# =============================================================================
# RateAnalyzer.psm1
# FX Rate Statistical Analysis Module
# Computes SMA, RSI, recent high/low, and current percentile indicators.
# =============================================================================

# Import i18n module for localization
$modDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modDir 'i18n.psm1') -Force

# -----------------------------------------------------------------------------
# Module-Level Variables
# -----------------------------------------------------------------------------

$script:RateProperties = @('CashBuy', 'CashSell', 'SpotBuy', 'SpotSell')

# =============================================================================
# Function: Get-SimpleMovingAverage
# =============================================================================

<#
.SYNOPSIS
    Computes the Simple Moving Average (SMA) for a given rate property.

.DESCRIPTION
    Takes an array of data points and calculates the SMA of the specified
    property over the given period.  Only non-zero, non-null values are
    included in the calculation.  If fewer valid data points exist than the
    requested period, $null is returned.

.PARAMETER DataPoints
    Array of PSCustomObject with rate properties (e.g. CashBuy, CashSell,
    SpotBuy, SpotSell) and a Date or Time field.

.PARAMETER Property
    The property name to average (e.g. "SpotSell", "CashBuy").

.PARAMETER Period
    The SMA window size in number of data points (e.g. 5, 10, 20).

.OUTPUTS
    [decimal] The SMA value, or $null if insufficient valid data.

.EXAMPLE
    $sma = Get-SimpleMovingAverage -DataPoints $history -Property "SpotSell" -Period 20
#>
function Get-SimpleMovingAverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [Parameter(Mandatory)]
        [int]$Period
    )

    # --- Collect valid (non-zero, non-null) values ---
    $validValues = [System.Collections.Generic.List[decimal]]::new()
    foreach ($pt in $DataPoints) {
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) {
            $validValues.Add([decimal]$val)
        }
    }
    $validArr = @($validValues)

    # --- Need at least $Period valid points ---
    if ($validArr.Count -lt $Period) {
        return $null
    }

    # --- Take the last $Period values and average ---
    $subset = $validArr[($validArr.Count - $Period)..($validArr.Count - 1)]
    $sum = [decimal]0
    foreach ($v in $subset) {
        $sum += $v
    }

    return [math]::Round(($sum / $Period), 4)
}

# =============================================================================
# Function: Get-RelativeStrengthIndex
# =============================================================================

<#
.SYNOPSIS
    Computes the Relative Strength Index (RSI) for a given rate property.

.DESCRIPTION
    Calculates the RSI using Wilder's smoothing method (also known as the
    exponential moving average method).  Only non-zero, non-null values
    participate in the calculation.  At least Period+1 valid data points
    are required; otherwise $null is returned.

.PARAMETER DataPoints
    Array of PSCustomObject with rate properties and a Date or Time field.

.PARAMETER Property
    The property name to compute RSI for (e.g. "SpotSell").

.PARAMETER Period
    The RSI look-back period (default 14).

.OUTPUTS
    [decimal] The RSI value (0-100), or $null if insufficient valid data.

.EXAMPLE
    $rsi = Get-RelativeStrengthIndex -DataPoints $history -Property "SpotSell" -Period 14
#>
function Get-RelativeStrengthIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [int]$Period = 14
    )

    # --- Collect valid values ---
    $validValues = [System.Collections.Generic.List[decimal]]::new()
    foreach ($pt in $DataPoints) {
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) {
            $validValues.Add([decimal]$val)
        }
    }
    $validArr = @($validValues)

    # --- Need at least Period+1 points to compute changes ---
    if ($validArr.Count -lt ($Period + 1)) {
        return $null
    }

    # --- Compute price changes ---
    $changes = [System.Collections.Generic.List[decimal]]::new()
    for ($i = 1; $i -lt $validArr.Count; $i++) {
        $changes.Add($validArr[$i] - $validArr[$i - 1])
    }
    $changesArr = @($changes)

    # --- Initial average gain / loss (first $Period changes) ---
    $sumGain = [decimal]0
    $sumLoss = [decimal]0
    for ($i = 0; $i -lt $Period; $i++) {
        if ($changesArr[$i] -gt 0) {
            $sumGain += $changesArr[$i]
        }
        elseif ($changesArr[$i] -lt 0) {
            $sumLoss += [math]::Abs($changesArr[$i])
        }
    }

    $avgGain = $sumGain / $Period
    $avgLoss = $sumLoss / $Period

    # --- If average loss is zero, RSI = 100 ---
    if ($avgLoss -eq 0) {
        return [decimal]100
    }

    # --- Smooth remaining changes using Wilder's method ---
    for ($i = $Period; $i -lt $changesArr.Count; $i++) {
        $gain = [decimal]0
        $loss = [decimal]0
        if ($changesArr[$i] -gt 0) {
            $gain = $changesArr[$i]
        }
        elseif ($changesArr[$i] -lt 0) {
            $loss = [math]::Abs($changesArr[$i])
        }

        $avgGain = ($avgGain * ($Period - 1) + $gain) / $Period
        $avgLoss = ($avgLoss * ($Period - 1) + $loss) / $Period
    }

    # --- Final RSI ---
    if ($avgLoss -eq 0) {
        return [decimal]100
    }

    $rs = $avgGain / $avgLoss
    $rsi = [decimal]100 - ([decimal]100 / ([decimal]1 + $rs))

    return [math]::Round($rsi, 2)
}

# =============================================================================
# Function: Get-RecentHighLow
# =============================================================================

<#
.SYNOPSIS
    Finds the recent N-day high and low for a given rate property.

.DESCRIPTION
    Scans the last N valid (non-zero, non-null) data points and returns
    the highest and lowest values.  If fewer than 1 valid point exists,
    $null is returned.

.PARAMETER DataPoints
    Array of PSCustomObject with rate properties and a Date or Time field.

.PARAMETER Property
    The property name to examine (e.g. "SpotSell").

.PARAMETER Period
    The look-back window in number of data points (e.g. 30).

.OUTPUTS
    PSCustomObject with High ([decimal]) and Low ([decimal]), or $null
    if insufficient valid data.

.EXAMPLE
    $hl = Get-RecentHighLow -DataPoints $history -Property "SpotSell" -Period 30
    # $hl.High 嚙踝蕭 32.50,  $hl.Low 嚙踝蕭 31.80
#>
function Get-RecentHighLow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [Parameter(Mandatory)]
        [int]$Period
    )

    # --- Collect valid values ---
    $validValues = [System.Collections.Generic.List[decimal]]::new()
    foreach ($pt in $DataPoints) {
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) {
            $validValues.Add([decimal]$val)
        }
    }
    $validArr = @($validValues)

    if ($validArr.Count -lt 1) {
        return $null
    }

    # --- Take the last $Period values (or all if fewer) ---
    $takeCount = [math]::Min($Period, $validArr.Count)
    $subset = $validArr[($validArr.Count - $takeCount)..($validArr.Count - 1)]

    $high = $subset[0]
    $low = $subset[0]

    foreach ($v in $subset) {
        if ($v -gt $high) { $high = $v }
        if ($v -lt $low)  { $low = $v }
    }

    return [PSCustomObject]@{
        High = $high
        Low  = $low
    }
}

# =============================================================================
# Function: Get-CurrentPosition
# =============================================================================

<#
.SYNOPSIS
    Computes where the current rate sits relative to the N-period range (percentile).

.DESCRIPTION
    Takes the last N valid data points, determines the high and low of the
    range, and calculates the percentile position of the most recent value.
    A percentile of 0 means the current value equals the low; 100 means it
    equals the high; 50 means it is at the mid-point.

.PARAMETER DataPoints
    Array of PSCustomObject with rate properties and a Date or Time field.

.PARAMETER Property
    The property name to examine (e.g. "SpotSell").

.PARAMETER Period
    The look-back window in number of data points (e.g. 30).

.OUTPUTS
    [decimal] The percentile (0-100), or $null if insufficient valid data
    or if all values are identical (range is zero and current 嚙踝蕭 high/low).

.EXAMPLE
    $pct = Get-CurrentPosition -DataPoints $history -Property "SpotSell" -Period 30
    # Returns e.g. 25.0 (current rate is at the 25th percentile of the range)
#>
function Get-CurrentPosition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [Parameter(Mandatory)]
        [int]$Period
    )

    # --- Collect valid values ---
    $validValues = [System.Collections.Generic.List[decimal]]::new()
    foreach ($pt in $DataPoints) {
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) {
            $validValues.Add([decimal]$val)
        }
    }
    $validArr = @($validValues)

    if ($validArr.Count -lt 1) {
        return $null
    }

    # --- Take the last $Period values (or all if fewer) ---
    $takeCount = [math]::Min($Period, $validArr.Count)
    $subset = $validArr[($validArr.Count - $takeCount)..($validArr.Count - 1)]

    # --- Current value is the last valid value ---
    $current = $validArr[-1]

    $high = $subset[0]
    $low = $subset[0]

    foreach ($v in $subset) {
        if ($v -gt $high) { $high = $v }
        if ($v -lt $low)  { $low = $v }
    }

    $range = $high - $low

    # --- Edge: zero range ---
    if ($range -eq 0) {
        # All values are identical 嚙碼 percentile is 50 by convention
        return [decimal]50
    }

    $percentile = [decimal](($current - $low) / $range) * [decimal]100

    return [math]::Round($percentile, 1)
}

# =============================================================================
# Function: Get-RateStatistics  (PRIVATE helper 嚙碾 not exported)
# =============================================================================

<#
.SYNOPSIS
    Computes all statistical indicators for a single rate property.

.DESCRIPTION
    Internal helper that calls Get-SimpleMovingAverage, Get-RelativeStrengthIndex,
    Get-RecentHighLow, and Get-CurrentPosition for one property and returns
    a hashtable with the results.

.PARAMETER DataPoints
    Array of PSCustomObject data points.

.PARAMETER Property
    The rate property name (e.g. "SpotSell").

.PARAMETER HighLowPeriod
    The look-back period for high/low and percentile.

.OUTPUTS
    [hashtable] with keys: SMA5, SMA20, RSI14, RecentHigh, RecentLow, CurrentPercentile
#>
function Get-PropertyIndicators {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [Parameter(Mandatory)]
        [int]$HighLowPeriod
    )

    $hlResult = Get-RecentHighLow -DataPoints $DataPoints -Property $Property -Period $HighLowPeriod

    return @{
        SMA5              = Get-SimpleMovingAverage -DataPoints $DataPoints -Property $Property -Period 5
        SMA20             = Get-SimpleMovingAverage -DataPoints $DataPoints -Property $Property -Period 20
        RSI14             = Get-RelativeStrengthIndex -DataPoints $DataPoints -Property $Property -Period 14
        RecentHigh        = if ($null -ne $hlResult) { $hlResult.High } else { $null }
        RecentLow         = if ($null -ne $hlResult) { $hlResult.Low } else { $null }
        CurrentPercentile = Get-CurrentPosition -DataPoints $DataPoints -Property $Property -Period $HighLowPeriod
    }
}

# =============================================================================
# Function: Get-RateStatistics
# =============================================================================

<#
.SYNOPSIS
    Main entry point that computes all statistical indicators from historical FX rate data.

.DESCRIPTION
    Takes an array of PSCustomObject data points (Date, CashBuy, CashSell, SpotBuy,
    SpotSell) and computes SMA (5 & 20 day), RSI (14-day), recent 30-day high/low,
    and current percentile for all four rate types.  Also determines the trend
    (based on SMA5 vs SMA20 of SpotSell) and generates a short Traditional Chinese
    summary.

    Accepts both daily data (with Date property) and intraday data (with Time
    property).  For intraday data, the last data point is treated as the "current"
    value.

.PARAMETER DataPoints
    Array of PSCustomObject with properties: Date or Time, CashBuy, CashSell,
    SpotBuy, SpotSell (decimal; 0 means N/A).

.PARAMETER Currency
    The currency code (e.g. "USD").

.PARAMETER Period
    The period label (e.g. "3嚙諉歹蕭", "嚙踝蕭嚙踝蕭").

.OUTPUTS
    PSCustomObject with the following properties:
    - Currency              : Currency code
    - Period                : Period label
    - DataPointCount        : Number of data points provided
    - CurrentSpotSell       : Most recent SpotSell value (or 0 if N/A)
    - SMA5                  : Hashtable { CashBuy, CashSell, SpotBuy, SpotSell }
    - SMA20                 : Hashtable { CashBuy, CashSell, SpotBuy, SpotSell }
    - RSI14                 : Hashtable { CashBuy, CashSell, SpotBuy, SpotSell }
    - RecentHigh_30d        : Hashtable { CashBuy, CashSell, SpotBuy, SpotSell }
    - RecentLow_30d         : Hashtable { CashBuy, CashSell, SpotBuy, SpotSell }
    - CurrentPercentile_30d : Hashtable { CashBuy, CashSell, SpotBuy, SpotSell }
    - Trend                 : (L 'trend_up'), (L 'trend_down'), or (L 'trend_consolidate')
    - Summary               : Short Traditional Chinese summary

.EXAMPLE
    $stats = Get-RateStatistics -DataPoints $cachedData -Currency "USD" -Period "3嚙諉歹蕭"
    $stats.Summary
    # "嚙諍前嚙磐嚙踝蕭嚙踝蕭X嚙論率 32.15 嚙踝蕭嚙踝蕭30嚙踝蕭嚙?25 嚙褊歹蕭嚙踝蕭A嚙踝蕭嚙踝蕭C嚙瘢嚙瘠SMA5 > SMA20嚙璀嚙線嚙踝蕭嚙談勢上嚙褕。RSI=35嚙璀嚙踝蕭嚙緲嚙瘠"
#>
function Get-RateStatistics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Currency,

        [Parameter(Mandatory)]
        [string]$Period,

        [Parameter()]
        [ValidateSet('zh', 'en')]
        [string]$Lang
    )

    # Sync language for this module scope if explicitly provided
    if ($PSBoundParameters.ContainsKey('Lang')) {
        Set-Language $Lang
    }

    # --- Handle empty input ---
    if ($null -eq $DataPoints -or $DataPoints.Count -eq 0) {
        return [PSCustomObject]@{
            Currency               = $Currency
            Period                 = $Period
            DataPointCount         = 0
            CurrentSpotSell        = $null
            SMA5                   = $null
            SMA20                  = $null
            RSI14                  = $null
            RecentHigh_30d         = $null
            RecentLow_30d          = $null
            CurrentPercentile_30d  = $null
            Trend                  = $null
            Summary                = L 'stats_no_data'
        }
    }

    $dataCount = $DataPoints.Count
    $highLowPeriod = 30

    # --- Determine "current" SpotSell (last valid value) ---
    $currentSpotSell = $null
    for ($i = $DataPoints.Count - 1; $i -ge 0; $i--) {
        $val = $DataPoints[$i].SpotSell
        if ($null -ne $val -and $val -ne 0) {
            $currentSpotSell = [decimal]$val
            break
        }
    }

    # --- Compute indicators for each rate property ---
    $sma5             = @{}
    $sma20            = @{}
    $rsi14            = @{}
    $recentHigh30     = @{}
    $recentLow30      = @{}
    $currentPct30     = @{}

    foreach ($prop in $script:RateProperties) {
        $indicators = Get-PropertyIndicators -DataPoints $DataPoints -Property $prop -HighLowPeriod $highLowPeriod

        $sma5[$prop]            = $indicators.SMA5
        $sma20[$prop]           = $indicators.SMA20
        $rsi14[$prop]           = $indicators.RSI14
        $recentHigh30[$prop]    = $indicators.RecentHigh
        $recentLow30[$prop]     = $indicators.RecentLow
        $currentPct30[$prop]    = $indicators.CurrentPercentile
    }

    # --- Determine trend based on SpotSell SMA5 vs SMA20 ---
    $trend = L 'trend_consolidate'
    $spotSellSma5  = $sma5['SpotSell']
    $spotSellSma20 = $sma20['SpotSell']

    if ($null -ne $spotSellSma5 -and $null -ne $spotSellSma20) {
        if ($spotSellSma5 -gt $spotSellSma20) {
            $trend = L 'trend_up'
        }
        elseif ($spotSellSma5 -lt $spotSellSma20) {
            $trend = L 'trend_down'
        }
    }

    # --- Build summary (Traditional Chinese) ---
    $summary = Build-Summary -CurrentSpotSell $currentSpotSell `
                             -SpotSellPercentile $currentPct30['SpotSell'] `
                             -Trend $trend `
                             -SpotSellRsi $rsi14['SpotSell']

    return [PSCustomObject]@{
        Currency               = $Currency
        Period                 = $Period
        DataPointCount         = $dataCount
        CurrentSpotSell        = $currentSpotSell
        SMA5                   = $sma5
        SMA20                  = $sma20
        RSI14                  = $rsi14
        RecentHigh_30d         = $recentHigh30
        RecentLow_30d          = $recentLow30
        CurrentPercentile_30d  = $currentPct30
        Trend                  = $trend
        Summary                = $summary
    }
}

# =============================================================================
# Function: Build-Summary  (PRIVATE helper 嚙碾 not exported)
# =============================================================================

<#
.SYNOPSIS
    Builds a short Traditional Chinese summary string from key indicators.

.DESCRIPTION
    Combines the current SpotSell value, its 30-day percentile, the trend
    direction, and the RSI reading into a human-readable summary.

.PARAMETER CurrentSpotSell
    The current SpotSell rate (decimal or $null).

.PARAMETER SpotSellPercentile
    The 30-day percentile for SpotSell (decimal or $null).

.PARAMETER Trend
    The trend string: (L 'trend_up'), (L 'trend_down'), or (L 'trend_consolidate').

.PARAMETER SpotSellRsi
    The 14-day RSI for SpotSell (decimal or $null).

.OUTPUTS
    [string] A Traditional Chinese summary.
#>
function Build-Summary {
    [CmdletBinding()]
    param(
        [decimal]$CurrentSpotSell = $null,

        [decimal]$SpotSellPercentile = $null,

        [string]$Trend = $(L 'trend_consolidate'),

        [decimal]$SpotSellRsi = $null
    )

    $parts = @()

    # --- Part 1: Current rate and percentile ---
    if ($null -ne $CurrentSpotSell -and $null -ne $SpotSellPercentile) {
        $pctInt = [int][math]::Round($SpotSellPercentile)
        $positionDesc = ""
        if ($pctInt -le 20) {
            $positionDesc = L 'position_near_low'
        }
        elseif ($pctInt -ge 80) {
            $positionDesc = L 'position_near_high'
        }
        elseif ($pctInt -le 40) {
            $positionDesc = L 'position_weak'
        }
        elseif ($pctInt -ge 60) {
            $positionDesc = L 'position_strong'
        }
        else {
            $positionDesc = L 'position_neutral'
        }

        $parts += (L 'summary_pos_format' -f $CurrentSpotSell, $pctInt, $positionDesc)
    }
    elseif ($null -ne $CurrentSpotSell) {
        $parts += (L 'summary_spot_only' -f $CurrentSpotSell)
    }

    # --- Part 2: Trend ---

    switch ($Trend) {
        { $_ -eq (L 'trend_up') } { $parts += (L 'trend_rising') }
        { $_ -eq (L 'trend_down') } { $parts += (L 'trend_falling') }
        { $_ -eq (L 'trend_consolidate') } { $parts += (L 'trend_consolidating') }
    }

    # --- Part 3: RSI ---
    if ($null -ne $SpotSellRsi) {
        $rsiInt = [int][math]::Round($SpotSellRsi)
        $rsiDesc = ""
        if ($rsiInt -ge 70) {
            $rsiDesc = L 'rsi_score_overbought'
        }
        elseif ($rsiInt -le 30) {
            $rsiDesc = L 'rsi_score_oversold'
        }
        else {
            $rsiDesc = L 'rsi_score_neutral'
        }
        $parts += (L 'rsi_format' -f $rsiInt, $rsiDesc)
    }

    return ($parts -join '')
}

# =============================================================================
# Function: Get-MACD
# =============================================================================

<#
.SYNOPSIS
    嚙緘嚙賤移嚙褊伐蕭嚙踝蕭嚙踝蕭嚙衝湛蕭嚙踝蕭 (MACD) 嚙踝蕭嚙請。

.DESCRIPTION
    嚙誹據快速 EMA 嚙瞑嚙瘠嚙緣 EMA 嚙踝蕭嚙緣嚙褓計嚙踝蕭 MACD 嚙線嚙璀嚙璀嚙踝蕭 MACD 嚙線嚙踝蕭
    EMA 嚙緻嚙踝蕭T嚙踝蕭嚙線嚙璀嚙踝蕭怳嚙踝蕭t嚙磐嚙踝蕭嚙磕嚙踝蕭嚙踝蕭 (Histogram)嚙瘠
    嚙褓使用非嚙編嚙畿嚙瘩嚙褐值迎蕭嚙踝蕭嚙踝蕭I嚙箠嚙踝蕭p嚙踝蕭C嚙磐嚙踝蕭嚙衝賂蕭嚙踝蕭I嚙踝蕭嚙踝蕭嚙璀嚙稷嚙踝蕭 $null嚙瘠

    EMA 嚙緘嚙踝蕭閬∴蕭G嚙踝蕭嚙踝蕭 = 2/(嚙踝蕭嚙踝蕭+1)嚙瘤EMA = (嚙踝蕭嚙盤 - 嚙箴嚙瑾EMA) * 嚙踝蕭嚙踝蕭 + 嚙箴嚙瑾EMA

.PARAMETER DataPoints
    嚙稽嚙緣嚙論率嚙豎性迎蕭 PSCustomObject 嚙罷嚙瘠嚙稽嚙緘 CashBuy嚙畿CashSell嚙畿SpotBuy嚙畿SpotSell嚙稷嚙瘠

.PARAMETER Property
    嚙緯嚙緘嚙賤的嚙豎性名嚙誶（嚙緘 "SpotSell"嚙稷嚙瘠

.PARAMETER FastPeriod
    嚙誰速 EMA 嚙踝蕭嚙踝蕭嚙璀嚙緩嚙稽 12嚙瘠

.PARAMETER SlowPeriod
    嚙瘠嚙緣 EMA 嚙踝蕭嚙踝蕭嚙璀嚙緩嚙稽 26嚙瘠

.PARAMETER SignalPeriod
    嚙確嚙踝蕭嚙線 EMA 嚙踝蕭嚙踝蕭嚙璀嚙緩嚙稽 9嚙瘠

.OUTPUTS
    PSCustomObject @{ MACDLine = [decimal]; SignalLine = [decimal]; Histogram = [decimal] }嚙璀
    嚙踝蕭 $null嚙稽嚙踝蕭嚙踝蕭嚙踝蕭氶^嚙瘠

.EXAMPLE
    $macd = Get-MACD -DataPoints $history -Property "SpotSell"
    # $macd.MACDLine 嚙踝蕭 -0.05, $macd.SignalLine 嚙踝蕭 -0.12, $macd.Histogram 嚙踝蕭 0.07
#>
function Get-MACD {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [int]$FastPeriod = 12,

        [int]$SlowPeriod = 26,

        [int]$SignalPeriod = 9
    )

    # --- Collect valid (non-zero, non-null) values ---
    $validValues = [System.Collections.Generic.List[decimal]]::new()
    foreach ($pt in $DataPoints) {
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) {
            $validValues.Add([decimal]$val)
        }
    }
    $validArr = @($validValues)

    # --- Need at least SlowPeriod + SignalPeriod data points ---
    $minRequired = $SlowPeriod + $SignalPeriod
    if ($validArr.Count -lt $minRequired) {
        return $null
    }

    # --- Helper: compute EMA for a given period over the value array ---
    function Compute-EMA {
        param(
            [decimal[]]$Values,
            [int]$Period
        )

        $multiplier = [decimal](2) / ([decimal]$Period + [decimal]1)

        # Seed EMA with SMA of first $Period values
        $sum = [decimal]0
        for ($i = 0; $i -lt $Period; $i++) {
            $sum += $Values[$i]
        }
        $ema = $sum / $Period

        # Smooth remaining values
        for ($i = $Period; $i -lt $Values.Count; $i++) {
            $ema = ($Values[$i] - $ema) * $multiplier + $ema
        }

        return $ema
    }

    # --- Compute fast EMA and slow EMA ---
    $fastEMA = Compute-EMA -Values $validArr -Period $FastPeriod
    $slowEMA = Compute-EMA -Values $validArr -Period $SlowPeriod

    # --- Compute MACD line series: MACD[i] = FastEMA[i] - SlowEMA[i] ---
    # To compute the signal line, we need the MACD series over time.
    # We recompute by walking forward and collecting MACD values.

    $fastMultiplier = [decimal](2) / ([decimal]$FastPeriod + [decimal]1)
    $slowMultiplier = [decimal](2) / ([decimal]$SlowPeriod + [decimal]1)

    # Seed fast EMA
    $fastSum = [decimal]0
    for ($i = 0; $i -lt $FastPeriod; $i++) {
        $fastSum += $validArr[$i]
    }
    $currentFastEMA = $fastSum / $FastPeriod

    # Seed slow EMA
    $slowSum = [decimal]0
    for ($i = 0; $i -lt $SlowPeriod; $i++) {
        $slowSum += $validArr[$i]
    }
    $currentSlowEMA = $slowSum / $SlowPeriod

    # Walk forward and collect MACD values
    # Both EMAs walk from their respective seeds; MACD recorded from SlowPeriod onward
    $macdValues = [System.Collections.Generic.List[decimal]]::new()
    for ($i = $FastPeriod; $i -lt $validArr.Count; $i++) {
        $currentFastEMA = ($validArr[$i] - $currentFastEMA) * $fastMultiplier + $currentFastEMA

        if ($i -ge $SlowPeriod) {
            $currentSlowEMA = ($validArr[$i] - $currentSlowEMA) * $slowMultiplier + $currentSlowEMA
            $macdValues.Add($currentFastEMA - $currentSlowEMA)
        }
    }

    $macdArr = @($macdValues)

    # --- Signal line: EMA of MACD values ---
    if ($macdArr.Count -lt $SignalPeriod) {
        return $null
    }

    $signalMultiplier = [decimal](2) / ([decimal]$SignalPeriod + [decimal]1)

    $sigSum = [decimal]0
    for ($i = 0; $i -lt $SignalPeriod; $i++) {
        $sigSum += $macdArr[$i]
    }
    $currentSignal = $sigSum / $SignalPeriod

    for ($i = $SignalPeriod; $i -lt $macdArr.Count; $i++) {
        $currentSignal = ($macdArr[$i] - $currentSignal) * $signalMultiplier + $currentSignal
    }

    # --- Final values ---
    $macdLine = $macdArr[-1]
    $signalLine = $currentSignal
    $histogram = $macdLine - $signalLine

    return [PSCustomObject]@{
        MACDLine   = [math]::Round($macdLine, 4)
        SignalLine = [math]::Round($signalLine, 4)
        Histogram  = [math]::Round($histogram, 4)
    }
}

# =============================================================================
# Function: Get-BollingerBands
# =============================================================================

<#
.SYNOPSIS
    嚙緘嚙賤布嚙盤嚙緬嚙瘩 (Bollinger Bands) 嚙踝蕭嚙請。

.DESCRIPTION
    嚙誹據最迎蕭 N 嚙諉佗蕭嚙衝賂蕭嚙踝蕭I嚙踝蕭 SMA 嚙瑾嚙踝蕭嚙踝蕭嚙緙嚙璀嚙瘡嚙踝蕭嚙踝蕭郱t嚙踝蕭嚙瘡
    嚙踝蕭嚙複計嚙踝蕭W嚙緙嚙瞑嚙磊嚙緙嚙瘠嚙瞑嚙褕計嚙踝蕭a嚙箴 (Bandwidth) 嚙瞑 %B 嚙踝蕭嚙請。
    嚙褓使用非嚙編嚙畿嚙瘩嚙褐值迎蕭嚙踝蕭嚙踝蕭I嚙瘠嚙磐嚙踝蕭嚙衝賂蕭嚙踝蕭I嚙踝蕭嚙踝蕭嚙璀嚙稷嚙踝蕭 $null嚙瘠

.PARAMETER DataPoints
    嚙稽嚙緣嚙論率嚙豎性迎蕭 PSCustomObject 嚙罷嚙瘠嚙瘠

.PARAMETER Property
    嚙緯嚙緘嚙賤的嚙豎性名嚙誶（嚙緘 "SpotSell"嚙稷嚙瘠

.PARAMETER Period
    SMA 嚙踝蕭嚙踝蕭嚙璀嚙緩嚙稽 20嚙瘠

.PARAMETER StdDevMultiplier
    嚙請準差嚙踝蕭嚙複，嚙緩嚙稽 2.0嚙瘠

.OUTPUTS
    PSCustomObject @{
        Upper     = [decimal]  嚙磕嚙緙
        Middle    = [decimal]  嚙踝蕭嚙緙 (SMA20)
        Lower     = [decimal]  嚙磊嚙緙
        Current   = [decimal]  嚙諍前嚙踝蕭嚙踝蕭
        Bandwidth = [decimal]  嚙窮嚙箴 ((嚙磕嚙緙-嚙磊嚙緙)/嚙踝蕭嚙緙*100)
        PercentB  = [decimal]  %B ((嚙諍前-嚙磊嚙緙)/(嚙磕嚙緙-嚙磊嚙緙)*100)
    }嚙璀嚙踝蕭 $null嚙稽嚙踝蕭嚙踝蕭嚙踝蕭氶^嚙瘠

.EXAMPLE
    $bb = Get-BollingerBands -DataPoints $history -Property "SpotSell"
    # $bb.Upper 嚙踝蕭 32.80, $bb.Middle 嚙踝蕭 32.10, $bb.Lower 嚙踝蕭 31.40
#>
function Get-BollingerBands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Property,

        [int]$Period = 20,

        [decimal]$StdDevMultiplier = 2.0
    )

    # --- Collect valid (non-zero, non-null) values ---
    $validValues = [System.Collections.Generic.List[decimal]]::new()
    foreach ($pt in $DataPoints) {
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) {
            $validValues.Add([decimal]$val)
        }
    }
    $validArr = @($validValues)

    # --- Need at least $Period valid points ---
    if ($validArr.Count -lt $Period) {
        return $null
    }

    # --- Take the last $Period values ---
    $subset = $validArr[($validArr.Count - $Period)..($validArr.Count - 1)]

    # --- Middle band: SMA ---
    $sum = [decimal]0
    foreach ($v in $subset) {
        $sum += $v
    }
    $middle = $sum / $Period

    # --- Population standard deviation ---
    $sumSqDiff = [decimal]0
    foreach ($v in $subset) {
        $diff = $v - $middle
        $sumSqDiff += $diff * $diff
    }
    $variance = $sumSqDiff / $Period
    $stdDev = [math]::Sqrt([double]$variance)

    # --- Upper and Lower bands ---
    $upper = $middle + [decimal]$stdDev * $StdDevMultiplier
    $lower = $middle - [decimal]$stdDev * $StdDevMultiplier

    # --- Current value (last valid) ---
    $current = $validArr[-1]

    # --- Bandwidth: (Upper - Lower) / Middle * 100 ---
    $bandwidth = [decimal]0
    if ($middle -ne 0) {
        $bandwidth = ($upper - $lower) / $middle * [decimal]100
    }

    # --- PercentB: (Current - Lower) / (Upper - Lower) * 100 ---
    $percentB = [decimal]0
    $bandRange = $upper - $lower
    if ($bandRange -ne 0) {
        $percentB = ($current - $lower) / $bandRange * [decimal]100
    }
    else {
        # All values identical 嚙踝蕭 %B = 50 by convention
        $percentB = [decimal]50
    }

    return [PSCustomObject]@{
        Upper     = [math]::Round($upper, 4)
        Middle    = [math]::Round($middle, 4)
        Lower     = [math]::Round($lower, 4)
        Current   = [math]::Round($current, 4)
        Bandwidth = [math]::Round($bandwidth, 2)
        PercentB  = [math]::Round($percentB, 1)
    }
}

# =============================================================================
# Function: Get-RateRecommendation
# =============================================================================

<#
.SYNOPSIS
    嚙踝蕭X嚙踝蕭嚙踝蕭嚙踝蕭嚙踝蕭嚙璀嚙踝蕭嚙談買嚙皚/嚙踝蕭X/嚙稼嚙踝蕭嚙衝喉蕭C

.DESCRIPTION
    嚙踝蕭X嚙課佗蕭嚙箠嚙諄技術嚙踝蕭嚙請（SMA嚙畿RSI嚙畿MACD嚙畿嚙踝蕭嚙盤嚙緬嚙瘩嚙畿嚙褊歹蕭嚙踝蕭B嚙箠嚙褊度）嚙璀
    嚙緲嚙盤嚙稼嚙緞嚙踝蕭嚙踝蕭嚙緣嚙諄莎蕭嚙談綽蕭X嚙論率嚙踝蕭議嚙瘠嚙瘩嚙緯嚙諒橘蕭 SpotSell 嚙豎性計嚙踝蕭A
    CashSell 嚙瑾嚙踝蕭嚙踝蕭嚙磊嚙諸考。

    嚙踝蕭嚙踝蕭嚙範嚙踝蕭G-100 嚙踝蕭 +100
    - RSI: <30 = +25嚙稽嚙磕嚙踝蕭=嚙磋嚙皚嚙稷嚙璀30-40 = +10嚙璀40-60 = 0嚙璀60-70 = -10嚙璀>70 = -25嚙稽嚙磕嚙磋=嚙踝蕭X嚙稷
    - SMA 嚙談塚蕭: SMA5 > SMA20 = +15嚙稽嚙磕嚙褕）嚙璀SMA5 < SMA20 = -15嚙稽嚙磊嚙踝蕭嚙稷嚙璀嚙諛蛛蕭 = 0
    - MACD: 嚙磕嚙踝蕭 > 0 = +15嚙稽嚙篁嚙磐嚙稷嚙璀嚙磕嚙踝蕭 < 0 = -15嚙稽嚙踝蕭嚙磐嚙稷嚙璀嚙踝蕭嚙踝蕭s = 0
    - 嚙踝蕭嚙盤嚙緬嚙瘩: %B < 20 = +20嚙稽嚙踝蕭嚙踝蕭U嚙緙=嚙磋嚙皚嚙稷嚙璀%B > 80 = -20嚙稽嚙踝蕭嚙踝蕭W嚙緙=嚙踝蕭X嚙稷嚙璀嚙踝蕭l = 0
    - 嚙褊歹蕭嚙踝蕭: < 20 = +15嚙璀20-40 = +5嚙璀40-60 = 0嚙璀60-80 = -5嚙璀> 80 = -15
    - 嚙窮嚙箴: > 3 = +10嚙稽嚙踝蕭嚙箠嚙踝蕭=嚙踝蕭嚙罵嚙稷嚙璀< 1 = -5嚙稽嚙瘠嚙箠嚙踝蕭=嚙諂慎嚙稷

    嚙諒終恬蕭議嚙瘦
    - > 30  嚙踝蕭 嚙篌嚙瞑嚙踝蕭議嚙磋嚙皚
    - 10~30 嚙踝蕭 嚙踝蕭議嚙磋嚙皚
    - -10~10 嚙踝蕭 嚙稼嚙踝蕭
    - -30~-10 嚙踝蕭 嚙踝蕭議嚙稼嚙踝蕭/嚙踝蕭X
    - < -30 嚙踝蕭 嚙篌嚙瞑嚙踝蕭議嚙踝蕭X

.PARAMETER DataPoints
    嚙稽嚙緣嚙論率嚙豎性迎蕭 PSCustomObject 嚙罷嚙瘠嚙瘠

.PARAMETER Currency
    嚙踝蕭嚙瞌嚙瞇嚙碼嚙稽嚙緘 "USD"嚙稷嚙瘠

.PARAMETER Period
    嚙踝蕭嚙踝蕭嚙踝蕭嚙課（嚙緘 "3嚙諉歹蕭"嚙稷嚙瘠

.OUTPUTS
    PSCustomObject @｛
        Currency        = [string]
        Period          = [string]
        Score           = [int]
        Recommendation  = [string]
        RSI_Score       = [int]
        SMA_Score       = [int]
        MACD_Score      = [int]
        Bollinger_Score = [int]
        Percentile_Score = [int]
        Volatility_Score = [int]
        Details         = [hashtable]
        Summary         = [string]
        DetailedReport  = [string]
    ｝

.EXAMPLE
    $rec = Get-RateRecommendation -DataPoints $history -Currency "USD" -Period "3嚙諉歹蕭"
    $rec.Recommendation   # (L 'recommendation_buy')
    $rec.DetailedReport   # 嚙踝蕭嚙踝蕭嚙箱嚙賡中嚙踝蕭嚙踝蕭R嚙踝蕭嚙箠
#>
function Get-RateRecommendation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DataPoints,

        [Parameter(Mandatory)]
        [string]$Currency,

        [Parameter(Mandatory)]
        [string]$Period,

        [Parameter()]
        [ValidateSet('zh', 'en')]
        [string]$Lang
    )

    # Sync language for this module scope if explicitly provided
    if ($PSBoundParameters.ContainsKey('Lang')) {
        Set-Language $Lang
    }

    # --- Handle empty input ---
    if ($null -eq $DataPoints -or $DataPoints.Count -eq 0) {
        return [PSCustomObject]@{
            Currency         = $Currency
            Period           = $Period
            Score            = 0
            Recommendation   = L 'recommendation_hold'
            RSI_Score        = 0
            SMA_Score        = 0
            MACD_Score       = 0
            Bollinger_Score  = 0
            Percentile_Score = 0
            Volatility_Score = 0
            Details          = $null
            Summary          = L 'stats_no_data'
            DetailedReport   = L 'stats_no_data'
            TrendStrength    = L 'trend_strength_consolidate'
            RiskLevel        = L 'risk_low'
            CrossSignals     = $null
            ActionAdvice     = @()
        }
    }

    # --- Compute all indicators for SpotSell (primary) ---
    $primaryProp = "SpotSell"
    $secondaryProp = "CashSell"

    $rsiValue       = Get-RelativeStrengthIndex -DataPoints $DataPoints -Property $primaryProp -Period 14
    $sma5Value      = Get-SimpleMovingAverage -DataPoints $DataPoints -Property $primaryProp -Period 5
    $sma20Value     = Get-SimpleMovingAverage -DataPoints $DataPoints -Property $primaryProp -Period 20
    $percentileValue = Get-CurrentPosition -DataPoints $DataPoints -Property $primaryProp -Period 30
    $macdResult     = Get-MACD -DataPoints $DataPoints -Property $primaryProp
    $bollingerResult = Get-BollingerBands -DataPoints $DataPoints -Property $primaryProp

    # --- Get current SpotSell value ---
    $currentSpotSell = $null
    for ($i = $DataPoints.Count - 1; $i -ge 0; $i--) {
        $val = $DataPoints[$i].SpotSell
        if ($null -ne $val -and $val -ne 0) {
            $currentSpotSell = [decimal]$val
            break
        }
    }

    # --- Extract MACD details ---
    $macdLine    = $null
    $signalLine  = $null
    $histogram   = $null
    if ($null -ne $macdResult) {
        $macdLine   = $macdResult.MACDLine
        $signalLine = $macdResult.SignalLine
        $histogram  = $macdResult.Histogram
    }

    # --- Extract Bollinger details ---
    $bbUpper     = $null
    $bbMiddle    = $null
    $bbLower     = $null
    $bbPercentB  = $null
    $bbBandwidth = $null
    if ($null -ne $bollingerResult) {
        $bbUpper     = $bollingerResult.Upper
        $bbMiddle    = $bollingerResult.Middle
        $bbLower     = $bollingerResult.Lower
        $bbPercentB  = $bollingerResult.PercentB
        $bbBandwidth = $bollingerResult.Bandwidth
    }

    # ============================================
    # Scoring
    # ============================================

    # --- RSI Score ---
    $rsiScore = 0
    if ($null -ne $rsiValue) {
        $rsiRound = [math]::Round($rsiValue, 0)
        if ($rsiRound -lt 30) {
            $rsiScore = 25
        }
        elseif ($rsiRound -lt 40) {
            $rsiScore = 10
        }
        elseif ($rsiRound -le 60) {
            $rsiScore = 0
        }
        elseif ($rsiRound -le 70) {
            $rsiScore = -10
        }
        else {
            $rsiScore = -25
        }
    }

    # --- SMA Trend Score ---
    $smaScore = 0
    if ($null -ne $sma5Value -and $null -ne $sma20Value) {
        if ($sma5Value -gt $sma20Value) {
            $smaScore = 15
        }
        elseif ($sma5Value -lt $sma20Value) {
            $smaScore = -15
        }
        else {
            $smaScore = 0
        }
    }

    # --- MACD Score ---
    $macdScore = 0
    if ($null -ne $histogram) {
        # Use relative threshold to handle different currency rate magnitudes
        # (e.g., USD ~32 vs JPY ~0.22 vs IDR ~0.0002)
        if ($null -ne $currentSpotSell -and $currentSpotSell -ne 0) {
            $macdNorm = [decimal]$histogram / $currentSpotSell * 100
            if ($macdNorm -gt [decimal]0.01) {
                $macdScore = 15
            }
            elseif ($macdNorm -lt [decimal]-0.01) {
                $macdScore = -15
            }
            else {
                $macdScore = 0
            }
        }
        else {
            # Fallback to absolute threshold if current rate unavailable
            if ($histogram -gt [decimal]0.001) {
                $macdScore = 15
            }
            elseif ($histogram -lt [decimal]-0.001) {
                $macdScore = -15
            }
            else {
                $macdScore = 0
            }
        }
    }

    # --- Bollinger Score ---
    $bollingerScore = 0
    if ($null -ne $bbPercentB) {
        if ($bbPercentB -lt 20) {
            $bollingerScore = 20
        }
        elseif ($bbPercentB -gt 80) {
            $bollingerScore = -20
        }
        else {
            $bollingerScore = 0
        }
    }

    # --- Percentile Score ---
    $percentileScore = 0
    if ($null -ne $percentileValue) {
        $pctRound = [math]::Round($percentileValue, 0)
        if ($pctRound -lt 20) {
            $percentileScore = 15
        }
        elseif ($pctRound -lt 40) {
            $percentileScore = 5
        }
        elseif ($pctRound -le 60) {
            $percentileScore = 0
        }
        elseif ($pctRound -le 80) {
            $percentileScore = -5
        }
        else {
            $percentileScore = -15
        }
    }

    # --- Volatility (Bandwidth) Score ---
    $volatilityScore = 0
    if ($null -ne $bbBandwidth) {
        if ($bbBandwidth -gt 3) {
            $volatilityScore = 10
        }
        elseif ($bbBandwidth -lt 1) {
            $volatilityScore = -5
        }
        else {
            $volatilityScore = 0
        }
    }

    # ============================================
    # Cross-Signal Detection (嚙篁嚙踝蕭嚙確嚙踝蕭嚙瑾嚙踝蕭)
    # ============================================

    $bullSignals = 0
    $bearSignals = 0
    $crossSignalList = @()

    if ($rsiScore -gt 0) { $bullSignals++; $crossSignalList += (L 'signal_rsi_bullish') }
    if ($rsiScore -lt 0) { $bearSignals++; $crossSignalList += (L 'signal_rsi_bearish') }
    if ($smaScore -gt 0) { $bullSignals++; $crossSignalList += (L 'signal_sma_rising') }
    if ($smaScore -lt 0) { $bearSignals++; $crossSignalList += (L 'signal_sma_falling') }
    if ($macdScore -gt 0) { $bullSignals++; $crossSignalList += (L 'signal_macd_bullish') }
    if ($macdScore -lt 0) { $bearSignals++; $crossSignalList += (L 'signal_macd_bearish') }
    if ($bollingerScore -gt 0) { $bullSignals++; $crossSignalList += (L 'signal_bb_lower') }
    if ($bollingerScore -lt 0) { $bearSignals++; $crossSignalList += (L 'signal_bb_upper') }
    if ($percentileScore -gt 0) { $bullSignals++; $crossSignalList += (L 'signal_pct_low') }
    if ($percentileScore -lt 0) { $bearSignals++; $crossSignalList += (L 'signal_pct_high') }

    $crossSignalDirection = ""
    $crossSignalStrength = ""
    if ($bullSignals -ge 3 -and $bullSignals -gt $bearSignals) {
        $crossSignalDirection = (L 'signal_bullish')
        if ($bullSignals -ge 4) { $crossSignalStrength = (L 'strength_strong') } else { $crossSignalStrength = (L 'strength_weak') }
    }
    elseif ($bearSignals -ge 3 -and $bearSignals -gt $bullSignals) {
        $crossSignalDirection = (L 'signal_bearish')
        if ($bearSignals -ge 4) { $crossSignalStrength = (L 'strength_strong') } else { $crossSignalStrength = (L 'strength_weak') }
    }
    else {
        $crossSignalDirection = (L 'signal_diverged')
        $crossSignalStrength = ""
    }

    $crossSignals = [PSCustomObject]@{
        BullCount   = $bullSignals
        BearCount   = $bearSignals
        Direction    = $crossSignalDirection
        Strength     = $crossSignalStrength
        SignalList   = $crossSignalList
    }

    # ============================================
    # Trend Strength (嚙談勢強嚙踝蕭)
    # ============================================

    $trendStrengthRaw = 0

    # SMA trend component (-2 to +2)
    $smaComponent = 0
    if ($null -ne $sma5Value -and $null -ne $sma20Value -and $sma20Value -ne 0) {
        $smaDiff = [math]::Round(($sma5Value - $sma20Value) / $sma20Value * 100, 2)
        if ($smaDiff -gt 1.0) { $smaComponent = 2 }
        elseif ($smaDiff -gt 0.3) { $smaComponent = 1 }
        elseif ($smaDiff -lt -1.0) { $smaComponent = -2 }
        elseif ($smaDiff -lt -0.3) { $smaComponent = -1 }
        else { $smaComponent = 0 }
    }

    # MACD histogram component (-2 to +2)
    $macdComponent = 0
    if ($null -ne $histogram -and $null -ne $currentSpotSell -and $currentSpotSell -ne 0) {
        $macdNorm = [math]::Round([decimal]$histogram / $currentSpotSell * 100, 4)
        if ($macdNorm -gt 0.05) { $macdComponent = 2 }
        elseif ($macdNorm -gt 0.01) { $macdComponent = 1 }
        elseif ($macdNorm -lt -0.05) { $macdComponent = -2 }
        elseif ($macdNorm -lt -0.01) { $macdComponent = -1 }
        else { $macdComponent = 0 }
    }

    # Bollinger bandwidth component (0 or 嚙踝蕭1)
    $bbComponent = 0
    if ($null -ne $bbBandwidth) {
        if ($bbBandwidth -ge 4) { $bbComponent = 1 }
        elseif ($bbBandwidth -le 1) { $bbComponent = -1 }
    }

    $trendStrengthRaw = $smaComponent + $macdComponent + $bbComponent

    $trendStrength = ""
    if ($trendStrengthRaw -ge 4) { $trendStrength = (L 'trend_strength_bull_strong') }
    elseif ($trendStrengthRaw -ge 2) { $trendStrength = (L 'trend_strength_bull_weak') }
    elseif ($trendStrengthRaw -ge -1 -and $trendStrengthRaw -le 1) { $trendStrength = (L 'trend_strength_consolidate') }
    elseif ($trendStrengthRaw -ge -3) { $trendStrength = (L 'trend_strength_bear_weak') }
    else { $trendStrength = (L 'trend_strength_bear_strong') }

    # ============================================
    # Risk Level (嚙踝蕭嚙瘢嚙踝蕭嚙踝蕭)
    # ============================================

    $riskLevel = L 'risk_low'
    $riskPoints = 0
    $riskReasonParts = @()

    # Volatility contribution
    if ($null -ne $bbBandwidth) {
        if ($bbBandwidth -ge 5) { $riskPoints += 3 }
        elseif ($bbBandwidth -ge 3) { $riskPoints += 2 }
        elseif ($bbBandwidth -ge 1.5) { $riskPoints += 1 }
    }

    # RSI extreme contribution
    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        if ($rsiInt -le 20 -or $rsiInt -ge 80) { $riskPoints += 3 }
        elseif ($rsiInt -le 30 -or $rsiInt -ge 70) { $riskPoints += 2 }
        elseif ($rsiInt -le 35 -or $rsiInt -ge 65) { $riskPoints += 1 }
    }

    # Percentile extreme contribution
    if ($null -ne $percentileValue) {
        $pctRound2 = [int][math]::Round($percentileValue)
        if ($pctRound2 -le 10 -or $pctRound2 -ge 90) { $riskPoints += 1 }
    }

    if ($riskPoints -ge 5) { $riskLevel = (L 'risk_high') }
    elseif ($riskPoints -ge 3) { $riskLevel = (L 'risk_medium') }
    else { $riskLevel = (L 'risk_low') }

    # ============================================
    # Action Advice (嚙豬作嚙踝蕭議)
    # ============================================

    $actionAdvice = @()

    if ($null -ne $rsiValue) {
        $rsiInt2 = [int][math]::Round($rsiValue)
        if ($rsiInt2 -lt 30) {
            $actionAdvice += (L 'advice_rsi_oversold')
        }
        elseif ($rsiInt2 -gt 70) {
            $actionAdvice += (L 'advice_rsi_overbought')
        }
        elseif ($rsiInt2 -ge 30 -and $rsiInt2 -le 40) {
            $actionAdvice += (L 'advice_rsi_weak_oversold')
        }
        elseif ($rsiInt2 -ge 60 -and $rsiInt2 -le 70) {
            $actionAdvice += (L 'advice_rsi_weak_obought')
        }
    }

    if ($null -ne $sma5Value -and $null -ne $sma20Value) {
        $smaDiff2 = $sma5Value - $sma20Value
        if ($smaDiff2 -gt 0) {
            $actionAdvice += (L 'advice_sma_death_cross')
        }
        elseif ($smaDiff2 -lt 0) {
            $actionAdvice += (L 'advice_sma_golden_cross')
        }
        else {
            $actionAdvice += (L 'advice_sma_near')
        }
    }

    if ($null -ne $histogram) {
        if ($histogram -gt 0 -and $null -ne $macdLine -and $null -ne $signalLine) {
            if ($macdLine -gt $signalLine) {
                $actionAdvice += (L 'advice_macd_bull_align')
            }
        }
        elseif ($histogram -lt 0 -and $null -ne $macdLine -and $null -ne $signalLine) {
            if ($macdLine -lt $signalLine) {
                $actionAdvice += (L 'advice_macd_bear_align')
            }
        }
    }

    if ($null -ne $bbPercentB) {
        if ($bbPercentB -lt 20 -and $null -ne $bbLower) {
            $actionAdvice += (L 'advice_bb_lower_break' $bbLower)
        }
        elseif ($bbPercentB -gt 80 -and $null -ne $bbUpper) {
            $actionAdvice += (L 'advice_bb_upper_break' $bbUpper)
        }
    }

    # Limit to at most 3 advice items
    if ($actionAdvice.Count -gt 3) {
        $actionAdvice = @($actionAdvice[0], $actionAdvice[1], $actionAdvice[2])
    }

    # --- Total score ---
    $totalScore = $rsiScore + $smaScore + $macdScore + $bollingerScore + $percentileScore + $volatilityScore

    # --- Score display strings (for report formatting) ---
    $trendScoreStr = if ($smaScore -ge 0) { "+$smaScore" } else { "$smaScore" }
    $rsiScoreStr   = if ($rsiScore -ge 0) { "+$rsiScore" } else { "$rsiScore" }
    $macdScoreStr  = if ($macdScore -ge 0) { "+$macdScore" } else { "$macdScore" }
    $bbScoreStr    = if ($bollingerScore -ge 0) { "+$bollingerScore" } else { "$bollingerScore" }
    $pctScoreStr   = if ($percentileScore -ge 0) { "+$percentileScore" } else { "$percentileScore" }
    $volScoreStr   = if ($volatilityScore -ge 0) { "+$volatilityScore" } else { "$volatilityScore" }

    # --- Determine recommendation ---
    $recommendation = ""
    if ($totalScore -gt 30) {
        $recommendation = (L 'recommendation_buy_strong')
    }
    elseif ($totalScore -ge 10) {
        $recommendation = (L 'recommendation_buy')
    }
    elseif ($totalScore -gt -10) {
        $recommendation = (L 'recommendation_hold')
    }
    elseif ($totalScore -ge -30) {
        $recommendation = (L 'recommendation_hold_sell')
    }
    else {
        $recommendation = (L 'recommendation_sell_strong')
    }

    # --- Build Details hashtable ---
    $details = @{
        RSI              = $rsiValue
        SMA5             = $sma5Value
        SMA20            = $sma20Value
        MACD_Histogram   = $histogram
        Bollinger_PercentB = $bbPercentB
        Percentile_30d   = $percentileValue
        Bandwidth        = $bbBandwidth
    }

    # ============================================
    # Build Summary (3-5 sentences, Traditional Chinese)
    # ============================================
    $summaryParts = @()

    # Sentence 1: Current rate and percentile
    if ($null -ne $currentSpotSell -and $null -ne $percentileValue) {
        $pctInt = [int][math]::Round($percentileValue)
        if ($pctInt -le 20) { $summaryParts += (L 'rec_pos_near_low2' $Currency $currentSpotSell $pctInt) }
        elseif ($pctInt -ge 80) { $summaryParts += (L 'rec_pos_near_high2' $Currency $currentSpotSell $pctInt) }
        elseif ($pctInt -le 40) { $summaryParts += (L 'rec_pos_low' $Currency $currentSpotSell $pctInt) }
        elseif ($pctInt -ge 60) { $summaryParts += (L 'rec_pos_high' $Currency $currentSpotSell $pctInt) }
        else { $summaryParts += (L 'rec_pos_neutral' $Currency $currentSpotSell $pctInt) }
    }

    # Sentence 2: RSI
    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        if ($rsiInt -lt 30) {
            $summaryParts += (L 'rec_rsi_oversold' $rsiInt)
        }
        elseif ($rsiInt -gt 70) {
            $summaryParts += (L 'rec_rsi_overbought' $rsiInt)
        }
        else {
            $summaryParts += (L 'rec_rsi_neutral' $rsiInt)
        }
    }

    # Sentence 3: MACD
    if ($null -ne $histogram) {
        if ($histogram -gt 0) {
            $summaryParts += (L 'rec_macd_positive')
        }
        elseif ($histogram -lt 0) {
            $summaryParts += (L 'rec_macd_negative')
        }
        else {
            $summaryParts += (L 'macd_neutral')
        }
    }

    # Sentence 4: Bollinger
    if ($null -ne $bbPercentB) {
        $pbInt = [int][math]::Round($bbPercentB)
        if ($bbPercentB -lt 20) {
            $summaryParts += (L 'rec_bb_near_lower' $pbInt)
        }
        elseif ($bbPercentB -gt 80) {
            $summaryParts += (L 'rec_bb_near_upper' $pbInt)
        }
        else {
            $summaryParts += (L 'bb_middle' $pbInt)
        }
    }

    # Sentence 5: Final recommendation
    $scoreStr = ""
    if ($totalScore -ge 0) { $scoreStr = "+$totalScore" } else { $scoreStr = "$totalScore" }
    $summaryParts += (L 'rec_final_format' $scoreStr $recommendation)

    $summary = $summaryParts -join ''

    # ============================================
    # Build DetailedReport (multi-line, localized)
    # ============================================

    $lines = @()
    $lines += (L 'report_header_line')
    $lines += (L 'report_header' $Currency (Get-PeriodDisplay $Period))
    $lines += (L 'report_header_line')
    $lines += ''

    # Score header
    $lines += (L 'report_score_header' $scoreStr $recommendation)
    $lines += ''
    $lines += (L 'report_header_line')
    $lines += (L 'report_tech_header')
    $lines += (L 'report_header_line')
    $lines += ''

    # --- Trend indicators ---
    $lines += (L 'report_trend_header')
    $sma5Str  = if ($null -ne $sma5Value)  { "$sma5Value" } else { 'N/A' }
    $sma20Str = if ($null -ne $sma20Value) { "$sma20Value" } else { 'N/A' }
    $lines += (L 'sma_values' $sma5Str $sma20Str)

    if ($null -ne $sma5Value -and $null -ne $sma20Value) {
        if ($sma5Value -gt $sma20Value) {
            $trendLabel = (L 'trend_up')
        }
        elseif ($sma5Value -lt $sma20Value) {
            $trendLabel = (L 'trend_down')
        }
        else {
            $trendLabel = (L 'trend_consolidate')
        }
        $lines += (L 'sma_trend_format' $trendLabel $trendScoreStr)
    }
    $lines += ''

    # --- Momentum indicators ---
    $lines += (L 'report_momentum_header')
    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        if ($rsiInt -lt 30) { $rsiLabel = (L 'rsi_oversold') }
        elseif ($rsiInt -gt 70) { $rsiLabel = (L 'rsi_overbought') }
        else { $rsiLabel = (L 'rsi_label_neutral') }
        $lines += (L 'rsi_format_detail' $rsiInt $rsiLabel $rsiScoreStr)
    }
    else {
        $lines += (L 'percentile_na')
    }

    $macdLineStr   = if ($null -ne $macdLine)   { "$macdLine" } else { 'N/A' }
    $signalLineStr = if ($null -ne $signalLine)  { "$signalLine" } else { 'N/A' }
    $histogramStr  = if ($null -ne $histogram)   { "$histogram" } else { 'N/A' }
    $lines += (L 'macd_values' $macdLineStr $signalLineStr $histogramStr)

    if ($null -ne $histogram) {
        if ($histogram -gt [decimal]0.001) {
            $macdLabel = (L 'macd_bullish')
        }
        elseif ($histogram -lt [decimal]-0.001) {
            $macdLabel = (L 'macd_bearish')
        }
        else {
            $macdLabel = (L 'macd_neutral')
        }
        $lines += (L 'macd_judgement' $macdLabel $macdScoreStr)
    }
    $lines += ''

    # --- Volatility indicators ---
    $lines += (L 'report_volatility_header')
    $bbUpperStr  = if ($null -ne $bbUpper)  { "$bbUpper" } else { 'N/A' }
    $bbMiddleStr = if ($null -ne $bbMiddle) { "$bbMiddleStr" } else { 'N/A' }
    $bbLowerStr  = if ($null -ne $bbLower)  { "$bbLower" } else { 'N/A' }
    $lines += (L 'bb_values' $bbUpperStr $bbMiddleStr $bbLowerStr)

    if ($null -ne $bbPercentB) {
        $pbInt = [int][math]::Round($bbPercentB)
        if ($bbPercentB -lt 20) { $pbLabel = (L 'bb_near_lower') }
        elseif ($bbPercentB -gt 80) { $pbLabel = (L 'bb_near_upper') }
        else { $pbLabel = (L 'bb_middle') }
        $lines += (L 'percentb_format' $pbInt $pbLabel $bbScoreStr)
    }

    if ($null -ne $bbBandwidth) {
        $bwStr = [math]::Round($bbBandwidth, 1)
        if ($bbBandwidth -gt 3) { $bwLabel = (L 'bw_high') }
        elseif ($bbBandwidth -lt 1) { $bwLabel = (L 'bw_low') }
        else { $bwLabel = (L 'bw_normal') }
        $lines += (L 'bandwidth_format' $bwStr $bwLabel $volScoreStr)
    }
    $lines += ''

    # --- Position indicators ---
    $lines += (L 'report_position_header')
    if ($null -ne $percentileValue) {
        $pctInt = [int][math]::Round($percentileValue)
        if ($pctInt -le 20) { $pctPosDesc = (L 'pct_pos_low') }
        elseif ($pctInt -ge 80) { $pctPosDesc = (L 'pct_pos_high') }
        else { $pctPosDesc = (L 'pct_pos_middle') }
        $lines += (L 'percentile_detail' $pctInt $pctPosDesc $pctScoreStr)
    }
    else {
        $lines += (L 'percentile_na')
    }
    $lines += ''

    # --- Trend Strength & Risk section ---
    $lines += (L 'report_header_line')
    $lines += (L 'report_risk_header')
    $lines += (L 'report_header_line')
    $lines += ''

    $lines += (L 'trend_strength_fmt' $trendStrength)
    $lines += (L 'trend_components')
    $riskIcon = ''
    if ($riskLevel -eq (L 'risk_high')) { $riskIcon = '🔴' }
    elseif ($riskLevel -eq (L 'risk_medium')) { $riskIcon = '🟡' }
    else { $riskIcon = '🟢' }
    if ($crossSignalDirection -eq (L 'signal_bullish')) { $csEmoji = '🟢' } else { $csEmoji = '🔴' }
    $lines += ''
    $lines += (L 'risk_fmt') -f $riskIcon, $riskLevel
    if ($riskReasonParts.Count -gt 0) {
        $lines += (L 'risk_reason_format') -f ($riskReasonParts -join "??")
    }
    else {
        $lines += (L 'risk_reason_normal')
    }
    $lines += ''

    # --- Cross-Signal Confirmation section ---
    $lines += (L 'report_header_line')
    $lines += (L 'report_cross_header')
    $lines += (L 'report_header_line')
    $lines += ''

    if ($crossSignalDirection -eq (L 'signal_diverged')) {
        $lines += (L 'signal_diverged_fmt' $bullSignals $bearSignals)
        $lines += (L 'signal_diverged_hint')
    }
    else {
        if ($crossSignalDirection -eq (L 'signal_bullish')) { $csEmoji = '🟢' } else { $csEmoji = '🔴' }
        $csStr = ''
        if ($crossSignalStrength -eq (L 'strength_strong')) { $csStr = (L 'consensus_desc_strong') }
        else { $csStr = (L 'consensus_desc_weak') }
        $lines += (L 'signal_consensus_fmt') -f $csEmoji, $crossSignalDirection, $csStr
        $lines += (L 'signal_counts_fmt' $bullSignals $bearSignals)
        if ($crossSignalList.Count -gt 0) {
            $lines += (L 'signal_list_fmt') -f ($crossSignalList -join "??")
        }
        if ($crossSignalStrength -eq (L 'strength_strong')) {
            if ($crossSignalDirection -eq (L 'signal_bullish')) {
                $lines += (L 'signal_strong_bull')
            }
            else {
                $lines += (L 'signal_strong_bear')
            }
        }
        else {
            $lines += (L 'signal_weak_hint')
        }
    }
    $lines += ''

    # --- Final recommendation section ---
    $lines += (L 'report_header_line')
    $lines += (L 'report_rec_header')
    $lines += (L 'report_header_line')
    $lines += ''

    # Build narrative recommendation
    $narrativeParts = @()

    if ($null -ne $currentSpotSell -and $null -ne $percentileValue) {
        $pctInt = [int][math]::Round($percentileValue)
        if ($pctInt -le 20) { $narrativeParts += (L 'rec_pos_near_low2' $Currency $currentSpotSell $pctInt) }
        elseif ($pctInt -ge 80) { $narrativeParts += (L 'rec_pos_near_high2' $Currency $currentSpotSell $pctInt) }
        elseif ($pctInt -le 40) { $narrativeParts += (L 'rec_pos_low' $Currency $currentSpotSell $pctInt) }
        elseif ($pctInt -ge 60) { $narrativeParts += (L 'rec_pos_high' $Currency $currentSpotSell $pctInt) }
        else { $narrativeParts += (L 'rec_pos_neutral' $Currency $currentSpotSell $pctInt) }
    }

    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        if ($rsiInt -lt 30) { $narrativeParts += (L 'rec_rsi_oversold' $rsiInt) }
        elseif ($rsiInt -gt 70) { $narrativeParts += (L 'rec_rsi_overbought' $rsiInt) }
        else { $narrativeParts += (L 'rec_rsi_neutral' $rsiInt) }
    }

    if ($null -ne $histogram) {
        if ($histogram -gt 0) { $narrativeParts += (L 'rec_macd_positive') }
        else { $narrativeParts += (L 'rec_macd_negative') }
    }

    if ($null -ne $bbPercentB) {
        $pbInt = [int][math]::Round($bbPercentB)
        if ($bbPercentB -lt 20) { $narrativeParts += (L 'rec_bb_near_lower' $pbInt) }
        elseif ($bbPercentB -gt 80) { $narrativeParts += (L 'rec_bb_near_upper' $pbInt) }
    }

    if ($crossSignalDirection -ne (L 'signal_diverged') -and $crossSignalStrength -eq (L 'strength_strong')) {
        if ($crossSignalDirection -eq (L 'signal_bullish')) { $narrativeParts += (L 'rec_consensus_bull') }
        else { $narrativeParts += (L 'rec_consensus_bear') }
    }

    $narrativeParts += (L 'rec_final_format' $scoreStr $recommendation)

    # Append suitability note based on recommendation
    if ($totalScore -gt 10) { $narrativeParts += (L 'rec_suit_buy') }
    elseif ($totalScore -lt -10) { $narrativeParts += (L 'rec_suit_sell') }
    else { $narrativeParts += (L 'rec_suit_hold') }

    $lines += ($narrativeParts -join '')
    $lines += ''

    # --- Action Advice section ---
    if ($actionAdvice.Count -gt 0) {
        $lines += ''
        $lines += (L 'action_advice_header')
        foreach ($advice in $actionAdvice) {
            $lines += (L 'action_bullet_format' $advice)
        }
    }

    $lines += ''
    $lines += (L 'risk_disclaimer')

    $detailedReport = $lines -join "`n"

    # --- Return result ---
    return [PSCustomObject]@{
        Currency         = $Currency
        Period           = $Period
        Score            = $totalScore
        Recommendation   = $recommendation
        RSI_Score        = $rsiScore
        SMA_Score        = $smaScore
        MACD_Score       = $macdScore
        Bollinger_Score  = $bollingerScore
        Percentile_Score = $percentileScore
        Volatility_Score = $volatilityScore
        Details          = $details
        Summary          = $summary
        DetailedReport   = $detailedReport
        TrendStrength    = $trendStrength
        RiskLevel        = $riskLevel
        CrossSignals     = $crossSignals
        ActionAdvice     = $actionAdvice
    }
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Get-RateStatistics',
    'Get-SimpleMovingAverage',
    'Get-RelativeStrengthIndex',
    'Get-RecentHighLow',
    'Get-CurrentPosition',
    'Get-MACD',
    'Get-BollingerBands',
    'Get-RateRecommendation'
)


