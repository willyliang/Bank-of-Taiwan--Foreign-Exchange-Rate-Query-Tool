# =============================================================================
# RateAnalyzer.psm1
# FX Rate Statistical Analysis Module
# Computes SMA, RSI, recent high/low, and current percentile indicators.
# =============================================================================

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
    # $hl.High → 32.50,  $hl.Low → 31.80
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
    or if all values are identical (range is zero and current ≠ high/low).

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
        # All values are identical — percentile is 50 by convention
        return [decimal]50
    }

    $percentile = [decimal](($current - $low) / $range) * [decimal]100

    return [math]::Round($percentile, 1)
}

# =============================================================================
# Function: Get-RateStatistics  (PRIVATE helper – not exported)
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
    The period label (e.g. "3個月", "本日").

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
    - Trend                 : "上升", "下降", or "盤整"
    - Summary               : Short Traditional Chinese summary

.EXAMPLE
    $stats = Get-RateStatistics -DataPoints $cachedData -Currency "USD" -Period "3個月"
    $stats.Summary
    # "目前即期賣出匯率 32.15 位於近30日第 25 百分位，接近低點。SMA5 > SMA20，短期趨勢上升。RSI=35，偏弱。"
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
        [string]$Period
    )

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
            Summary                = "無資料，無法計算統計指標。"
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
    $trend = "盤整"
    $spotSellSma5  = $sma5['SpotSell']
    $spotSellSma20 = $sma20['SpotSell']

    if ($null -ne $spotSellSma5 -and $null -ne $spotSellSma20) {
        if ($spotSellSma5 -gt $spotSellSma20) {
            $trend = "上升"
        }
        elseif ($spotSellSma5 -lt $spotSellSma20) {
            $trend = "下降"
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
# Function: Build-Summary  (PRIVATE helper – not exported)
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
    The trend string: "上升", "下降", or "盤整".

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

        [string]$Trend = "盤整",

        [decimal]$SpotSellRsi = $null
    )

    $parts = @()

    # --- Part 1: Current rate and percentile ---
    if ($null -ne $CurrentSpotSell -and $null -ne $SpotSellPercentile) {
        $pctInt = [int][math]::Round($SpotSellPercentile)
        $positionDesc = ""
        if ($pctInt -le 20) {
            $positionDesc = "接近低點"
        }
        elseif ($pctInt -ge 80) {
            $positionDesc = "接近高點"
        }
        elseif ($pctInt -le 40) {
            $positionDesc = "偏弱"
        }
        elseif ($pctInt -ge 60) {
            $positionDesc = "偏強"
        }
        else {
            $positionDesc = "中性"
        }

        $parts += "目前即期賣出匯率 $CurrentSpotSell 位於近30日第 $pctInt 百分位，$positionDesc。"
    }
    elseif ($null -ne $CurrentSpotSell) {
        $parts += "目前即期賣出匯率 $CurrentSpotSell。"
    }

    # --- Part 2: Trend ---

    switch ($Trend) {
        "上升" { $parts += "SMA5 > SMA20，短期趨勢上升。" }
        "下降" { $parts += "SMA5 < SMA20，短期趨勢下降。" }
        "盤整" { $parts += "SMA5 ≈ SMA20，短期趨勢盤整。" }
    }

    # --- Part 3: RSI ---
    if ($null -ne $SpotSellRsi) {
        $rsiInt = [int][math]::Round($SpotSellRsi)
        $rsiDesc = ""
        if ($rsiInt -ge 70) {
            $rsiDesc = "偏強"
        }
        elseif ($rsiInt -le 30) {
            $rsiDesc = "偏弱"
        }
        else {
            $rsiDesc = "中性"
        }
        $parts += "RSI=$rsiInt，$rsiDesc。"
    }

    return ($parts -join '')
}

# =============================================================================
# Function: Get-MACD
# =============================================================================

<#
.SYNOPSIS
    計算移動平均收斂散度 (MACD) 指標。

.DESCRIPTION
    根據快速 EMA 與慢速 EMA 的差值計算 MACD 線，再對 MACD 線取
    EMA 得到訊號線，兩者之差即為柱狀圖 (Histogram)。
    僅使用非零、非空值的資料點進行計算。若有效資料點不足，回傳 $null。

    EMA 計算方式：乘數 = 2/(期間+1)；EMA = (收盤 - 前一EMA) * 乘數 + 前一EMA

