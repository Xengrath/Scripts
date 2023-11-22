<#
.SYNOPSIS
	This script is used to detect if a device is a laptop and if it has had its power options configured previously.
.DESCRIPTION
	This script is used to detect if a device is a laptop and if it has had its power options configured previously.
    It determines if power options have been applied previously by the presence of a log file.
    It is intended to be run as the detection script of a Remediation from Microsoft Intune
.NOTES
	Author:         Timothy Ransom
    Version:        1.0.0
    Version Date:   22-NOV-2023

    1.0.0 - (22-NOV-2023) - Script Created

#>

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

Function Test-LaptopHardware
{
    Param([string]$computer = "localhost")
    $isLaptop = $false
    # Check if the machine has a battery (indicating it's a laptop)
    $battery = Get-WmiObject -Class Win32_Battery -ComputerName $computer
    if ($battery) {
        $isLaptop = $true
    }
    $isLaptop
}


## Create Text File with VLC Media Player File Detection Method
$FilePath = "$($env:windir)\Temp\PowerOptionsLaptops_Detection_v1.txt"

##*===============================================
##* DETECTION
##*===============================================

$isLaptop = Test-LaptopHardware -Computer $env:COMPUTERNAME
if ($isLaptop -and (Test-Path $FilePath)) {
    Write-Output "Power Options have been applied, Exiting."
    Exit 0
}
elseif (-not $isLaptop) {
    Write-Output "Device is not a laptop, Exiting."
    Exit 0
}
else {
    Write-Output "Power Options have not been applied, Running Remediation..."
    Exit 1
}
