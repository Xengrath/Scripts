<#
.SYNOPSIS
    This script is used to set Power Options against all Power Plans on the computer
.DESCRIPTION
    This script is used to set Power Options against all Power Plans on the computer
    It retrieves a list of all power plans and loops through them to set the options accordingly.
    It is intended to be run as the remediation script of a Remediation from Microsoft Intune
.NOTES
    Author:         Timothy Ransom
    Version:        1.0.0
    Version Date:   22-NOV-2023

    1.0.0 - (22-NOV-2023) - Script Created

    #>

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

$FilePath = "$($env:windir)\Temp\PowerOptionsLaptops_Detection_v1.txt"

Start-Transcript -Path $FilePath -NoClobber

## Retrieve all of the available Power Schemes:

    # Run powercfg and store the output
    $powercfgOutput = powercfg.exe /list

    # Split the output into individual lines
    $powercfgLines = $powercfgOutput -split "`r`n"

    # Initialize an empty array to store the power schemes
    $powerSchemes = @()

    # Loop through the lines to find power scheme information
    foreach ($line in $powercfgLines) {
        if ($line -match "([0-9a-fA-F-]+)\s*\(([^)]+)\)") {
            $powerScheme = [PSCustomObject] @{
                Guid = $Matches[1].Trim()
                Name = $Matches[2].Trim()
            }
            $powerSchemes += $powerScheme
        }
    }

# Display the list of power schemes
$powerSchemes

##*===============================================
##* REMEDIATION
##*===============================================

try {
    # Print the power scheme guide
    foreach ($scheme in $powerSchemes) {
        Write-Output "Updating Power Scheme: $($scheme.Name) [$($scheme.Guid)]"
        
        ## Turn off Display After:
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/display-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/display-settings-display-idle-timeout
            powercfg.exe -setacvalueindex $($scheme.Guid) 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 1200
            powercfg.exe -setdcvalueindex $($scheme.Guid) 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 1200

        ## Hard Disk Timeout
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/disk-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/disk-settings-disk-idle-timeout
            powercfg.exe -setacvalueindex $($scheme.Guid) 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0
            powercfg.exe -setdcvalueindex $($scheme.Guid) 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0

        ## Sleep After:
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/sleep-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/sleep-settings-sleep-idle-timeout
            powercfg.exe -setacvalueindex $($scheme.Guid) 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 5400
            powercfg.exe -setdcvalueindex $($scheme.Guid) 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 1800

        ## Hibernate After:
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/sleep-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/sleep-settings-hibernate-idle-timeout
            powercfg.exe -setacvalueindex $($scheme.Guid) 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0
            powercfg.exe -setdcvalueindex $($scheme.Guid) 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0

        ## Power Button Action:
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-power-button-action
            powercfg.exe -setacvalueindex $($scheme.Guid) 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 3
            powercfg.exe -setdcvalueindex $($scheme.Guid) 4f971e89-eebd-4455-a8de-9e59040e7347 7648efa3-dd9c-4e3e-b566-50f929386280 3

        ## Sleep Button Action:
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-sleep-button-action
            powercfg.exe -setacvalueindex $($scheme.Guid) 4f971e89-eebd-4455-a8de-9e59040e7347 96996bc0-ad50-47ec-923b-6f41874dd9eb 0
            powercfg.exe -setdcvalueindex $($scheme.Guid) 4f971e89-eebd-4455-a8de-9e59040e7347 96996bc0-ad50-47ec-923b-6f41874dd9eb 0

        ## Close Lid Action:
            # {Power Subgroup GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings
            # {Power Setting GUID} = https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action
            powercfg.exe -setacvalueindex $($scheme.Guid) 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
            powercfg.exe -setdcvalueindex $($scheme.Guid) 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 1
    }
}
catch {
    Write-Error "An error occurred while updating power settings: $_"
}
finally {
    Write-Output "Power settings update completed on $(Get-Date -Format "dddd dd-MMM-yyyy HH:mm K")"
}

Stop-Transcript
