echo " ███████████                                  ";
echo "░█░░░███░░░█                                  ";
echo "░   ░███  ░   █████  ████████  █████ ███ █████";
echo "    ░███     ███░░  ░░███░░███░░███ ░███░░███ ";
echo "    ░███    ░░█████  ░███ ░███ ░███ ░███ ░███ ";
echo "    ░███     ░░░░███ ░███ ░███ ░░███████████  ";
echo "    █████    ██████  ░███████   ░░████░████   ";
echo "   ░░░░░    ░░░░░░   ░███░░░     ░░░░ ░░░░    ";
echo "                     ░███                     ";
echo "                     █████                    ";
echo "                    ░░░░░                     ";
echo "                a parser-wrapper              ";
echo "                   by placeholder             ";

# ==================== Helpers ====================

# Generic status writer: prints to console AND logs to current log file
function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Default","Info","Success","Warning","Error")]
        [string]$Level = "Default"
    )

    switch ($Level) {
        "Success" { $color = "Green" }
        "Error"   { $color = "Red" }
        "Warning" { $color = "Yellow" }
        "Info"    { $color = "Cyan" }
        default   { $color = "White" }
    }

    Write-Host $Message -ForegroundColor $color

    if ($script:CurrentLogFile) {
        Add-Content -Path $script:CurrentLogFile -Value $Message
    }
}

# For lines like: user johndoe  (only johndoe should be yellow)
function Write-UserInfo {
    param(
        [string]$Prefix,
        [string]$UserName,
        [string]$Suffix = ""
    )

    $line = "$Prefix$UserName$Suffix"

    # Console with colored username
    Write-Host -NoNewline $Prefix
    Write-Host -NoNewline $UserName -ForegroundColor Yellow
    Write-Host $Suffix

    # Log file (no color)
    if ($script:CurrentLogFile) {
        Add-Content -Path $script:CurrentLogFile -Value $line
    }
}

# Get marker path for a processed case
function Get-CaseMarkerPath {
    param(
        [string]$OutDir
    )
    return (Join-Path $OutDir "processing_done.flag")
}

# Check if a case/output directory has already been fully processed
function Test-CaseAlreadyProcessed {
    param(
        [string]$OutDir
    )

    $marker = Get-CaseMarkerPath -OutDir $OutDir
    return (Test-Path $marker)
}

# Mark a case/output directory as processed
function Set-CaseProcessed {
    param(
        [string]$OutDir,
        [string]$CaseName
    )

    $marker = Get-CaseMarkerPath -OutDir $OutDir
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "Processed $CaseName at $ts" | Set-Content -Path $marker
}

# 7-Zip location
$sevenZipPath = 'C:\Program Files\7-Zip\7z.exe'

