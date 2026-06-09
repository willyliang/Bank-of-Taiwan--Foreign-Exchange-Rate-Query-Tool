#Requires -Version 5.1

<#
.SYNOPSIS
    ChartBuilder module for creating and managing .NET Chart controls for FX rate display.

.DESCRIPTION
    Provides functions to create a WinForms Chart control configured for historical
    exchange rate curves, update chart data, adjust period formatting, and compute
    date ranges for various time periods.
#>

# ── Assembly Loading ──────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction SilentlyContinue

# ── Internal Constants ────────────────────────────────────────────────────────
$script:SeriesConfig = @(
    @{ Name = '現金買入'; Color = [System.Drawing.Color]::FromArgb(0, 255, 136) }
    @{ Name = '現金賣出'; Color = [System.Drawing.Color]::FromArgb(255, 50, 100) }
    @{ Name = '即期買入'; Color = [System.Drawing.Color]::FromArgb(0, 212, 255) }
    @{ Name = '即期賣出'; Color = [System.Drawing.Color]::FromArgb(138, 43, 226) }
)

# ── Function: New-RateChart ──────────────────────────────────────────────────

function New-RateChart {
    <#
    .SYNOPSIS
        Creates a new Chart control configured for FX rate display.

    .DESCRIPTION
        Builds a System.Windows.Forms.DataVisualization.Charting.Chart object with
        four line series (現金買入, 現金賣出, 即期買入, 即期賣出), a white
        ChartArea with light-gray grid, a bottom-docked legend, and a bold title.

    .PARAMETER Width
        Width of the chart in pixels. Default is 800.

    .PARAMETER Height
        Height of the chart in pixels. Default is 400.

    .OUTPUTS
        System.Windows.Forms.DataVisualization.Charting.Chart
    #>
    [CmdletBinding()]
    param(
        [int]$Width = 800,
        [int]$Height = 400
    )

    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    $chart.Width  = $Width
    $chart.Height = $Height
    $chart.BackColor = [System.Drawing.Color]::FromArgb(35, 38, 52)

    # ── ChartArea ─────────────────────────────────────────────────────────
    $chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
    $chartArea.Name = 'RateArea'
    $chartArea.BackColor = [System.Drawing.Color]::FromArgb(35, 38, 52)

    # X-Axis
    $chartArea.AxisX.LabelStyle.Format   = 'MM/dd'
    $chartArea.AxisX.IntervalType        = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Days
    $chartArea.AxisX.Interval            = 1
    $chartArea.AxisX.MajorGrid.LineColor = [System.Drawing.Color]::FromArgb(55, 58, 80)
    $chartArea.AxisX.MajorGrid.LineDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]::Dot
    $chartArea.AxisX.LabelStyle.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)

    # Y-Axis
    $chartArea.AxisY.LabelStyle.Format   = '0.00'
    $chartArea.AxisY.MajorGrid.LineColor = [System.Drawing.Color]::FromArgb(55, 58, 80)
    $chartArea.AxisY.LabelStyle.ForeColor = [System.Drawing.Color]::FromArgb(140, 150, 175)

    $chart.ChartAreas.Add($chartArea)

    # ── Series ────────────────────────────────────────────────────────────
    foreach ($cfg in $script:SeriesConfig) {
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.Name         = $cfg.Name
        $series.ChartType    = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Line
        $series.Color        = $cfg.Color
        $series.BorderWidth  = 2
        $series.XValueType  = [System.Windows.Forms.DataVisualization.Charting.ChartValueType]::DateTime
        $series.YValueType  = [System.Windows.Forms.DataVisualization.Charting.ChartValueType]::Double
        $series.ChartArea    = 'RateArea'
        $chart.Series.Add($series)
    }

    # ── Legend ────────────────────────────────────────────────────────────
    $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
    $legend.Name        = 'RateLegend'
    $legend.Docking     = [System.Windows.Forms.DataVisualization.Charting.Docking]::Bottom
    $legend.LegendStyle = [System.Windows.Forms.DataVisualization.Charting.LegendStyle]::Row
    $legend.Font        = New-Object System.Drawing.Font('Microsoft JhengHei', 9)
    $legend.ForeColor   = [System.Drawing.Color]::FromArgb(140, 150, 175)
    $legend.BackColor   = [System.Drawing.Color]::FromArgb(35, 38, 52)
    $chart.Legends.Add($legend)

    # ── Title ─────────────────────────────────────────────────────────────
    $title = New-Object System.Windows.Forms.DataVisualization.Charting.Title
    $title.Text = '歷史匯率曲線'
    $title.Font = New-Object System.Drawing.Font('Microsoft JhengHei', 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
    $chart.Titles.Add($title)

    return $chart
}