.PARAMETER DataPoints
    包含匯率屬性的 PSCustomObject 陣列（如 CashBuy、CashSell、SpotBuy、SpotSell）。

.PARAMETER Property
    要計算的屬性名稱（如 "SpotSell"）。

.PARAMETER FastPeriod
    快速 EMA 期間，預設 12。

.PARAMETER SlowPeriod
    慢速 EMA 期間，預設 26。

.PARAMETER SignalPeriod
    訊號線 EMA 期間，預設 9。

.OUTPUTS
    PSCustomObject @{ MACDLine = [decimal]; SignalLine = [decimal]; Histogram = [decimal] }，
    或 $null（資料不足時）。

.EXAMPLE
    $macd = Get-MACD -DataPoints $history -Property "SpotSell"
    # $macd.MACDLine → -0.05, $macd.SignalLine → -0.12, $macd.Histogram → 0.07
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
    計算布林通道 (Bollinger Bands) 指標。

.DESCRIPTION
    根據最近 N 個有效資料點的 SMA 作為中軌，以母體標準差乘以
    倍數計算上軌與下軌。同時計算帶寬 (Bandwidth) 與 %B 指標。
    僅使用非零、非空值的資料點。若有效資料點不足，回傳 $null。

.PARAMETER DataPoints
    包含匯率屬性的 PSCustomObject 陣列。

.PARAMETER Property
    要計算的屬性名稱（如 "SpotSell"）。

.PARAMETER Period
    SMA 期間，預設 20。

.PARAMETER StdDevMultiplier
    標準差倍數，預設 2.0。

.OUTPUTS
    PSCustomObject @{
        Upper     = [decimal]  上軌
        Middle    = [decimal]  中軌 (SMA20)
        Lower     = [decimal]  下軌
        Current   = [decimal]  目前價格
        Bandwidth = [decimal]  帶寬 ((上軌-下軌)/中軌*100)
        PercentB  = [decimal]  %B ((目前-下軌)/(上軌-下軌)*100)
    }，或 $null（資料不足時）。

.EXAMPLE
    $bb = Get-BollingerBands -DataPoints $history -Property "SpotSell"
    # $bb.Upper → 32.80, $bb.Middle → 32.10, $bb.Lower → 31.40
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
        # All values identical → %B = 50 by convention
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
    綜合評分引擎，產生買入/賣出/觀望建議。

.DESCRIPTION
    整合所有可用技術指標（SMA、RSI、MACD、布林通道、百分位、波動度），
    透過加權評分系統產生綜合匯率建議。主要依據 SpotSell 屬性計算，
    CashSell 作為輔助參考。

    評分範圍：-100 到 +100
    - RSI: <30 = +25（超賣=買入），30-40 = +10，40-60 = 0，60-70 = -10，>70 = -25（超買=賣出）
    - SMA 趨勢: SMA5 > SMA20 = +15（上升），SMA5 < SMA20 = -15（下降），相等 = 0
    - MACD: 柱狀 > 0 = +15（多頭），柱狀 < 0 = -15（空頭），接近零 = 0
    - 布林通道: %B < 20 = +20（接近下軌=買入），%B > 80 = -20（接近上軌=賣出），其餘 = 0
    - 百分位: < 20 = +15，20-40 = +5，40-60 = 0，60-80 = -5，> 80 = -15
    - 帶寬: > 3 = +10（高波動=機會），< 1 = -5（低波動=謹慎）

    最終建議：
    - > 30  → 強烈建議買入
    - 10~30 → 建議買入
    - -10~10 → 觀望
    - -30~-10 → 建議觀望/賣出
    - < -30 → 強烈建議賣出

.PARAMETER DataPoints
    包含匯率屬性的 PSCustomObject 陣列。

.PARAMETER Currency
    幣別代碼（如 "USD"）。

.PARAMETER Period
    期間標籤（如 "3個月"）。

.OUTPUTS
    PSCustomObject @{
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
    }

