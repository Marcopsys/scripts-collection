<#
.SYNOPSIS
    Executes Varonis Data Classification Engine (DCE) lifecycle jobs.
.DESCRIPTION
    This script automates the execution of necessary jobs for processing new files or rules
    in the Varonis Data Classification Engine, following the documented DCE lifecycle.
    It requires the Varonis PowerShell module and connects to a Varonis DSP server.

.AUTHOR
    marcopsys
.VERSION
    v1.0 - 2023-03-14
.PARAMETER filer
    The name of the file server to scan.
.EXAMPLE
    powershell "C:\Run-Varonis-DCE-Jobs.ps1" -filer WIN-FILER
.REQUIREMENTS
    - PowerShell 5.1+
    - VaronisManagement PowerShell module installed
#>

#region Import and Prerequisites
Write-Host -ForegroundColor Red  "Starting Varonis DCE Lifecycle Script..."
Import-Module -Name VaronisManagement

# Connect to Varonis Infrastructure
Connect-Idu

# Creating a global variable for storing job mappings
$global:varonisJobs = @{}
#endregion

#region Functions
function Get-VaronisJobs {
    # Load or create a cache of available Varonis jobs
    $hashTable = @{}
    $varonisJobsCacheFile = "$PSScriptRoot\varonisJobsCache.csv"

    if (Test-Path $varonisJobsCacheFile) {
        foreach ($line in Get-Content $varonisJobsCacheFile) {
            $jobDetails = $line.Split(",")
            if (-not $hashTable.Contains($jobDetails[0])) {
                $hashTable.Add($jobDetails[0], $jobDetails[1])
            }
        }
        Write-Host "Loading Jobs From Cache File..." -ForegroundColor Green
    } else {
        Write-Host "Building New Jobs Cache File" -ForegroundColor Green
        $varonisJobs = Get-VaronisJob -Name *
        foreach ($varonisJob in $varonisJobs) {
            $jobDescription = $varonisJob.Description
            $jobId = $varonisJob.ID.Value
            try {
                $hashTable.Add($jobDescription, $jobId)
                Add-Content -Path $varonisJobsCacheFile "$jobDescription,$jobId"
            } catch {
                Write-Host "Duplicate Job Found: '$jobDescription'" -ForegroundColor Yellow
            }
        }
        Write-Host "New Jobs Cache File Generated..." -ForegroundColor Green
    }
    $global:varonisJobs = $hashTable
}

function Run-VaronisJob($jobName) {
    # Executes a specific Varonis job
    if ($global:varonisJobs.ContainsKey($jobName)) {
        $jobId = $global:varonisJobs[$jobName]
        Write-Host "Running '$jobName'..." -ForegroundColor Green
        Start-Job -ID $jobId | Out-Null
        while (Test-JobRunning -Name $jobName) {
            Start-Sleep -Seconds 5
        }
        $lastJobExecution = Get-LastJobExecution -ID $jobId
        Write-Host "'$jobName' Finished @ $($lastJobExecution.TimeFinished)" -ForegroundColor Cyan
    } else {
        Write-Host "Job '$jobName' Not Found" -ForegroundColor Red
    }
}

function Run-JobSequence($jobSequence) {
    # Runs a sequence of jobs in order
    foreach ($job in $jobSequence) {
        Run-VaronisJob -jobName $job
    }
}

function Update-DceFull($fwjob) {
    # Job sequence for full DCE lifecycle execution
    $jobSequence = (
        "$fwjob", "Collector Data Transferring", "Collector FileWalk Data Delivery", "Collector FileWalk Data Processing",
        "Pull Walks :: Processing", "Pull Walks :: Publishing", "DCE and DW User Sync", "DCE and DW - Notification service",
        "DCE and DW Pulling Bounded Sync", "DCE and DW - Notification service", "Collector DCE and DW Send Workload",
        "Collector DCE Delivery", "DCE and DW - Allocate DirID for Classification Results", "$fwjob",
        "Collector Data Transferring", "Collector FileWalk Data Delivery", "Collector FileWalk Data Processing",
        "Pull Walks :: Processing", "Pull Walks :: Publishing", "Pull DCE :: Processing", "Pull DCE :: Publishing"
    )
    Run-JobSequence -jobSequence $jobSequence
}
#endregion

#region Selecting and Running Jobs
Get-VaronisJobs
$jobs = $global:varonisJobs.GetEnumerator()
$Filewalks = @{}
$FWnumber = 0

foreach ($job in $jobs) {
    if ($job.Key -match '^FileWalk') {
        $FWnumber++
        $Filewalks.Add("$FWnumber", $job.Key)
    }
}

Write-Host "Found $($Filewalks.Count) Filewalk jobs." -ForegroundColor Yellow
Write-Host "Select one to start the DCE Lifecycle:" -ForegroundColor Green
$Filewalks.Keys | ForEach-Object { Write-Host "[$_]: $($Filewalks[$_])" }
Write-Host "[0]: Skip filewalk"
$choice = Read-Host "Enter option number"

switch ($choice) {
    { $Filewalks.ContainsKey($choice) } { Write-Host "You selected: $($Filewalks[$choice])"; Update-DceFull -fwjob $($Filewalks[$choice]) }
    { $_ -eq '0' } { Write-Host "Skipping FileWalk..." -ForegroundColor Red; Update-DceFull -fwjob "" }
    default { Write-Host "Invalid option selected" -ForegroundColor Red }
}
#endregion