# ── Function: Update-ChartData ───────────────────────────────────────────────

function Update-ChartData {
    <#
    .SYNOPSIS
        Updates the chart with historical daily rate data.

    .DESCRIPTION
        Accepts an array of PSCustomObject data points (Date, CashBuy, CashSell,
        SpotBuy, SpotSell), sorts them by date, clears existing series points,
        and adds new data. Zero values are skipped to avoid misleading dips.

    .PARAMETER Chart
        The Chart object to update.

    .PARAMETER DataPoints
        Array of PSCustomObject with properties: Date (DateTime or "YYYY-MM-DD"),
        CashBuy, CashSell, SpotBuy, SpotSell (decimal).

    .OUTPUTS
        None. Modifies the Chart object in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.DataVisualization.Charting.Chart]$Chart,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$DataPoints
    )

    # Handle null or empty input
    if ($null -eq $DataPoints -or $DataPoints.Count -eq 0) {
        foreach ($cfg in $script:SeriesConfig) {
            $Chart.Series[$cfg.Name].Points.Clear()
        }
        if ($Chart.Titles.Count -gt 0) {
            $Chart.Titles[0].Text = '尚無資料'
        }
        $Chart.Invalidate()
        return
    }

    # Sort by Date ascending
    $sorted = $DataPoints | Sort-Object -Property Date

    # Clear all series
    foreach ($cfg in $script:SeriesConfig) {
        $Chart.Series[$cfg.Name].Points.Clear()
    }

    # Reset title
    if ($Chart.Titles.Count -gt 0) {
        $Chart.Titles[0].Text = '歷史匯率曲線'
    }

    # Property mapping: series name → data property
    $propMap = @{
        '現金買入' = 'CashBuy'
        '現金賣出' = 'CashSell'
        '即期買入' = 'SpotBuy'
        '即期賣出' = 'SpotSell'
    }

    $allY = @()

    foreach ($pt in $sorted) {
        # Parse date — robust: handle datetime objects, yyyy-MM-dd, and other formats
        $dateValue = $null
        if ($pt.Date -is [datetime]) {
            $dateValue = $pt.Date
        }
        elseif ([string]::IsNullOrWhiteSpace($pt.Date)) {
            continue  # Skip entries with empty Date
        }
        else {
            try {
                $dateValue = [datetime]::ParseExact($pt.Date, 'yyyy-MM-dd', $null)
            }
            catch {
                try {
                    $dateValue = [datetime]::Parse($pt.Date)
                }
                catch {
                    continue  # Skip unparseable dates
                }
            }
        }

        if ($null -eq $dateValue) { continue }

        foreach ($seriesName in $propMap.Keys) {
            $propName  = $propMap[$seriesName]
            $rateValue = $pt.$propName

            # Skip zero values (N/A)
            if ($null -eq $rateValue -or $rateValue -eq 0) { continue }

            $Chart.Series[$seriesName].Points.AddXY($dateValue, $rateValue) | Out-Null
            $allY += $rateValue
        }
    }

    # Adjust Y-axis: auto-scale interval based on data range
    # USD ~30 range 1~3 → interval 0.05; JPY ~0.22 range 0.005 → interval 0.001
    $chartArea = $Chart.ChartAreas['RateArea']
    if ($allY.Count -gt 0) {
        $yMin = ($allY | Measure-Object -Minimum).Minimum
        $yMax = ($allY | Measure-Object -Maximum).Maximum
        $yRange = $yMax - $yMin
        if ($yRange -eq 0) { $yRange = $yMax * 0.05 }  # avoid zero range

        # Pick interval so ~6-10 grid lines span the range
        # Try "nice" steps: 0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01 ...
        $niceSteps = @(0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100)
        $interval = 0.05
        foreach ($step in $niceSteps) {
            if ($yRange / $step -le 10 -and $yRange / $step -ge 4) {
                $interval = $step
                break
            }
        }
        $chartArea.AxisY.Interval = $interval
        # Update label format to match precision
        $decimals = 0
        $tmp = $interval
        while ($tmp -lt 1 -and $decimals -lt 6) { $tmp *= 10; $decimals++ }
        $chartArea.AxisY.LabelStyle.Format = "0.$('0' * $decimals)"
        # Pad top/bottom by ~2 intervals so curve doesn't touch edges
        $pad = $interval * 2
        $chartArea.AxisY.Minimum = [Math]::Floor(($yMin - $pad) / $interval) * $interval
        $chartArea.AxisY.Maximum = [Math]::Ceiling(($yMax + $pad) / $interval) * $interval
    }

    $Chart.Invalidate()
}