.EXAMPLE
    $rec = Get-RateRecommendation -DataPoints $history -Currency "USD" -Period "3個月"
    $rec.Recommendation   # "建議買入"
    $rec.DetailedReport   # 完整繁體中文分析報告
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
        [string]$Period
    )

    # --- Handle empty input ---
    if ($null -eq $DataPoints -or $DataPoints.Count -eq 0) {
        return [PSCustomObject]@{
            Currency         = $Currency
            Period           = $Period
            Score            = 0
            Recommendation   = "觀望"
            RSI_Score        = 0
            SMA_Score        = 0
            MACD_Score       = 0
            Bollinger_Score  = 0
            Percentile_Score = 0
            Volatility_Score = 0
            Details          = $null
            Summary          = "無資料，無法產生建議。"
            DetailedReport   = "無資料，無法產生分析報告。"
            TrendStrength    = "盤整"
            RiskLevel        = "低"
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
    # Cross-Signal Detection (多重訊號共識)
    # ============================================

    $bullSignals = 0
    $bearSignals = 0
    $crossSignalList = @()

    if ($rsiScore -gt 0) { $bullSignals++; $crossSignalList += "RSI 偏多" }
    if ($rsiScore -lt 0) { $bearSignals++; $crossSignalList += "RSI 偏空" }
    if ($smaScore -gt 0) { $bullSignals++; $crossSignalList += "SMA 上升" }
    if ($smaScore -lt 0) { $bearSignals++; $crossSignalList += "SMA 下降" }
    if ($macdScore -gt 0) { $bullSignals++; $crossSignalList += "MACD 多頭" }
    if ($macdScore -lt 0) { $bearSignals++; $crossSignalList += "MACD 空頭" }
    if ($bollingerScore -gt 0) { $bullSignals++; $crossSignalList += "布林接近下軌" }
    if ($bollingerScore -lt 0) { $bearSignals++; $crossSignalList += "布林接近上軌" }
    if ($percentileScore -gt 0) { $bullSignals++; $crossSignalList += "百分位偏低" }
    if ($percentileScore -lt 0) { $bearSignals++; $crossSignalList += "百分位偏高" }

    $crossSignalDirection = ""
    $crossSignalStrength = ""
    if ($bullSignals -ge 3 -and $bullSignals -gt $bearSignals) {
        $crossSignalDirection = "看多"
        if ($bullSignals -ge 4) { $crossSignalStrength = "強" } else { $crossSignalStrength = "弱" }
    }
    elseif ($bearSignals -ge 3 -and $bearSignals -gt $bullSignals) {
        $crossSignalDirection = "看空"
        if ($bearSignals -ge 4) { $crossSignalStrength = "強" } else { $crossSignalStrength = "弱" }
    }
    else {
        $crossSignalDirection = "分歧"
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
    # Trend Strength (趨勢強度)
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

    # Bollinger bandwidth component (0 or ±1)
    $bbComponent = 0
    if ($null -ne $bbBandwidth) {
        if ($bbBandwidth -ge 4) { $bbComponent = 1 }
        elseif ($bbBandwidth -le 1) { $bbComponent = -1 }
    }

    $trendStrengthRaw = $smaComponent + $macdComponent + $bbComponent

    $trendStrength = ""
    if ($trendStrengthRaw -ge 4) { $trendStrength = "強勢多頭" }
    elseif ($trendStrengthRaw -ge 2) { $trendStrength = "弱勢多頭" }
    elseif ($trendStrengthRaw -ge -1 -and $trendStrengthRaw -le 1) { $trendStrength = "盤整" }
    elseif ($trendStrengthRaw -ge -3) { $trendStrength = "弱勢空頭" }
    else { $trendStrength = "強勢空頭" }

    # ============================================
    # Risk Level (風險等級)
    # ============================================

    $riskLevel = "低"
    $riskPoints = 0

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

    if ($riskPoints -ge 5) { $riskLevel = "高" }
    elseif ($riskPoints -ge 3) { $riskLevel = "中" }
    else { $riskLevel = "低" }

    # ============================================
    # Action Advice (操作建議)
    # ============================================

    $actionAdvice = @()

    if ($null -ne $rsiValue) {
        $rsiInt2 = [int][math]::Round($rsiValue)
        if ($rsiInt2 -lt 30) {
            $actionAdvice += "若 RSI 回升至 40 以上，可考慮分批進場買入"
        }
        elseif ($rsiInt2 -gt 70) {
            $actionAdvice += "若 RSI 回落至 60 以下，可考慮分批賣出"
        }
        elseif ($rsiInt2 -ge 30 -and $rsiInt2 -le 40) {
            $actionAdvice += "RSI 偏弱但未極端超賣，觀察是否進一步跌破 30 形成更強買入訊號"
        }
        elseif ($rsiInt2 -ge 60 -and $rsiInt2 -le 70) {
            $actionAdvice += "RSI 偏強但未極端超買，觀察是否進一步突破 70 形成更強賣出訊號"
        }
    }

    if ($null -ne $sma5Value -and $null -ne $sma20Value) {
        $smaDiff2 = $sma5Value - $sma20Value
        if ($smaDiff2 -gt 0) {
            $actionAdvice += "關注 SMA5 是否向下跌穿 SMA20 形成死亡交叉，作為趨勢反轉警訊"
        }
        elseif ($smaDiff2 -lt 0) {
            $actionAdvice += "關注 SMA5 是否向上穿越 SMA20 形成黃金交叉，作為趨勢反轉訊號"
        }
        else {
            $actionAdvice += "SMA5 與 SMA20 接近，留意即將出現的方向突破"
        }
    }

    if ($null -ne $histogram) {
        if ($histogram -gt 0 -and $null -ne $macdLine -and $null -ne $signalLine) {
            if ($macdLine -gt $signalLine) {
                $actionAdvice += "MACD 多頭排列中，若柱狀圖縮小需留意動能減弱"
            }
        }
        elseif ($histogram -lt 0 -and $null -ne $macdLine -and $null -ne $signalLine) {
            if ($macdLine -lt $signalLine) {
                $actionAdvice += "MACD 空頭排列中，若柱狀圖縮小需留意跌勢趨緩"
            }
        }
    }

    if ($null -ne $bbPercentB) {
        if ($bbPercentB -lt 20 -and $null -ne $bbLower) {
            $actionAdvice += "價格接近布林下軌 ($bbLower)，若跌破且帶寬擴大，恐加速下跌"
        }
        elseif ($bbPercentB -gt 80 -and $null -ne $bbUpper) {
            $actionAdvice += "價格接近布林上軌 ($bbUpper)，若突破且帶寬擴大，可能續強"
        }
    }

    # Limit to at most 3 advice items
    if ($actionAdvice.Count -gt 3) {
        $actionAdvice = @($actionAdvice[0], $actionAdvice[1], $actionAdvice[2])
    }

    # --- Total score ---
    $totalScore = $rsiScore + $smaScore + $macdScore + $bollingerScore + $percentileScore + $volatilityScore

    # --- Determine recommendation ---
    $recommendation = ""
    if ($totalScore -gt 30) {
        $recommendation = "強烈建議買入"
    }
    elseif ($totalScore -ge 10) {
        $recommendation = "建議買入"
    }
    elseif ($totalScore -gt -10) {
        $recommendation = "觀望"
    }
    elseif ($totalScore -ge -30) {
        $recommendation = "建議觀望/賣出"
    }
    else {
        $recommendation = "強烈建議賣出"
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
        $posText = ""
        if ($pctInt -le 20) { $posText = "接近低點" }
        elseif ($pctInt -ge 80) { $posText = "接近高點" }
        elseif ($pctInt -le 40) { $posText = "偏弱" }
        elseif ($pctInt -ge 60) { $posText = "偏強" }
        else { $posText = "中性" }
        $summaryParts += "目前 ${Currency} 即期賣出匯率 ${currentSpotSell} 位於近30日第 ${pctInt} 百分位，${posText}。"
    }

    # Sentence 2: RSI
    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        if ($rsiInt -lt 30) {
            $summaryParts += "RSI 為 ${rsiInt} 處於超賣區間，短期有反彈可能。"
        }
        elseif ($rsiInt -gt 70) {
            $summaryParts += "RSI 為 ${rsiInt} 處於超買區間，短期有回調風險。"
        }
        else {
            $summaryParts += "RSI 為 ${rsiInt} 處於中性區間。"
        }
    }

    # Sentence 3: MACD
    if ($null -ne $histogram) {
        if ($histogram -gt 0) {
            $summaryParts += "MACD 柱狀圖為正，顯示動能偏多。"
        }
        elseif ($histogram -lt 0) {
            $summaryParts += "MACD 柱狀圖為負，顯示動能偏空。"
        }
        else {
            $summaryParts += "MACD 柱狀圖接近零，動能不明確。"
        }
    }

    # Sentence 4: Bollinger
    if ($null -ne $bbPercentB) {
        $pbInt = [int][math]::Round($bbPercentB)
        if ($bbPercentB -lt 20) {
            $summaryParts += "布林通道 %B 僅 ${pbInt}%，價格接近下軌支撐。"
        }
        elseif ($bbPercentB -gt 80) {
            $summaryParts += "布林通道 %B 達 ${pbInt}%，價格接近上軌壓力。"
        }
        else {
            $summaryParts += "布林通道 %B 為 ${pbInt}%，價格位於通道中間。"
        }
    }

    # Sentence 5: Final recommendation
    $scoreStr = ""
    if ($totalScore -ge 0) { $scoreStr = "+$totalScore" } else { $scoreStr = "$totalScore" }
    $summaryParts += "綜合評分 ${scoreStr} 分，${recommendation}。"

    $summary = $summaryParts -join ''

    # ============================================
    # Build DetailedReport (multi-line, Traditional Chinese)
    # ============================================

    $lines = @()
    $lines += "═══════════════════════════════"
    $lines += "  ${Currency} 匯率綜合分析報告 — ${Period}"
    $lines += "═══════════════════════════════"
    $lines += ""

    # Score header
    if ($totalScore -ge 0) { $scoreStr = "+$totalScore" } else { $scoreStr = "$totalScore" }
    $lines += "📌 綜合評分: ${scoreStr}  →  ${recommendation}"
    $lines += ""
    $lines += "───────────────────────────────"
    $lines += "  技術指標明細"
    $lines += "───────────────────────────────"
    $lines += ""

    # --- Trend indicators ---
    $lines += "📈 趨勢指標"
    $sma5Str  = if ($null -ne $sma5Value)  { "$sma5Value" } else { "N/A" }
    $sma20Str = if ($null -ne $sma20Value) { "$sma20Value" } else { "N/A" }
    $lines += "  SMA5: ${sma5Str}  |  SMA20: ${sma20Str}"

    if ($null -ne $sma5Value -and $null -ne $sma20Value) {
        if ($sma5Value -gt $sma20Value) {
            $trendLabel = "上升"
            $trendScoreStr = "+$smaScore"
        }
        elseif ($sma5Value -lt $sma20Value) {
            $trendLabel = "下降"
            if ($smaScore -ge 0) { $trendScoreStr = "+$smaScore" } else { $trendScoreStr = "$smaScore" }
        }
        else {
            $trendLabel = "盤整"
            $trendScoreStr = "$smaScore"
        }
        $lines += "  趨勢: ${trendLabel} (${trendScoreStr}分)"
    }
    $lines += ""

    # --- Momentum indicators ---
    $lines += "📊 動量指標"
    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        $rsiLabel = ""
        if ($rsiInt -lt 30) { $rsiLabel = "超賣" }
        elseif ($rsiInt -gt 70) { $rsiLabel = "超買" }
        else { $rsiLabel = "中性" }
        if ($rsiScore -ge 0) { $rsiScoreStr = "+$rsiScore" } else { $rsiScoreStr = "$rsiScore" }
        $lines += "  RSI(14): ${rsiInt}  →  ${rsiLabel} (${rsiScoreStr}分)"
    }
    else {
        $lines += "  RSI(14): N/A"
    }

    $macdLineStr   = if ($null -ne $macdLine)   { "$macdLine" } else { "N/A" }
    $signalLineStr = if ($null -ne $signalLine)  { "$signalLine" } else { "N/A" }
    $histogramStr  = if ($null -ne $histogram)   { "$histogram" } else { "N/A" }
    $lines += "  MACD: ${macdLineStr}  |  訊號線: ${signalLineStr}  |  柱狀: ${histogramStr}"

    if ($null -ne $histogram) {
        if ($histogram -gt [decimal]0.001) {
            $macdLabel = "多頭"
            if ($macdScore -ge 0) { $macdScoreStr = "+$macdScore" } else { $macdScoreStr = "$macdScore" }
            $lines += "  MACD 判定: ${macdLabel} (${macdScoreStr}分)"
        }
        elseif ($histogram -lt [decimal]-0.001) {
            $macdLabel = "空頭"
            if ($macdScore -ge 0) { $macdScoreStr = "+$macdScore" } else { $macdScoreStr = "$macdScore" }
            $lines += "  MACD 判定: ${macdLabel} (${macdScoreStr}分)"
        }
        else {
            $macdLabel = "中性"
            $macdScoreStr = "$macdScore"
            $lines += "  MACD 判定: ${macdLabel} (${macdScoreStr}分)"
        }
    }
    $lines += ""

    # --- Volatility indicators ---
    $lines += "📐 波動指標"
    $bbUpperStr  = if ($null -ne $bbUpper)  { "$bbUpper" } else { "N/A" }
    $bbMiddleStr = if ($null -ne $bbMiddle) { "$bbMiddle" } else { "N/A" }
    $bbLowerStr  = if ($null -ne $bbLower)  { "$bbLower" } else { "N/A" }
    $lines += "  布林通道: 上軌 ${bbUpperStr}  |  中軌 ${bbMiddleStr}  |  下軌 ${bbLowerStr}"

    if ($null -ne $bbPercentB) {
        $pbInt = [int][math]::Round($bbPercentB)
        if ($bbPercentB -lt 20) {
            $pbLabel = "接近下軌"
        }
        elseif ($bbPercentB -gt 80) {
            $pbLabel = "接近上軌"
        }
        else {
            $pbLabel = "通道中間"
        }
        if ($bollingerScore -ge 0) { $bbScoreStr = "+$bollingerScore" } else { $bbScoreStr = "$bollingerScore" }
        $lines += "  %B: ${pbInt}%  →  ${pbLabel} (${bbScoreStr}分)"
    }

    if ($null -ne $bbBandwidth) {
        $bwStr = [math]::Round($bbBandwidth, 1)
        if ($bbBandwidth -gt 3) {
            $bwLabel = "高波動"
        }
        elseif ($bbBandwidth -lt 1) {
            $bwLabel = "低波動"
        }
        else {
            $bwLabel = "正常波動"
        }
        if ($volatilityScore -ge 0) { $volScoreStr = "+$volatilityScore" } else { $volScoreStr = "$volatilityScore" }
        $lines += "  帶寬: ${bwStr}%  →  ${bwLabel} (${volScoreStr}分)"
    }
    $lines += ""

    # --- Position indicators ---
    $lines += "📏 位置指標"
    if ($null -ne $percentileValue) {
        $pctInt = [int][math]::Round($percentileValue)
        if ($percentileScore -ge 0) { $pctScoreStr = "+$percentileScore" } else { $pctScoreStr = "$percentileScore" }
        $pctPosDesc = if ($pctInt -le 20) { '低點' } elseif ($pctInt -ge 80) { '高點' } else { '中間' }
        $lines += "  30日百分位: ${pctInt}%  →  接近${pctPosDesc} (${pctScoreStr}分)"
    }
    else {
        $lines += "  30日百分位: N/A"
    }
    $lines += ""

    # --- Trend Strength & Risk section ---
    $lines += "───────────────────────────────"
    $lines += "  趨勢強度與風險評估"
    $lines += "───────────────────────────────"
    $lines += ""

    $lines += "📊 趨勢強度: ${trendStrength}"
    $lines += "  （綜合 SMA 趨勢 + MACD 動能 + 布林帶寬）"

    $riskIcon = ""
    if ($riskLevel -eq "高") { $riskIcon = "🔴" }
    elseif ($riskLevel -eq "中") { $riskIcon = "🟡" }
    else { $riskIcon = "🟢" }
    $lines += ""
    $lines += "${riskIcon} 風險等級: ${riskLevel}"
    $riskReasonParts = @()
    if ($null -ne $bbBandwidth -and $bbBandwidth -ge 3) { $riskReasonParts += "帶寬較高 ($bbBandwidth%)" }
    if ($null -ne $rsiValue) {
        $rsiInt3 = [int][math]::Round($rsiValue)
        if ($rsiInt3 -le 30 -or $rsiInt3 -ge 70) { $riskReasonParts += "RSI 處於極端值 ($rsiInt3)" }
    }
    if ($riskReasonParts.Count -gt 0) {
        $lines += "  （原因: " + ($riskReasonParts -join '、') + "）"
    }
    else {
        $lines += "  （各項指標波動與偏離程度正常）"
    }
    $lines += ""

    # --- Cross-Signal Confirmation section ---
    $lines += "───────────────────────────────"
    $lines += "  多重訊號共識"
    $lines += "───────────────────────────────"
    $lines += ""

    if ($crossSignalDirection -eq "分歧") {
        $lines += "⚖️ 多空訊號分歧：看多 ${bullSignals} 項 / 看空 ${bearSignals} 項"
        $lines += "  目前指標尚未形成共識，建議觀望為主。"
    }
    else {
        $csEmoji = ""
        if ($crossSignalDirection -eq "看多") { $csEmoji = "🟢" } else { $csEmoji = "🔴" }
        $csStr = ""
        if ($crossSignalStrength -eq "強") { $csStr = "（強共識）" } else { $csStr = "（弱共識）" }
        $lines += "${csEmoji} 多重訊號共識: ${crossSignalDirection}${csStr}"
        $lines += "  看多 ${bullSignals} 項 / 看空 ${bearSignals} 項"

        if ($crossSignalList.Count -gt 0) {
            $lines += "  共識訊號: " + ($crossSignalList -join '、')
        }

        if ($crossSignalStrength -eq "強") {
            if ($crossSignalDirection -eq "看多") {
                $lines += "  ⮕ 多項指標一致看多，訊號可靠度較高，可適度加碼。"
            }
            else {
                $lines += "  ⮕ 多項指標一致看空，訊號可靠度較高，宜保守操作。"
            }
        }
        else {
            $lines += "  ⮕ 共識程度尚可，建議搭配其他訊號確認後再行動。"
        }
    }
    $lines += ""

    # --- Final recommendation section ---
    $lines += "───────────────────────────────"
    $lines += "  綜合建議"
    $lines += "───────────────────────────────"
    $lines += ""

    # Build narrative recommendation
    $narrativeParts = @()

    if ($null -ne $currentSpotSell -and $null -ne $percentileValue) {
        $pctInt = [int][math]::Round($percentileValue)
        $posDesc = if ($pctInt -le 20) { "接近低點" } elseif ($pctInt -ge 80) { "接近高點" } elseif ($pctInt -le 40) { "偏低" } elseif ($pctInt -ge 60) { "偏高" } else { "中間" }
        $narrativeParts += "目前 ${Currency} 即期賣出匯率 ${currentSpotSell} 位於近30日第 ${pctInt} 百分位，${posDesc}。"
    }

    if ($null -ne $rsiValue) {
        $rsiInt = [int][math]::Round($rsiValue)
        if ($rsiInt -lt 30) {
            $narrativeParts += "RSI 為 ${rsiInt} 處於超賣區間，短期有反彈可能。"
        }
        elseif ($rsiInt -gt 70) {
            $narrativeParts += "RSI 為 ${rsiInt} 處於超買區間，短期有回調風險。"
        }
        else {
            $narrativeParts += "RSI 為 ${rsiInt}，處於中性區間。"
        }
    }

    if ($null -ne $histogram) {
        if ($histogram -gt 0) {
            $narrativeParts += "MACD 柱狀圖由負轉正，顯示動能轉強。"
        }
        elseif ($histogram -lt 0) {
            $narrativeParts += "MACD 柱狀圖仍為負值，顯示動能偏弱。"
        }
    }

    if ($null -ne $bbPercentB) {
        $pbInt = [int][math]::Round($bbPercentB)
        if ($bbPercentB -lt 20) {
            $narrativeParts += "布林通道 %B 僅 ${pbInt}%，價格接近下軌支撐。"
        }
        elseif ($bbPercentB -gt 80) {
            $narrativeParts += "布林通道 %B 達 ${pbInt}%，價格接近上軌壓力。"
        }
    }

    # Add cross-signal note in narrative
    if ($crossSignalDirection -ne "分歧" -and $crossSignalStrength -eq "強") {
        if ($crossSignalDirection -eq "看多") {
            $narrativeParts += "多項指標形成看多共識，訊號可靠度提升。"
        }
        else {
            $narrativeParts += "多項指標形成看空共識，訊號可靠度提升。"
        }
    }

    $narrativeParts += "綜合評分 ${scoreStr} 分，${recommendation}。"

    # Append suitability note based on recommendation
    if ($totalScore -gt 10) {
        $narrativeParts += "適合有外幣需求的民眾分批買入。"
    }
    elseif ($totalScore -lt -10) {
        $narrativeParts += "建議暫緩買入，或可考慮分批賣出。"
    }
    else {
        $narrativeParts += "建議持續觀察，等待更明確訊號。"
    }

    $lines += ($narrativeParts -join '')
    $lines += ""

    # --- Action Advice section ---
    if ($actionAdvice.Count -gt 0) {
        $lines += ""
        $lines += "💡 操作建議"
        foreach ($advice in $actionAdvice) {
            $lines += "  • $advice"
        }
    }

    $lines += ""
    $lines += "⚠ 以上分析僅供參考，不構成任何投資建議。投資有風險，請自行審慎評估。"

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
