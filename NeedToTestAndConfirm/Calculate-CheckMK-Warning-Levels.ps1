<#
.SYNOPSIS
    Calculates CheckMK warning and critical levels using the "magic factor."
.DESCRIPTION
    This script automates the calculation of warning and critical thresholds for filesystem monitoring
    based on the "magic factor" used in CheckMK. The script allows setting a normalized disk size for scaling.

.AUTHOR
    marcopsys
.VERSION
    v1.0 - 2021-03-04
.PARAMETER Size_gb
    The total size of the disk or shared storage in GB.
.PARAMETER MagicFactor
    The scaling factor (between 0.5 and 1.0) that influences the threshold calculation.
.PARAMETER Normsize
    The baseline size (in GB) used for normalization in CheckMK calculations.
.EXAMPLE
    .\Calculate-CheckMK-Warning-Levels.ps1 -Size_gb 100
.REQUIREMENTS
    - PowerShell 5.1+
#>

#region Parameters
param (
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [double]$Size_gb,
    
    [double]$MagicFactor = 0.8,  # Magic factor, range 0.5 to 1.0
    [double]$Normsize = 20  # Default normalized size in GB
)
#endregion

#region Calculation
Write-Host "Calculating warning and critical levels using CheckMK methodology..." -ForegroundColor Cyan

# Define standard warning and critical levels
$warn = 90
$crit = 95

# Apply CheckMK scaling calculations
$Hgb_Size = $Size_gb / $Normsize
$Felt_Size = [Math]::Pow($Hgb_Size, $MagicFactor)
$Scale = $Felt_Size / $Hgb_Size

$CalculWarn = 100 - ((100 - $warn) * $Scale)
$CalculCrit = 100 - ((100 - $crit) * $Scale)

Write-Host "Computed Warning Level: $CalculWarn%" -ForegroundColor Yellow
Write-Host "Computed Critical Level: $CalculCrit%" -ForegroundColor Red
#endregion
