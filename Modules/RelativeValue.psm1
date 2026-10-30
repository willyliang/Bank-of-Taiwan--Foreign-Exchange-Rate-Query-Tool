<#
.SYNOPSIS
    相對划算度（一年期位階）附加模組 — 純新增，不修改任何原始模組。
.DESCRIPTION
    Get-RelativeValue                    : 計算一年(252 交易日)位階 0-100 + 樣本數/足夠性/標籤
    Get-RelativeValueHistory             : 以 Get-HistoricalRange 載入近 N 個月每日歷史
    Get-RelativeValueText                : 產生本地化(zh/en)報告區塊字串（自帶字串，不動 i18n.psm1）
    Get-RateRecommendationWithRelative   : 呼叫原 Get-RateRecommendation 並附加「一年相對划算度」區塊
#>

Set-StrictMode -Version Latest

function Get-RelativeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$DataPoints,
        [string]$Property = 'SpotSell',
        [int]$Window     = 252,
        [int]$MinSamples = 252
    )

    $count = 0
    foreach ($pt in $DataPoints) {
        if ($null -eq $pt) { continue }
        $val = $pt.$Property
        if ($null -ne $val -and $val -ne 0) { $count++ }
    }

    if ($count -lt 1) {
        return [PSCustomObject]@{ Position = $null; SampleCount = 0; Sufficient = $false; Band = 'na' }
    }

    $sufficient = ($count -ge $MinSamples)
    $pos = Get-CurrentPosition -DataPoints $DataPoints -Property $Property -Period $Window

    $band = 'normal'
    if ($null -ne $pos) {
        if ($pos -le 33)     { $band = 'cheap' }
        elseif ($pos -ge 67) { $band = 'expensive' }
    }

    [PSCustomObject]@{ Position = $pos; SampleCount = $count; Sufficient = $sufficient; Band = $band }
}

function Get-RelativeValueHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrencyCode,
        [int]$Months = 18
    )

    try {
        $end   = [datetime]::Today
        $start = $end.AddMonths(-[math]::Abs($Months))
        $miss  = [ref]@()
        return @(Get-HistoricalRange -CurrencyCode $CurrencyCode -StartDate $start -EndDate $end -MissingDates $miss)
    }
    catch {
        return @()
    }
}

function Get-RelativeValueText {
    [CmdletBinding()]
    param(
        [Parameter()]$RelValue,
        [string]$Lang = 'zh'
    )

    $isZh   = ($Lang -ne 'en')
    $header = if ($isZh) { '📅 一年相對划算度' } else { '📅 1-Year Relative Value' }

    if ($null -eq $RelValue -or -not $RelValue.Sufficient) {
        $haveN = 0
        if ($null -ne $RelValue) { $haveN = [int]$RelValue.SampleCount }
        if ($isZh) {
            $line = "  一年期位階：資料不足／累積中（需 252 個交易日，目前 $haveN 天）"
        } else {
            $line = "  1-year position: insufficient data (need 252 trading days, have $haveN)"
        }
        return ($header + "`n" + $line)
    }

    $v = [int][math]::Round($RelValue.Position)
    $bandText = switch ($RelValue.Band) {
        'cheap'     { if ($isZh) { '相對便宜（一年低位）' } else { 'relatively cheap (1-year low)' } }
        'expensive' { if ($isZh) { '相對貴（一年高位）' }   else { 'relatively expensive (1-year high)' } }
        default     { if ($isZh) { '中間' }                 else { 'middle' } }
    }

    if ($isZh) {
        $line = "  一年期位階 $v%（$bandText）；樣本 $($RelValue.SampleCount) 個交易日"
        $note = '  ※ 長線位階僅供參考，非短期買賣訊號'
    } else {
        $line = "  1-year position $v% ($bandText); sample = $($RelValue.SampleCount) trading days"
        $note = '  Note: long-horizon position is informational only, not a short-term trade signal'
    }

    return ($header + "`n" + $line + "`n" + $note)
}

function Get-RateRecommendationWithRelative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$DataPoints,
        [Parameter(Mandatory)][string]$Currency,
        [Parameter(Mandatory)][string]$Period,
        [Parameter()][ValidateSet('zh','en')][string]$Lang = 'zh',
        [Parameter()][AllowEmptyCollection()][array]$DailyHistory
    )

    $rec = Get-RateRecommendation -DataPoints $DataPoints -Currency $Currency -Period $Period -Lang $Lang
    if ($null -eq $rec) { return $rec }

    $rel = $null
    if ($null -ne $DailyHistory -and $DailyHistory.Count -gt 0) {
        $rel = Get-RelativeValue -DataPoints $DailyHistory
    }

    $section = Get-RelativeValueText -RelValue $rel -Lang $Lang

    $report = [string]$rec.DetailedReport
    $disclaimer = ''
    try { $disclaimer = [string](L 'risk_disclaimer') } catch { $disclaimer = '' }

    if ($disclaimer -ne '') {
        $idx = $report.LastIndexOf($disclaimer)
        if ($idx -ge 0) {
            $report = $report.Substring(0, $idx) + $section + "`n`n" + $report.Substring($idx)
        } else {
            $report = $report + "`n`n" + $section
        }
    } else {
        $report = $report + "`n`n" + $section
    }

    $relPos  = $null
    $relBand = 'na'
    $relSuff = $false
    if ($null -ne $rel) {
        $relPos  = $rel.Position
        $relBand = $rel.Band
        $relSuff = [bool]$rel.Sufficient
    }

    $rec | Add-Member -NotePropertyName DetailedReport           -NotePropertyValue $report   -Force
    $rec | Add-Member -NotePropertyName RelativeValue            -NotePropertyValue $relPos   -Force
    $rec | Add-Member -NotePropertyName RelativeValueBand        -NotePropertyValue $relBand  -Force
    $rec | Add-Member -NotePropertyName RelativeValueSufficient  -NotePropertyValue $relSuff  -Force

    return $rec
}

Export-ModuleMember -Function @(
    'Get-RelativeValue',
    'Get-RelativeValueHistory',
    'Get-RelativeValueText',
    'Get-RateRecommendationWithRelative'
)