# ── Function: Set-ChartPeriod ────────────────────────────────────────────────

function Set-ChartPeriod {
    <#
    .SYNOPSIS
        Adjusts the chart X-Axis format and interval for a given period.

    .DESCRIPTION
        Configures axis label format, interval type, and interval value based on
        the selected time period. For 本日 (intraday), the X-axis displays time
        (HH:mm) with hourly intervals.

    .PARAMETER Chart
        The Chart object to reconfigure.

    .PARAMETER Period
        One of: 本日, 本月, 3個月, 半年, 1年, 3年, 5年, 10年.

    .OUTPUTS
        None. Modifies the Chart object in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.DataVisualization.Charting.Chart]$Chart,

        [Parameter(Mandatory)]
        [string]$Period
    )

    $area = $Chart.ChartAreas['RateArea']

    switch ($Period) {
        '本日' {
            $area.AxisX.LabelStyle.Format = 'HH:mm'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Hours
            $area.AxisX.Interval         = 1
        }
        '本月' {
            $area.AxisX.LabelStyle.Format = 'MM/dd'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Days
            $area.AxisX.Interval         = 2
        }
        '3個月' {
            $area.AxisX.LabelStyle.Format = 'MM/dd'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Weeks
            $area.AxisX.Interval         = 1
        }
        '半年' {
            $area.AxisX.LabelStyle.Format = 'yyyy/MM'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Months
            $area.AxisX.Interval         = 1
        }
        '1年' {
            $area.AxisX.LabelStyle.Format = 'yyyy/MM'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Months
            $area.AxisX.Interval         = 2
        }
        '3年' {
            $area.AxisX.LabelStyle.Format = 'yyyy/MM'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Months
            $area.AxisX.Interval         = 3
        }
        '5年' {
            $area.AxisX.LabelStyle.Format = 'yyyy/MM'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Months
            $area.AxisX.Interval         = 6
        }
        '10年' {
            $area.AxisX.LabelStyle.Format = 'yyyy'
            $area.AxisX.IntervalType     = [System.Windows.Forms.DataVisualization.Charting.DateTimeIntervalType]::Years
            $area.AxisX.Interval         = 1
        }
    }

    $Chart.Invalidate()
}

# ── Function: Get-PeriodDateRange ───────────────────────────────────────────

function Get-PeriodDateRange {
    <#
    .SYNOPSIS
        Returns the start and end dates for a given period string.

    .DESCRIPTION
        Computes StartDate and EndDate as DateTime objects based on the
        specified period. EndDate is always today; StartDate varies.

    .PARAMETER Period
        One of: 本日, 本月, 3個月, 半年, 1年, 3年, 5年, 10年.

    .OUTPUTS
        PSCustomObject with StartDate (DateTime) and EndDate (DateTime).

    .EXCEPTIONS
        Throws ArgumentException for invalid period strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Period
    )

    $today = [datetime]::Today

    switch ($Period) {
        '本日' {
            $startDate = $today
        }
        '本月' {
            $startDate = New-Object System.DateTime($today.Year, $today.Month, 1)
        }
        '3個月' {
            $startDate = $today.AddMonths(-3)
        }
        '半年' {
            $startDate = $today.AddMonths(-6)
        }
        '1年' {
            $startDate = $today.AddYears(-1)
        }
        '3年' {
            $startDate = $today.AddYears(-3)
        }
        '5年' {
            $startDate = $today.AddYears(-5)
        }
        '10年' {
            $startDate = $today.AddYears(-10)
        }
        default {
            throw "Invalid period '$Period'. Must be one of: 本日, 本月, 3個月, 半年, 1年, 3年, 5年, 10年"
        }
    }

    return [PSCustomObject]@{
        StartDate = $startDate
        EndDate   = $today
    }
}

# ── Function: Update-ChartDataIntraday ──────────────────────────────────────

