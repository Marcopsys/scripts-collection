<#
.SYNOPSIS
    Exports VMware vSphere VM Tags and Annotations.
.DESCRIPTION
    This script retrieves tags and annotations applied to VMs in a specified datacenter.
    Useful for vCenter migration, backup, or metadata audit of VMs.

.AUTHOR
    marcopsys
.VERSION
    v2.0 - 2025-03-04
.PARAMETER DatacenterName
    The name of the target datacenter for exporting tags and annotations.
.EXAMPLE
    .\Export-VMware-TagsAndAnnotations.ps1 -DatacenterName "MyDatacenter"
.REQUIREMENTS
    - VMware PowerCLI installed
    - Works on vSphere 6.5+
#>

# Import VMware PowerCLI module if not loaded
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "VMware.PowerCLI module is required. Installing..." -ForegroundColor Yellow
    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
}

# Parameter to avoid hardcoded values
param(
    [string]$DatacenterName = "MyDatacenter"
)

# Define log file for debugging and auditing purposes
$LogFile = "C:\Logs\Export-VMware-TagsAndAnnotations.log"
Function Write-Log {
    Param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
}

# Check if connected to a vCenter before proceeding
if (-not (Get-View ServiceInstance)) {
    Write-Log "Connection to vCenter required. Execution aborted."
    Exit 1
}

Write-Log "Starting export of tags and annotations for datacenter: $DatacenterName"

# Retrieve all virtual machines from the specified datacenter
$VMs = Get-Datacenter -Name $DatacenterName | Get-VM

# Initialize an empty array to store annotation results
$AnnotationsResults = @()

# Loop through each VM to extract its annotations
foreach ($VM in $VMs) {
    $Annotations = $VM | Get-Annotation
    foreach ($Annotation in $Annotations) {
        $Report = [PSCustomObject]@{
            VM   = $VM.Name  # Store VM name
            Name  = $Annotation.Name  # Annotation name
            Value = $Annotation.Value  # Annotation value
        }
        $AnnotationsResults += $Report
    }
}

# Define export file path for annotations
$AnnotationsExportFile = "C:\Exports\VMware_VMAnnotations_$DatacenterName.csv"
$AnnotationsResults | Export-Csv -Path $AnnotationsExportFile -NoTypeInformation -Encoding UTF8

# Initialize an empty array to store tag results
$TagsResults = @()

# Loop through each VM to extract its assigned tags
foreach ($VM in $VMs) {
    $Tags = Get-TagAssignment -Entity $VM
    foreach ($Tag in $Tags) {
        $Report2 = [PSCustomObject]@{
            VM  = $Tag.Entity  # Store VM name
            Tag = $Tag.Tag.Name  # Store assigned tag
        }
        $TagsResults += $Report2
    }
}

# Define export file path for tags
$TagsExportFile = "C:\Exports\VMware_VMTags_$DatacenterName.csv"
$TagsResults | Export-Csv -Path $TagsExportFile -NoTypeInformation -Encoding UTF8

Write-Log "Export completed: $AnnotationsExportFile & $TagsExportFile"
Write-Host "Export completed. Files available: $AnnotationsExportFile & $TagsExportFile" -ForegroundColor Green