# Ingest: find all unprocessed KAPE ZIPs under C:\SFTP, extract each with 7z to
# C:\work\data\<zip-basename>, track processed ZIPs in a state file, and return
# a list of folders to process.
function Get-NewKapeCasesFromSftp {
    param(
        [string]$SourceRoot = "C:\work\in",
        [string]$DestRoot,
        [string]$StateFile
    )

    $destFolders = @()

    if (-not (Test-Path $SourceRoot)) {
        Write-Status "SFTP source '$SourceRoot' not found, skipping ingest." -Level Error
        return $destFolders
    }

    if (-not (Test-Path $DestRoot)) {
        New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
    }

    if (-not (Test-Path $sevenZipPath)) {
        Write-Status "7-Zip not found at '$sevenZipPath' – cannot extract KAPE zips." -Level Error
        return $destFolders
    }

    # Load already processed ZIP full paths into a hash set
    $processedSet = New-Object 'System.Collections.Generic.HashSet[string]'
    if (Test-Path $StateFile) {
        Get-Content $StateFile -ErrorAction SilentlyContinue |
            Where-Object { $_.Trim() } |
            ForEach-Object {
                $parts = $_ -split "`t", 2
                if ($parts.Count -eq 2) {
                    [void]$processedSet.Add($parts[1])
                }
            }
    }

    # Find KAPE roots first (directories named like KAPE*)
    $kapeRoots = Get-ChildItem $SourceRoot -Directory -Recurse |
                 Where-Object { $_.Name -like 'KAPE*' }

    if (-not $kapeRoots) {
        Write-Status "No KAPE directories found under '$SourceRoot', nothing to ingest." -Level Warning
        return $destFolders
    }

    # Within all KAPE roots, collect all zip files
    $zipFiles = @()
    foreach ($root in $kapeRoots) {
        $zipFiles += Get-ChildItem -Path $root.FullName -Recurse -File -Filter *.zip -ErrorAction SilentlyContinue
    }

    if (-not $zipFiles) {
        Write-Status "No ZIP files found inside any KAPE directories under '$SourceRoot'." -Level Warning
        return $destFolders
    }

    # Sort zips by time so we process older ones first
    $zipFilesSorted = $zipFiles | Sort-Object LastWriteTime

    foreach ($zip in $zipFilesSorted) {
        if ($processedSet.Contains($zip.FullName)) {
            continue
        }

        Write-Status "Found new KAPE ZIP to process: '$($zip.FullName)'" -Level Info

        $destFolder = Join-Path $DestRoot $zip.BaseName
        Write-Status "Extracting ZIP '$($zip.Name)' to '$destFolder' using 7-Zip..." -Level Info

        try {
            if (-not (Test-Path $destFolder)) {
                New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
            }

            $args = @(
                'x'                 # extract with full paths
                '-y'                # assume Yes on all queries
                "-o$destFolder"     # output folder (7z expects -oDIR with no space)
                $zip.FullName       # input archive
            )

            $proc = Start-Process -FilePath $sevenZipPath -ArgumentList $args -Wait -PassThru -NoNewWindow

            # 7-Zip exit codes:
            # 0 = no error, 1 = warnings, >=2 = fatal error
            if ($proc.ExitCode -ge 2) {
                Write-Status "7-Zip FAILED (exit $($proc.ExitCode)) extracting '$($zip.FullName)'." -Level Error
                continue
            }
        }
        catch {
            Write-Status "Exception while extracting '$($zip.FullName)' with 7-Zip: $($_.Exception.Message)" -Level Error
            continue
        }

        # Sanity check: dest folder must exist and have content
        if (-not (Test-Path $destFolder) -or
            (Get-ChildItem $destFolder -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {

            Write-Status "Extraction finished but '$destFolder' appears empty." -Level Error
            continue
        }

        # Log processed ZIP so we know what was ingested
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $StateFile -Value "$ts`t$($zip.FullName)"
        [void]$processedSet.Add($zip.FullName)

        Write-Status "Ingested '$($zip.FullName)' into '$destFolder' and logged to '$StateFile'." -Level Success

        $destFolders += $destFolder
    }

    if (-not $destFolders) {
        Write-Status "No new KAPE ZIPs to ingest. All ZIPs in '$SourceRoot' are already processed." -Level Info
    }

    return $destFolders
}

# ================= Script starts here =================

$scriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Base folders
$baseWork      = "C:\work\data"
$zimmermanRoot = "C:\work\Get-ZimmermanTools\net6"
$chainsawRoot  = "C:\work\chainsaw_x86_64-pc-windows-msvc\chainsaw"

# Ingest logs & state
$ingestLog  = Join-Path $baseWork "sftp_ingest.log"
$stateFile  = Join-Path $baseWork "sftp_processed.log"

# Ingest phase
$script:CurrentLogFile = $ingestLog
Write-Status "=== SFTP ingest phase ===" -Level Info
$caseFolders = Get-NewKapeCasesFromSftp -SourceRoot "C:\work\in" -DestRoot $baseWork -StateFile $stateFile
Write-Status "=== SFTP ingest done ===" -Level Info

if (-not $caseFolders -or $caseFolders.Count -eq 0) {
    Write-Status "No new extracted KAPE folders to process. Exiting." -Level Info
    $scriptStopwatch.Stop()
    Write-Status ("Script finished in {0}" -f $scriptStopwatch.Elapsed) -Level Info
    return
}

# Build case objects from folder paths
$cases = @()
foreach ($folder in $caseFolders) {
    $item = Get-Item $folder -ErrorAction SilentlyContinue
    if ($item -and $item.PSIsContainer) {
        $cases += $item
    }
    else {
        Write-Status "Ignoring non-directory case folder '$folder'." -Level Warning
    }
}

if (-not $cases -or $cases.Count -eq 0) {
    Write-Status "No valid case directories after ingest. Exiting." -Level Warning
    $scriptStopwatch.Stop()
    Write-Status ("Script finished in {0}" -f $scriptStopwatch.Elapsed) -Level Info
    return
}

foreach ($case in $cases) {
    $root     = $case.FullName              # e.g. C:\work\data\2025-11-20T115736_Test20_11-25
    $caseName = $case.Name                  # e.g. 2025-11-20T115736_Test20_11-25

    # Output folder per case
    $outDir = Join-Path $baseWork "out_$caseName"
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    # Check if this case has already been processed
    if (Test-CaseAlreadyProcessed -OutDir $outDir) {
        $script:CurrentLogFile = Join-Path $outDir "tools.log"
        Write-Status "Case '$caseName' is already marked as processed. Skipping all tools." -Level Info
        continue
    }

    # Case-level log (only main thread writes here)
    $caseLog = Join-Path $outDir "tools.log"

    # Make log helpers aware of current case/log (for top-level messages)
    $script:CurrentLogFile  = $caseLog
    $script:CurrentCaseName = $caseName

    # Convenience paths
    $cRoot     = Join-Path $root 'C'
    $usersRoot = Join-Path $cRoot 'Users'

    Write-Status "==================================================" -Level Info
    Write-Status "Processing case: $caseName" -Level Info
    Write-Status "  Root   -> $root" -Level Info
    Write-Status "  Output -> $outDir" -Level Info
    Write-Status "  Log    -> $caseLog" -Level Info
    Write-Status "==================================================" -Level Info
    Add-Content -Path $caseLog -Value "===== Processing $caseName started at $(Get-Date) ====="

    # ---------------- Build jobs for this case ----------------
    $jobs = @()

    # 1) EvtxECmd - Windows Event Logs
    $evtxLog = Join-Path $outDir "EvtxECmd.log"
    $jobs += Start-Job -Name "EvtxECmd-$caseName" -ScriptBlock {
        param($zimmermanRoot, $cRoot, $outDir, $toolLog, $caseName)

        $name = "EvtxECmd"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $zimmermanRoot 'EvtxeCmd\EvtxECmd.exe') `
                -d (Join-Path $cRoot 'Windows\System32\winevt\logs') `
                --csv $outDir --csvf 'evtxecmd.csv' *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $zimmermanRoot, $cRoot, $outDir, $evtxLog, $caseName

    # 2) JLECmd - Recent items for each non-system user (one job per user)

    if (-not (Test-Path $usersRoot)) {
        Write-Status "  [JLECmd] Users root '$usersRoot' not found, skipping JLECmd for this case" -Level Warning
    }
    else {
        $userProfiles = Get-ChildItem $usersRoot -Directory |
            Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

        if (-not $userProfiles) {
            Write-Status "  [JLECmd] No non-system user profiles found under '$usersRoot', skipping JLECmd" -Level Warning
        }
        else {
            foreach ($profile in $userProfiles) {
                $userName   = $profile.Name
                $userRoot   = $profile.FullName
                $recentPath = Join-Path $userRoot 'AppData\Roaming\Microsoft\Windows\Recent'

                if (Test-Path $recentPath) {
                    Write-UserInfo "  [JLECmd] Scheduling for user '" $userName "'..."
                    $jleLog = Join-Path $outDir ("JLECmd_{0}.log" -f $userName)

                    $jobs += Start-Job -Name "JLECmd-$caseName-$userName" -ScriptBlock {
                        param($zimmermanRoot, $recentPath, $outDir, $toolLog, $userName, $caseName)

                        $name = "JLECmd ($userName)"
                        $sw = [System.Diagnostics.Stopwatch]::StartNew()
                        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
                        try {
                            & (Join-Path $zimmermanRoot 'JLECmd.exe') `
                                -d $recentPath `
                                --csv $outDir --csvf ("jlecmd_{0}.csv" -f $userName) *>> $toolLog

                            $sw.Stop()
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
                            } else {
                                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
                            }
                        } catch {
                            $sw.Stop()
                            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
                            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
                        }
                    } -ArgumentList $zimmermanRoot, $recentPath, $outDir, $jleLog, $userName, $caseName
                }
                else {
                    Write-UserInfo "  [JLECmd] Skipped user '" $userName "' – Recent path missing: $recentPath"
                }
            }
        }
    }

    # 3) MFTECmd - $MFT
    $mftLog = Join-Path $outDir "MFTECmd.log"
    $jobs += Start-Job -Name "MFTECmd-$caseName" -ScriptBlock {
        param($zimmermanRoot, $cRoot, $outDir, $toolLog, $caseName)

        $name = "MFTECmd"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $zimmermanRoot 'MFTECmd.exe') `
                -f (Join-Path $cRoot '$MFT') `
                --csv $outDir --csvf 'mft.csv' *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $zimmermanRoot, $cRoot, $outDir, $mftLog, $caseName

    # 4) AmcacheParser
    $amcacheLog = Join-Path $outDir "AmcacheParser.log"
    $jobs += Start-Job -Name "AmcacheParser-$caseName" -ScriptBlock {
        param($zimmermanRoot, $cRoot, $outDir, $toolLog, $caseName)

        $name = "AmcacheParser"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $zimmermanRoot 'AmcacheParser.exe') `
                -f (Join-Path $cRoot 'Windows\AppCompat\Programs\Amcache.hve') `
                --csv $outDir --csvf 'amcache.csv' *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $zimmermanRoot, $cRoot, $outDir, $amcacheLog, $caseName

    # 5) AppCompatCacheParser
    $appcompatLog = Join-Path $outDir "AppCompatCacheParser.log"
    $jobs += Start-Job -Name "AppCompatCacheParser-$caseName" -ScriptBlock {
        param($zimmermanRoot, $cRoot, $outDir, $toolLog, $caseName)

        $name = "AppCompatCacheParser"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $zimmermanRoot 'AppCompatCacheParser.exe') `
                -f (Join-Path $cRoot 'Windows\System32\config\SYSTEM') `
                --csv $outDir --csvf 'appcompatcache.csv' *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $zimmermanRoot, $cRoot, $outDir, $appcompatLog, $caseName

    # 6) SQLECmd
    $sqleLog = Join-Path $outDir "SQLECmd.log"
    $jobs += Start-Job -Name "SQLECmd-$caseName" -ScriptBlock {
        param($zimmermanRoot, $usersRoot, $outDir, $toolLog, $caseName)

        $name = "SQLECmd"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $zimmermanRoot 'SQLECmd\SQLECmd.exe') `
                -d $usersRoot `
                --csv $outDir *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $zimmermanRoot, $usersRoot, $outDir, $sqleLog, $caseName

    # 7) SrumECmd
    $srumLog = Join-Path $outDir "SrumECmd.log"
    $jobs += Start-Job -Name "SrumECmd-$caseName" -ScriptBlock {
        param($zimmermanRoot, $cRoot, $outDir, $toolLog, $caseName)

        $name = "SrumECmd"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $zimmermanRoot 'SrumECmd.exe') `
                -f (Join-Path $cRoot 'Windows\System32\SRU\SRUDB.dat') `
                -r (Join-Path $cRoot 'Windows\System32\config\SOFTWARE') `
                --csv $outDir *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $zimmermanRoot, $cRoot, $outDir, $srumLog, $caseName

    # 8) Chainsaw
    $chainsawLog = Join-Path $outDir "Chainsaw.log"
    $jobs += Start-Job -Name "Chainsaw-$caseName" -ScriptBlock {
        param($chainsawRoot, $cRoot, $outDir, $toolLog, $caseName)

        $name = "Chainsaw"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Add-Content -Path $toolLog -Value "[$caseName] [$name] Starting at $(Get-Date)"
        try {
            & (Join-Path $chainsawRoot 'chainsaw.exe') `
                hunt (Join-Path $cRoot 'Windows\System32\winevt\logs') `
                -s (Join-Path $chainsawRoot 'sigma') `
                --mapping (Join-Path $chainsawRoot 'mappings\sigma-event-logs-all.yml') `
                -r (Join-Path $chainsawRoot 'rules') `
                --csv -o $outDir *>> $toolLog

            $sw.Stop()
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$caseName] [$name] Completed successfully in $($sw.Elapsed)" -ForegroundColor Green
            } else {
                Write-Host "[$caseName] [$name] Completed with exit code $LASTEXITCODE in $($sw.Elapsed)" -ForegroundColor Red
            }
        } catch {
            $sw.Stop()
            Write-Host "[$caseName] [$name] FAILED in $($sw.Elapsed): $($_.Exception.Message)" -ForegroundColor Red
            Add-Content -Path $toolLog -Value "[$caseName] [$name] ERROR: $($_.Exception.ToString())"
        }
    } -ArgumentList $chainsawRoot, $cRoot, $outDir, $chainsawLog, $caseName

    # ---------------- Run jobs and wait ----------------
    Write-Status "Started $($jobs.Count) jobs for case $caseName, waiting for completion..." -Level Info

    Wait-Job -Job $jobs | Out-Null
    Receive-Job -Job $jobs | Out-Null
    Remove-Job -Job $jobs

    # Mark case as processed
    Set-CaseProcessed -OutDir $outDir -CaseName $caseName

    Add-Content -Path $caseLog -Value "===== Finished $caseName at $(Get-Date) ====="
    Write-Status "Finished case: $caseName" -Level Info
    Write-Status "--------------------------------------------------" -Level Info
}

$scriptStopwatch.Stop()
Write-Status ("All cases completed in {0}" -f $scriptStopwatch.Elapsed) -Level Success
