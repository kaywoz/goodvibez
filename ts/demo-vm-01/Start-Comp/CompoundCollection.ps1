<#
.SYNOPSIS

#>
# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
 if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
  $CommandLine = "-ExecutionPolicy Bypass -File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
  Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
  Exit
 }
}
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

# --- KONFIGURATION ---
$SysmonExe  = "C:\Tools\sysmon64.exe"
$HartongXml = "C:\Tools\sysmonconfig.xml"
$KapeExe    = "C:\Tools\KAPE\kape.exe"
$DelaySec   = 10  # 10 secs
$Timestamp = Get-Date -Format "yyMMdd-HHmm"
$ZipName = "KapeCollect-demo-vm-01-$Timestamp"


Write-Host "--- Configurating Sysmon ---" -ForegroundColor Cyan

$SysmonService = Get-Service "Sysmon64" -ErrorAction SilentlyContinue

if ($SysmonService) {
    Write-Host "Sysmon is already installed , updating config."
    Start-Process $SysmonExe -ArgumentList "-c `"$HartongXml`"" -Wait
    
    if ($SysmonService.Status -ne 'Running') {
        Write-Host "Starting Sysmon"
        Start-Service "Sysmon64"
    }
} else {
    Write-Host "Sysmon missing. Installing with Hartong-config..."
    Start-Process $SysmonExe -ArgumentList "-i `"$HartongXml`" -accepteula" -Wait
}

Write-Host "--- Sysmon collecting data for $DelaySec seconds ---" -ForegroundColor Yellow
Start-Sleep -Seconds $DelaySec



Write-Host "Starting KAPE" -ForegroundColor Cyan

& $KapeExe --tsource C: --tdest C:\KAPE_output --tflush --target CompoundCollection --scs $ip --scp 22 --scu $user --scpw '$password' --scd "SFTP" --zip $ZipName --debug



Write-Host "KAPE Done." -ForegroundColor Green



Write-Host "--- Uninstalling Sysmon ---" -ForegroundColor Magenta

Start-Process $SysmonExe -ArgumentList "-u" -Wait

Write-Host "Done." -ForegroundColor Green