function Update-ChartDataIntraday {
    <#
    .SYNOPSIS
        Updates the chart with intraday rate data.

    .DESCRIPTION
        Accepts an array of PSCustomObject data points (Time, CashBuy, CashSell,
        SpotBuy, SpotSell), clears existing series points, and adds new data.
        Time strings (HH:mm:ss) are combined with today's date to form DateTime
        X-values. Zero values are skipped to avoid misleading dips.

    .PARAMETER Chart
        The Chart object to update.

    .PARAMETER IntradayPoints
        Array of PSCustomObject with properties: Time (string "HH:mm:ss"),
        CashBuy, CashSell, SpotBuy, SpotSell (decimal).

    .OUTPUTS
        None. Modifies the Chart object in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.DataVisualization.Charting.Chart]$Chart,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$IntradayPoints
    )

    # Handle null or empty input
    if ($null -eq $IntradayPoints -or $IntradayPoints.Count -eq 0) {
        foreach ($cfg in $script:SeriesConfig) {
            $Chart.Series[$cfg.Name].Points.Clear()
        }
        if ($Chart.Titles.Count -gt 0) {
            $Chart.Titles[0].Text = '尚無資料'
        }
        $Chart.Invalidate()
        return
    }

    # Sort by Time ascending
    $sorted = $IntradayPoints | Sort-Object -Property Time

    # Clear all series
    foreach ($cfg in $script:SeriesConfig) {
        $Chart.Series[$cfg.Name].Points.Clear()
    }

    # Reset title
    if ($Chart.Titles.Count -gt 0) {
        $Chart.Titles[0].Text = '歷史匯率曲線'
    }

    # Property mapping
    $propMap = @{
        '現金買入' = 'CashBuy'
        '現金賣出' = 'CashSell'
        '即期買入' = 'SpotBuy'
        '即期賣出' = 'SpotSell'
    }

    $allY = @()

    foreach ($pt in $sorted) {
        # Parse time as DateTime (today + time)
        $dt = [datetime]::Parse("$([datetime]::Today.ToString('yyyy-MM-dd')) $($pt.Time)")

        foreach ($seriesName in $propMap.Keys) {
            $propName  = $propMap[$seriesName]
            $rateValue = $pt.$propName

            # Skip zero values (N/A)
            if ($null -eq $rateValue -or $rateValue -eq 0) { continue }

            $Chart.Series[$seriesName].Points.AddXY($dt, $rateValue) | Out-Null
            $allY += $rateValue
        }
    }

    # Adjust Y-axis: auto-scale interval based on data range
    $chartArea = $Chart.ChartAreas['RateArea']
    if ($allY.Count -gt 0) {
        $yMin = ($allY | Measure-Object -Minimum).Minimum
        $yMax = ($allY | Measure-Object -Maximum).Maximum
        $yRange = $yMax - $yMin
        if ($yRange -eq 0) { $yRange = $yMax * 0.05 }

        $niceSteps = @(0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100)
        $interval = 0.05
        foreach ($step in $niceSteps) {
            if ($yRange / $step -le 10 -and $yRange / $step -ge 4) {
                $interval = $step
                break
            }
        }
        $chartArea.AxisY.Interval = $interval
        $decimals = 0
        $tmp = $interval
        while ($tmp -lt 1 -and $decimals -lt 6) { $tmp *= 10; $decimals++ }
        $chartArea.AxisY.LabelStyle.Format = "0.$('0' * $decimals)"
        $pad = $interval * 2
        $chartArea.AxisY.Minimum = [Math]::Floor(($yMin - $pad) / $interval) * $interval
        $chartArea.AxisY.Maximum = [Math]::Ceiling(($yMax + $pad) / $interval) * $interval
    }

    $Chart.Invalidate()
}

# ── Function: Get-ChartSeriesNames ──────────────────────────────────────────

function Get-ChartSeriesNames {
    <#
    .SYNOPSIS
        Returns the names of all chart series.
    .DESCRIPTION
        Returns an array of series names (e.g. '現金買入', '現金賣出', '即期買入', '即期賣出')
        from the module's internal SeriesConfig. Use this instead of hardcoding series names
        in calling code to stay in sync with the chart configuration.
    .OUTPUTS
        [string[]] Array of series names.
    #>
    [CmdletBinding()]
    param()

    return @($script:SeriesConfig | ForEach-Object { $_.Name })
}

# ── Module Exports ───────────────────────────────────────────────────────────
Export-ModuleMember -Function @(
    'New-RateChart',
    'Update-ChartData',
    'Set-ChartPeriod',
    'Get-PeriodDateRange',
    'Get-ChartSeriesNames',
    'Update-ChartDataIntraday'
)
