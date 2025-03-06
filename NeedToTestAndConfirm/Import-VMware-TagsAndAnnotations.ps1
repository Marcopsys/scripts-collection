<#
.SYNOPSIS
    Imports VMware vSphere VM Tags, Annotations, and Resource Pools from CSV files.
.DESCRIPTION
    This script reads CSV files containing tags, annotations, and resource pool assignments
    and applies them to virtual machines in a specified vCenter. Useful for vCenter migrations
    or restoring metadata after a disaster recovery.

.AUTHOR
    marcopsys
.VERSION
    v2.0 - 2025-03-04
.PARAMETER vCenter
    The name of the target vCenter server.
.PARAMETER FileAttribute
    CSV file containing VM annotations.
.PARAMETER FileTag
    CSV file containing VM tags.
.PARAMETER FilePool
    CSV file containing VM resource pool assignments.
.EXAMPLE
    .\Import-VMware-TagsAndAnnotations.ps1 -vCenter "my-vcenter" -FileAttribute "C:\Imports\VMAnnotations.csv" -FileTag "C:\Imports\VMTags.csv" -FilePool "C:\Imports\VMPools.csv"
.REQUIREMENTS
    - VMware PowerCLI installed
    - (need to confirm on recent vsphere)
#>

# Import VMware PowerCLI module if not already loaded
if (-not (Get-Module VMware.PowerCLI)) {
    Write-Host "VMware.PowerCLI module is required. Installing..." -ForegroundColor Yellow
    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
}

# Parameters for dynamic configuration
param(
    [string]$vCenter,
    [string]$FileAttribute,
    [string]$FileTag,
    [string]$FilePool
)

# Define log file for debugging and auditing purposes
$LogFile = "C:\Logs\Import-VMware-TagsAndAnnotations.log"
Function Write-Log {
    Param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
}

# Connect to vCenter
Write-Log "Connecting to vCenter: $vCenter"
Connect-VIServer -Server $vCenter -ErrorAction Stop

# Import and apply annotations
if (Test-Path $FileAttribute) {
    $Annotations = Import-Csv -Path $FileAttribute
    foreach ($Entry in $Annotations) {
        $VM = Get-VM -Name $Entry.VM -ErrorAction SilentlyContinue
        if ($VM) {
            Set-Annotation -Entity $VM -CustomAttribute $Entry.Name -Value $Entry.Value
            Write-Log "Applied annotation to VM: $($Entry.VM) - $($Entry.Name) = $($Entry.Value)"
        }
    }
} else {
    Write-Log "Attribute file not found: $FileAttribute"
}

# Import and apply tags
if (Test-Path $FileTag) {
    $Tags = Import-Csv -Path $FileTag
    foreach ($Entry in $Tags) {
        $VM = Get-VM -Name $Entry.VM -ErrorAction SilentlyContinue
        if ($VM) {
            New-TagAssignment -Entity $VM -Tag $Entry.Tag
            Write-Log "Applied tag to VM: $($Entry.VM) - $($Entry.Tag)"
        }
    }
} else {
    Write-Log "Tag file not found: $FileTag"
}

# Import and assign resource pools
if (Test-Path $FilePool) {
    $Pools = Import-Csv -Path $FilePool
    foreach ($Entry in $Pools) {
        $VM = Get-VM -Name $Entry.VM -ErrorAction SilentlyContinue
        $ResourcePool = Get-ResourcePool -Name $Entry.Pool -ErrorAction SilentlyContinue
        if ($VM -and $ResourcePool) {
            Move-VM -VM $VM -Destination $ResourcePool -Confirm:$false
            Write-Log "Moved VM to resource pool: $($Entry.VM) -> $($Entry.Pool)"
        }
    }
} else {
    Write-Log "Resource pool file not found: $FilePool"
}

Write-Log "Import process completed."
Write-Host "Import completed successfully." -ForegroundColor Green
