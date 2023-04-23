<# 
.SYNOPSIS 
    Finds all devices in Azure Active Directory that are disabled and have not been seen in specified period of time
.DESCRIPTION
    Finds all devices in Azure Active Directory that are disabled and have not been seen in specified period of time
    It is intended to be run with Azure Automation
.NOTES
    Editor:         Timothy Ransom
    Version:        1.0.0
    Version Date:   23-APR-2023
    
    1.0.0 - (23-APR-2023) - Script Created
    
    Requires a System Assigned Managed Identity with the Microsoft Graph Device.ReadWrite.All Permission
#>

#requires -Modules ThreadJob
#requires -Modules Microsoft.Graph.Users.Actions

# Connect to Microsoft Graph using System Assigned Managed Identity
try {
    Connect-MgGraph -Identity
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    return
}

# Retrieve all devices that are disabled and have not been seen in the specified period of time
$DaysDisabled = 30
$Date = (Get-Date (Get-Date).AddDays(-$DaysDisabled) -Format u).Replace(' ','T')
$devices = Get-MgDevice -All -Filter "deviceState eq 'disabled' and lastSeenDateTime lt $($Date)" -CountVariable CountVar -ConsistencyLevel eventual

# Output the count of devices returned by the previous command
Write-Output "Found ($CountVar) devices that are disabled and have not been seen for at least $($DaysDisabled) days."

# Delete devices in parallel using the ThreadJob module
if ($CountVar -eq 0) {
    Write-Output "No devices identified"
}
else {
    $jobs = @()
    foreach ($device in $devices) {
        $job = Start-ThreadJob -ScriptBlock { 
            param($deviceId, $deviceName)
            try {
                Remove-MgDevice -DeviceId $deviceId
                Write-Output "Deleting Device $deviceName ($deviceId)"
            }
            catch {
                Write-Error "Error deleting device $deviceName ($deviceId): $_"
                $failedDevice = [pscustomobject]@{
                    Name = $deviceName
                    Id = $deviceId
                }
                Write-Output $failedDevice
            }
        } -ArgumentList $device.Id, $device.Name
        $jobs += $job
    }

    # Retrieve all of the devices that failed to be disabled
    $FailedDevices = $jobs | Receive-Job -ErrorAction SilentlyContinue | Where-Object { $_ -ne $null }

    # If the number of failed devices is greater than 0, display them in a command seperated list
    if ($FailedDevices.Count -gt 0) {
        Write-Output "Failed to delete the following devices: $($FailedDevices.Name -join ', ')"
        Write-Output "Device IDs: $($FailedDevices.Id -join ', ')"
    }
    # If the number of failed devices is less than 0, close off the script
    else {
        Write-Output "Successfully deleted all ($CountVar) devices. "
    }
}
