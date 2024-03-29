<# 
.SYNOPSIS 
    Finds all devices in Azure Active Directory that have not signed-in in the specified period of time.
.DESCRIPTION
    Finds all devices in Azure Active Directory that have not signed-in in the specified period of time.
    It is intended to be run with Azure Automation
.NOTES
    Editor:         Timothy Ransom
    Version:        1.0.0
    Version Date:   23-APR-2023
    
    1.0.0 - (23-APR-2023) - Script Created
    1.1.0 - (23-APR-2023) - Update Comments and Write-Output

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

# Get UTC formatted time for the specified period of time
$DaysSinceLastSignIn = 90
$Date = (Get-Date (Get-Date).AddDays($DaysSinceLastSignIn) -Format u).Replace(' ','T')

# Retrieve all devices that have not signed-in in the specified period of time
$devices = Get-MgDevice -All -Filter "ApproximateLastSignInDateTime lt $date" -CountVariable CountVar -ConsistencyLevel eventual

# Output the count of devices returned by the previous command
Write-Output "Found ($CountVar) devices that have not signed-in in $($DaysSinceLastSignIn) days."

# Disable devices in parallel using the ThreadJob module
if ($CountVar -eq 0) {
    Write-Output "No devices identified"
}
else {
    $jobs = @()
    foreach ($device in $devices) {
        $job = Start-ThreadJob -ScriptBlock { 
            param($deviceId, $deviceName)
            try {
                Disable-MgUserManagedDevice -Id $deviceId
                Write-Output "Disabling Device $deviceName ($deviceId)"
            }
            catch {
                Write-Error "Error disabling device $deviceName ($deviceId): $_"
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
        Write-Output "Failed to disable the following devices: $($FailedDevices.Name -join ', ')"
        Write-Output "Device IDs: $($FailedDevices.Id -join ', ')"
    }
    # If the number of failed devices is less than 0, close off the script
    else {
        Write-Output "Successfully disabled all ($CountVar) devices. "
    }
}
