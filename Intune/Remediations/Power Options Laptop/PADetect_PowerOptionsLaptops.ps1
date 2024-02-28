<#
.SYNOPSIS
	This script is used to detect if a device is a laptop and if it has had its power options configured previously.
.DESCRIPTION
	This script is used to detect if a device is a laptop and if it has had its power options configured previously.
    It determines if power options have been applied previously by the presence of a log file.
    It is intended to be run as the detection script of a Remediation from Microsoft Intune
.NOTES
	Author:         Timothy Ransom
    Version:        2.0.0
    Version Date:   28-DEC-2023

    1.0.0 - (22-NOV-2023) - Script Created
    2.0.0 - (28-DEC-2023) - Function renamed to 'Test-Laptop'
                          - Test-Laptop uses Chassis type to determine if computer is a laptop
                          - Re-ordered the detection logic for improved clarity

#>

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

Function Test-Laptop {
    # Check if the local machine has a laptop chassis type
    $chassisTypes = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
    # Laptop chassis types (portable/laptop and notebook) typically have values 9, 10, or 14
    $isLaptopResult = (9 -in $chassisTypes -or 10 -in $chassisTypes -or 14 -in $chassisTypes)
    $isLaptopResult
}

# Create Text File for Logging and File Detection
$FilePath = "$($env:windir)\Temp\PowerOptionsLaptops_Detection_v1.txt"

##*===============================================
##* DETECTION
##*===============================================

$isLaptop = Test-Laptop

# Check if the device is not a laptop
if (-not $isLaptop) {
    Write-Output "Device is not a laptop, Exiting."
    Exit 0
}
# Check if power options have been applied (and the device is a laptop)
elseif (Test-Path $FilePath) {
    Write-Output "Power Options have been applied, Exiting."
    Exit 0
}
# If the device is a laptop and power options have not been applied, run remediation
else {
    Write-Output "Power Options have not been applied, Running Remediation..."
    Exit 1
}