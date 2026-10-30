# =============================================================================
# OllamaHelper.psm1
# Ollama Local LLM Helper Module - Auto-detect, Start, Model Management
# =============================================================================

# Import i18n module for localization
Import-Module (Join-Path $PSScriptRoot 'i18n.psm1') -Force

# -----------------------------------------------------------------------------
# Module-Level Variables
# -----------------------------------------------------------------------------
$script:OllamaApiBase = 'http://localhost:11434'

# =============================================================================
# Function: Test-OllamaAvailable
# =============================================================================

<#
.SYNOPSIS
    檢查 Ollama 是否已安裝且服務正在執行。

.DESCRIPTION
    依序執行兩項檢查：
    1. 確認 ollama.exe 在 PATH 中可找到（Get-Command）。
    2. 對 http://localhost:11434/api/tags 發送 GET 要求，確認 API 有回應。

    回傳具 IsOnPath、IsRunning、OllamaPath 三個屬性的 PSCustomObject。

.OUTPUTS
    [PSCustomObject] 含 IsOnPath (bool)、IsRunning (bool)、OllamaPath (string)。

.EXAMPLE
    $r = Test-OllamaAvailable
    if (-not $r.IsOnPath) { Write-Host 'Ollama 未安裝' }
    elseif (-not $r.IsRunning) { Write-Host 'Ollama 已安裝但未啟動' }
    else { Write-Host 'Ollama 正常運作' }
#>
function Test-OllamaAvailable {
    [CmdletBinding()]
    param()

    $result = [PSCustomObject]@{
        IsOnPath   = $false
        IsRunning  = $false
        OllamaPath = ''
    }

    # 1. Check if ollama.exe is on PATH
    try {
        $cmd = Get-Command -Name 'ollama' -CommandType Application -ErrorAction Stop
        $result.IsOnPath = $true
        $result.OllamaPath = $cmd.Source
    }
    catch {
        # Not on PATH
        return $result
    }

    # 2. Check if API is responding at localhost:11434
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.WebProxy]::new($null)
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add('Content-Type', 'application/json')

        $null = $wc.DownloadString("$script:OllamaApiBase/api/tags")
        $result.IsRunning = $true
    }
    catch {
        # API not responding
    }

    return $result
}

# =============================================================================
# Function: Start-OllamaService
# =============================================================================

<#
.SYNOPSIS
    在背景啟動 Ollama 服務。

.DESCRIPTION
    使用 Start-Process 以 -WindowStyle Hidden 啟動 'ollama serve'，
    讓服務在背景執行而不顯示主控台視窗。
    啟動後等待指定秒數（預設 3 秒）讓服務初始化，
    然後透過 Test-OllamaAvailable 確認是否成功啟動。

.PARAMETER WaitSeconds
    啟動後等待的秒數，預設為 3。

.OUTPUTS
    [bool] $true 表示服務已成功啟動，$false 表示啟動失敗。

.EXAMPLE
    if (-not (Start-OllamaService)) { Write-Host '無法啟動 Ollama' }
#>
function Start-OllamaService {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$WaitSeconds = 3
    )

    try {
        Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        return $false
    }

    # Wait for service to initialize
    Start-Sleep -Seconds $WaitSeconds

    # Verify the service is now running
    $check = Test-OllamaAvailable
    return $check.IsRunning
}

# =============================================================================
# Function: Get-OllamaModels
# =============================================================================

<#
.SYNOPSIS
    列出本機已安裝的 Ollama 模型。

.DESCRIPTION
    對 http://localhost:11434/api/tags 發送 GET 要求，
    解析回應中的 models 陣列，回傳模型名稱清單。
    使用 System.Net.WebClient 並略過 Proxy（本機連線）。

.OUTPUTS
    [string[]] 已安裝模型的名稱清單；無模型或錯誤時回傳空陣列。

.EXAMPLE
    $models = Get-OllamaModels
    if ($models.Count -eq 0) { Write-Host '尚無已安裝的模型' }
#>
function Get-OllamaModels {
    [CmdletBinding()]
    param()

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.WebProxy]::new($null)
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add('Content-Type', 'application/json')

        $responseText = $wc.DownloadString("$script:OllamaApiBase/api/tags")
        $responseObj = $responseText | ConvertFrom-Json

        if ($null -ne $responseObj.models -and $responseObj.models.Count -gt 0) {
            $names = $responseObj.models | ForEach-Object { $_.name }
            return ,@($names)
        }

        return ,@()
    }
    catch {
        return ,@()
    }
}

# =============================================================================
# Function: Invoke-OllamaPull
# =============================================================================

<#
.SYNOPSIS
    從 Ollama Hub 下載指定模型。

.DESCRIPTION
    對 http://localhost:11434/api/pull 發送 POST 要求以下載模型。
    Ollama 的 pull API 會以串流方式回傳進度（NDJSON），
    此函式會讀取所有回應並解析最終狀態。

    由於 WebClient.UploadString 無法處理串流回應，
    此函式改用 System.Net.HttpWebRequest 讀取串流進度。

.PARAMETER ModelName
    要下載的模型名稱，例如 'llama3.2:3b'。

.OUTPUTS
    [PSCustomObject] 含 Success (bool)、Message (string)。

.EXAMPLE
    $result = Invoke-OllamaPull -ModelName 'llama3.2:3b'
    if ($result.Success) { Write-Host '下載完成' }
    else { Write-Host "下載失敗: $($result.Message)" }
#>
function Invoke-OllamaPull {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModelName
    )

    try {
        $url = "$script:OllamaApiBase/api/pull"
        $body = @{ name = $ModelName; stream = $true } | ConvertTo-Json -Compress

        $request = [System.Net.WebRequest]::CreateHttp($url)
        $request.Method = 'POST'
        $request.ContentType = 'application/json'
        $request.Proxy = [System.Net.WebProxy]::new($null)
        $request.Timeout = [System.Threading.Timeout]::Infinite

        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bodyBytes.Length

        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $requestStream.Close()

        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8)

        $lastStatus = ''
        $success = $false

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $json = $line | ConvertFrom-Json
                if ($null -ne $json.status) {
                    $lastStatus = $json.status
                }
                if ($json.status -eq 'success') {
                    $success = $true
                }
            }
            catch {
                # Skip malformed lines
            }
        }

        $reader.Close()
        $response.Close()

        if ($success) {
            return [PSCustomObject]@{
                Success = $true
                Message = L 'ollama_download_success' $ModelName
            }
        }
        else {
            return [PSCustomObject]@{
                Success = $false
                Message = L 'ollama_download_incomplete' $lastStatus
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = L 'ollama_download_error' $_.Exception.Message
        }
    }
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Test-OllamaAvailable',
    'Start-OllamaService',
    'Get-OllamaModels',
    'Invoke-OllamaPull'
)
