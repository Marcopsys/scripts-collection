Function Start-ConsolidatedCleanup {
    [CmdletBinding(SupportsShouldProcess = $True)]
    Param (
        [Parameter(Mandatory = $false)]
        [ValidateSet("Light","Standard","Deep")]
        [string]$CleanupMode = $null,

        [Parameter(Mandatory = $false)]
        [int]$DaysToDelete = 30
    )

    # If CleanupMode is not provided, prompt the user for a selection
    if (-not $CleanupMode) {
        Write-Host "Choose your cleanup mode (Light = minimal risk, Standard = moderate, Deep = advanced):" -ForegroundColor Cyan
        $choice1 = New-Object System.Management.Automation.Host.ChoiceDescription "&Light", "Light Cleanup"
        $choice2 = New-Object System.Management.Automation.Host.ChoiceDescription "&Standard", "Standard Cleanup"
        $choice3 = New-Object System.Management.Automation.Host.ChoiceDescription "&Deep", "Deep Cleanup"
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($choice1, $choice2, $choice3)
        $chosen = $Host.UI.PromptForChoice("Cleanup Mode", "Select a Cleanup Mode:", $options, 0)
        switch ($chosen) {
            0 { $CleanupMode = "Light" }
            1 { $CleanupMode = "Standard" }
            2 { $CleanupMode = "Deep" }
        }
    }

    # Check for elevation; if not elevated, warn and ask whether to continue with limited (user-level) cleanup
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This script is not running with elevated privileges. Some system-level cleanup tasks will be skipped."
        $choice = Read-Host "Do you want to proceed cleaning only accessible user files? (Y/N)"
        if ($choice -ne "Y") {
            Write-Host "Please restart the script in an elevated PowerShell window." -ForegroundColor Red
            exit
        }
        $elevated = $false
    } else {
        $elevated = $true
    }

    # Define fixed log file path in TEMP folder (timestamp-based)
    $LogFile = "$env:TEMP\" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".log"

    # Start transcript (log the cleanup actions)
    if (Test-Path $LogFile) { Rename-Item -Path $LogFile -NewName ($LogFile + ".old") -ErrorAction SilentlyContinue }
    Start-Transcript -Path $LogFile | Out-Null

    # Start Timer
    $StartTime = Get-Date

    # Gather initial disk usage
    Write-Host "Gathering initial disk usage..." -ForegroundColor Green
    $Before = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } |
        Select-Object SystemName,
                      @{Name = "Drive"; Expression = { $_.DeviceID }},
                      @{Name = "Size (GB)"; Expression = { "{0:N1}" -f ($_.Size / 1GB) }},
                      @{Name = "Free (GB)"; Expression = { "{0:N1}" -f ($_.FreeSpace / 1GB) }},
                      @{Name = "PercentFree"; Expression = { "{0:P1}" -f ($_.FreeSpace / $_.Size) }}

    # Optionally stop Windows Update service if cleaning SoftwareDistribution folder
    $needSoftwareDistCleanup = ($CleanupMode -eq "Standard" -or $CleanupMode -eq "Deep")
    if ($CleanupMode -eq "Light") {
        $promptWU = Read-Host "Would you like to clean Windows Updates as well? (Y/N)"
        if ($promptWU -eq 'Y') { $needSoftwareDistCleanup = $true }
    }
    if ($needSoftwareDistCleanup -and $elevated) {
        Write-Host "Stopping Windows Update service (wuauserv)..." -ForegroundColor Green  # Executes a specific job
        Get-Service -Name wuauserv -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    }

    # Utility function: Removes items older than specified days
    Function Remove-ItemsIfOlder {
        param(
            [string]$Path,
            [int]$AgeInDays
        )
        # Check path accessibility using try/catch
        try {
            $exists = Test-Path $Path -ErrorAction Stop
        } catch {
            $exists = $false
        }
        if ($exists) {   # Executes a specific job
            try {
                Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$AgeInDays) } |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -Verbose
            } catch {
                $errMsg = $_.Exception.Message
                Write-Verbose ("Failed to process ${Path}: ${errMsg}")
            }
        }
    }

    # --- LIGHT CLEANUP STEPS ---
    Write-Host "`n[Performing Light Cleanup Steps]" -ForegroundColor Cyan
    if ($elevated) {
        Remove-ItemsIfOlder -Path "C:\Windows\Temp\*" -AgeInDays $DaysToDelete  # Executes a specific job
    } else {
        Write-Host "Skipping cleaning of C:\Windows\Temp\* (requires elevation)." -ForegroundColor Yellow
    }
    Remove-ItemsIfOlder -Path "C:\Users\*\AppData\Local\Temp\*" -AgeInDays $DaysToDelete  # Executes a specific job
    Remove-ItemsIfOlder -Path "C:\Users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -AgeInDays $DaysToDelete  # Executes a specific job
    if ($elevated) {
        if (Test-Path "C:\$Recycle.Bin" -ErrorAction SilentlyContinue) {
            Remove-Item "C:\$Recycle.Bin" -Recurse -Force -ErrorAction SilentlyContinue -Verbose  # Executes a specific job
        }
    } else {
        Write-Host "Skipping cleaning of Recycle Bin (requires elevation)." -ForegroundColor Yellow
    }
    if ($needSoftwareDistCleanup -and $elevated) {
        if (Test-Path "C:\Windows\SoftwareDistribution" -ErrorAction SilentlyContinue) {
            Remove-Item "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose  # Executes a specific job
        }
    }

    # --- STANDARD CLEANUP STEPS (requires elevation) ---
    if ($CleanupMode -eq "Standard" -or $CleanupMode -eq "Deep") {
        Write-Host "`n[Performing Standard Cleanup Steps]" -ForegroundColor Cyan
        if ($elevated) {
            # Adjust SCCM cache size if applicable
            $sccmCache = Get-WmiObject -Namespace root\ccm\SoftMgmtAgent -Class CacheConfig -ErrorAction SilentlyContinue  # Executes a specific job
            if ($null -ne $sccmCache) {
                $sccmCache.size = 1024 | Out-Null
                $sccmCache.Put() | Out-Null
                Restart-Service ccmexec -ErrorAction SilentlyContinue
            }
            # Remove additional system items
            $pathsToRemove = @(
                "C:\Config.Msi",
                "C:\Intel",
                "C:\PerfLogs",
                "$env:windir\memory.dmp",
                "$env:windir\minidump\*",
                "$env:windir\Prefetch\*",
                "C:\ProgramData\Microsoft\Windows\WER\*"
            )
            foreach ($p in $pathsToRemove) {
                if (Test-Path $p -ErrorAction SilentlyContinue) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue -Verbose }  # Executes a specific job
            }
            # Remove various user caches
            $userCachePaths = @(
                "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatCache\*",
                "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatUaCache\*",
                "C:\Users\*\AppData\Local\Microsoft\Windows\IEDownloadHistory\*",
                "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\*",
                "C:\Users\*\AppData\Local\Microsoft\Windows\INetCookies\*",
                "C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\Cache\*"
            )
            foreach ($ucp in $userCachePaths) {
                if (Test-Path $ucp -ErrorAction SilentlyContinue) { Remove-Item $ucp -Recurse -Force -ErrorAction SilentlyContinue -Verbose }  # Executes a specific job
            }
            # Run Windows Disk Cleanup
            Write-Host "Running Windows Disk Cleanup (/sagerun:1)..." -ForegroundColor Green  # Executes a specific job
            Try {
                Start-Process -FilePath "cleanmgr" -ArgumentList "/sagerun:1" -Wait -ErrorAction Stop -Verbose
            } Catch {
                Write-Warning "CleanMgr is not installed or failed to run. Skipping this step."
            }
        } else {
            Write-Host "Skipping Standard Cleanup tasks (require elevation)." -ForegroundColor Yellow
        }
    }

    # --- DEEP CLEANUP STEPS (requires elevation) ---
    if ($CleanupMode -eq "Deep") {
        Write-Host "`n[Performing Deep Cleanup Steps]" -ForegroundColor Cyan
        if ($elevated) {
            # Remove CBS logs
            if (Test-Path "C:\Windows\Logs\CBS\" -ErrorAction SilentlyContinue) {
                Get-ChildItem "C:\Windows\Logs\CBS\*.log" -Recurse -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Verbose  # Executes a specific job
            }
            # Remove IIS logs older than 60 days
            if (Test-Path "C:\inetpub\logs\LogFiles\" -ErrorAction SilentlyContinue) {
                Get-ChildItem "C:\inetpub\logs\LogFiles\*" -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-60) } |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -Verbose  # Executes a specific job
            }
        } else {
            Write-Host "Skipping Deep Cleanup tasks (require elevation)." -ForegroundColor Yellow
        }
    }

    # --- Restart Windows Update service if it was stopped ---
    if ($needSoftwareDistCleanup -and $elevated) {
        Write-Host "Restarting Windows Update service (wuauserv)..." -ForegroundColor Green  # Executes a specific job
        Get-Service -Name wuauserv -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue
    }

    # --- Prompt to scan for large ISO/VHD/VHDX files ---
    Function PromptForLargeFiles {
        param([string]$ScanPath)
        $scanChoice = Read-Host "Would you like to scan $ScanPath for large *.ISO, *.VHD, or *.VHDX files? (Y/N)"
        if ($scanChoice -eq 'Y') {
            Write-Host "Scanning for large files in $ScanPath..." -ForegroundColor Green  # Executes a specific job
            Get-ChildItem -Path $ScanPath -Include *.iso, *.vhd, *.vhdx, *.msu -Recurse -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending |
                Select-Object Name, Directory, @{Name="Size(GB)";Expression={"{0:N2}" -f ($_.Length / 1GB)}} |
                Format-Table | Out-String | Write-Host
        }
    }
    PromptForLargeFiles -ScanPath "C:\"

    # Gather final disk usage
    Write-Host "`nGathering final disk usage..." -ForegroundColor Green  # Executes a specific job
    $After = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } |
        Select-Object SystemName,
                      @{Name = "Drive"; Expression = { $_.DeviceID }},
                      @{Name = "Size (GB)"; Expression = { "{0:N1}" -f ($_.Size / 1GB) }},
                      @{Name = "Free (GB)"; Expression = { "{0:N1}" -f ($_.FreeSpace / 1GB) }},
                      @{Name = "PercentFree"; Expression = { "{0:P1}" -f ($_.FreeSpace / $_.Size) }}

    # Stop Timer and display summary
    $EndTime = Get-Date
    $Elapsed = ($EndTime - $StartTime).TotalSeconds
    Write-Host "`n=== DISK USAGE BEFORE CLEANUP ===" -ForegroundColor Green
    $Before | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "`n=== DISK USAGE AFTER CLEANUP ===" -ForegroundColor Green
    $After | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "`nHostname:" (hostname) -ForegroundColor Green
    Write-Host "Script started:" $StartTime
    Write-Host "Script ended:  " $EndTime
    Write-Host "Total duration (seconds): $Elapsed"

    # End transcript
    Stop-Transcript | Out-Null
    Write-Host "`nCleanup script finished." -ForegroundColor Green
}

# Invoke function by default
Start-ConsolidatedCleanup
