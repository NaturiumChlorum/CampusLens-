param(
  [string]$ProjectRoot = 'D:\CampusLens',
  [string]$DevEcoRoot = 'D:\devecostudio\DevEco Studio',
  [string]$Target = ''
)
$ErrorActionPreference = 'Stop'
$hdc = Join-Path $DevEcoRoot 'sdk\default\openharmony\toolchains\hdc.exe'
$node = Join-Path $DevEcoRoot 'tools\node\node.exe'
function Invoke-HdcChecked([string[]]$Arguments) {
  $result = (& $hdc @Arguments 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or $result -match '\[Fail\]') { throw $result }
  return $result
}
$health = $null
try { $health = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 3 -Proxy $null } catch { }
if ($null -eq $health) {
  $existing = Get-NetTCPConnection -State Listen -LocalPort 3000 -ErrorAction SilentlyContinue
  if ($existing) { throw 'PC 3000 已被占用，但 /health 无法返回；请先检查对应进程，不要重复启动。' }
  $logDir = Join-Path $ProjectRoot '.test\gateway'
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $envFile = Join-Path $ProjectRoot '.env'
  $server = Join-Path $ProjectRoot 'server\src\server.mjs'
  $gatewayProcess = Start-Process -FilePath $node -ArgumentList @('--env-file="' + $envFile + '"', '"' + $server + '"') -WorkingDirectory $ProjectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'stdout.log') -RedirectStandardError (Join-Path $logDir 'stderr.log') -PassThru
  for ($attempt=0; $attempt -lt 15; $attempt++) {
    Start-Sleep -Milliseconds 400
    try { $health = Invoke-RestMethod 'http://127.0.0.1:3000/health' -TimeoutSec 2 -Proxy $null; break } catch { }
    if ($gatewayProcess.HasExited) { throw "网关退出，请查看 $logDir\stderr.log" }
  }
  if ($null -eq $health) { throw "网关启动后健康检查未通过，请查看 $logDir" }
}
if ($health.status -ne 'ok' -or $null -eq $health.configured -or [string]::IsNullOrWhiteSpace($health.model)) { throw '3000 端口响应不是预期的 CampusLens 健康检查。' }
if (-not $health.configured) { throw '网关已启动，但未配置 LLM_API_KEY。' }
if ([string]::IsNullOrWhiteSpace($Target)) {
  $targetLines = (Invoke-HdcChecked @('list','targets')) -split '\r?\n' | Where-Object { $_.Trim() -and $_ -notmatch '^\[' }
  if (@($targetLines).Count -ne 1) { throw '请启动一个模拟器，或用 -Target 指定 hdc list targets 中的设备。' }
  $Target = @($targetLines)[0].Trim()
}
$rules = Invoke-HdcChecked @('-t',$Target,'fport','ls')
if ($rules -notmatch ([regex]::Escape($Target) + '\s+tcp:3000 tcp:3000\s+\[Reverse\]')) {
  try { Invoke-HdcChecked @('-t',$Target,'rport','tcp:3000','tcp:3000') | Write-Output }
  catch { throw "无法建立设备 3000 -> PC 3000 转发：$_`n若列表为空却提示 Port listen failed，请重启当前模拟器后重跑本脚本；不要忽略此错误。" }
}
Invoke-HdcChecked @('-t',$Target,'fport','ls') | Write-Output
Write-Output 'PC 健康检查通过。应用连接地址：http://127.0.0.1:3000'
Write-Output '这只验证网关及转发建立；请在应用执行真实任务统计完成业务验收。'
