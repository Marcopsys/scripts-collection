<#
.SYNOPSIS
    Analyzes folder sizes and exports results to a CSV file.
.DESCRIPTION
    This script scans a specified directory, retrieves folder sizes, owner information, 
    and last modification/access times, then exports the data to a CSV file.
    It is useful for tracking storage usage and maintaining weekly reports.

.AUTHOR
    marcopsys
.VERSION
    v1.1 - 2020-11-09 (latest update)
.PARAMETER pathtoscan
    UNC path of the directory to analyze.
.PARAMETER csvout
    Path to the output CSV file.
.PARAMETER level
    Optional depth level for scanning subdirectories.
.EXAMPLE
    .\Analyze-Folder-Sizes.ps1 -pathtoscan "\\?\UNC\srvdocts\documents\applications metiers" -csvout "C:\Reports\FolderSizes.csv" -level 2
.REQUIREMENTS
    - PowerShell 5.1+
    - Administrator privileges may be required for full access.
#>

#region Parameters
[CmdletBinding()]
param (
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [String]$pathtoscan,
    
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [String]$csvout,
    
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int]$level
)
#endregion

#region Initialization
Clear-Host 
Write-Host (Get-Date) ": Starting folder size analysis..."
$Starters = (Get-Date)

# Retrieve directories within the specified path
$pname = Get-ChildItem -Directory -Force -LiteralPath $pathtoscan -Depth $level

# Ensure the CSV file exists before writing
New-Item -ItemType "file" -Path $csvout -Force | Out-Null

# Write headers to the CSV file
"DOSSER`tfullPath`tOwner`tSize(MB)`tLast Modified`tLast Access" | Out-File -FilePath $csvout -Width 500
#endregion

#region Folder Analysis
foreach ($foldertoscan in $pname) {
    $prof_lpath = $foldertoscan.FullName
    $prof_name = $foldertoscan.Name
    $powner = (Get-Acl $foldertoscan.FullName).Owner
    $lastwtime = $foldertoscan.LastWriteTime
    $lastatime = $foldertoscan.LastAccessTime

    Write-Host (Get-Date) ": Scanning $prof_name..." -ForegroundColor White -BackgroundColor Black
    
    # Calculate folder size
    $ts = (Get-ChildItem -LiteralPath $prof_lpath -File -Recurse | Measure-Object -Sum Length).Sum / 1MB
    Write-Host (Get-Date) ": Size: $ts MB"
    
    # Append results to CSV
    "$prof_name`t$prof_lpath`t$powner`t$ts`t$lastwtime`t$lastatime" | Out-File -FilePath $csvout -Append -Width 500
}
#endregion

#region Completion
$Enders = (Get-Date)
Write-Host (Get-Date) ": Elapsed Time: $(($Enders - $Starters).TotalSeconds) seconds" -ForegroundColor Green
#endregion