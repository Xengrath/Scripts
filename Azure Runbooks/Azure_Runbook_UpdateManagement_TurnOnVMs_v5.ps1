<# 
.SYNOPSIS 
 Starts Azure virtual machines as part of an Update Management deployment, and ensures they are turned off after receiving updates.
 Handles AVD session hosts and performs additional tasks for them.
.DESCRIPTION
  This PowerShell script is designed to be run as part of an Azure Update Management Pre/Post script.
  The script ensures that all Azure virtual machines (VMs) in the Update Deployment receive updates by turning them on if they are not already running.
  The script will also store the names of the VMs that were started in an Azure Automation variable so that only those VMs are turned back off when the
  deployment is finished. 
  The script can handle Azure Virtual Desktop (AVD) session hosts, and performs additional tasks for them such as setting drain mode,
  removing active sessions, and adding exclusion tags for AVD scaling plans.
.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.
.NOTES
	Editor:         Timothy Ransom
    Version:        5.0.0
    Version Date:   18-JAN-2023

    5.0.0 - (18-JAN-2023)
        - Added Section to Check if VM Resource is AVD Session Host
        - Added Section to Add AVD Scaling Plan Exclusion Tag if VM is AVD Session Host and has Scaling Plan Set
        - Added Section to Set Drain Mode to Enabled if VM is AVD Session Host
        - Added Section to Start-ThreadJob to Remove any Active Sessions if VM is AVD Session Host
        - Updated Get/Set/Remove-AutomationVariable with Get/Set/Remove-AzAutomationVariable
        - Added Additional AzAutomationVariables for Tagged VMs and Drained VMs
#>

#requires -Modules ThreadJob

param(
    [string]$SoftwareUpdateConfigurationRunContext
)
#region BoilerplateAuthentication
# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect using a Managed Service Identity
try {
    $AzureContext = (Connect-AzAccount -Identity).context
}
catch {
    Write-Output "There is no system-assigned user identity. Aborting."; 
    exit
}

# set and store context
$AzureContext = Set-AzContext -SubscriptionId $AzureContext.Subscription.Id -DefaultProfile $AzureContext
#endregion BoilerplateAuthentication


#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext
$vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
$runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

if (!$vmIds) {
    #Workaround: Had to change JSON formatting
    $Settings = ConvertFrom-Json $context.SoftwareUpdateConfigurationSettings
    #Write-Output "List of settings: $Settings"
    $VmIds = $Settings.AzureVirtualMachines
    #Write-Output "Azure VMs: $VmIds"
    if (!$vmIds) {
        Write-Output "No Azure VMs found"
        return
    }
}

#https://github.com/azureautomation/runbooks/blob/master/Utility/ARM/Find-WhoAmI
# In order to prevent asking for an Automation Account name and the resource group of that AA,
# search through all the automation accounts in the subscription 
# to find the one with a job which matches our job ID
$AutomationResource = Get-AzResource -ResourceType Microsoft.Automation/AutomationAccounts

foreach ($Automation in $AutomationResource) {
    $Job = Get-AzAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($Job))) {
        $ResourceGroup = $Job.ResourceGroupName
        $AutomationAccount = $Job.AutomationAccountName
        break;
    }
}

#This is used to store the state of VMs
New-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name "$runId" -Value "" -Encrypted $false
New-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name "$runId-UpdateManagementTaggedVMs" -Value "" -Encrypted $false
New-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name "$runId-UpdateManagementDrainedVMs" -Value "" -Encrypted $false

$updatedMachines = @()
$taggedmachines = @()
$drainedmachines = @()
$startableStates = "stopped" , "stopping", "deallocated", "deallocating"
$jobIDs = New-Object System.Collections.Generic.List[System.Object]


# Some Variables to be used in the below section

# Get a list of all AVD host pools in the subscription
$AVDHostPools = Get-AzResource -ResourceType "Microsoft.DesktopVirtualization/hostpools"
# Get a list of all AVD Scaling Plans in the subscription
$AVDScalingPlans = Get-AzWvdScalingPlan | Select-Object -Property Name, Id, @{Name = 'HostPoolID'; Expression = { $_.HostPoolReference.HostPoolArmPath } }, @{Name = 'AutoscaleEnabled'; Expression = { $_.HostPoolReference.ScalingPlanEnabled } }, @{Name = 'ExclusionTag'; Expression = { $_.ExclusionTag } }
# Message Title & Body for AVD User Sessions
$MessageTitle = "Azure Virtual Desktop - Scheduled Maintenance"
$MessageBody = "Dear User `n `n" + `
    "The server you are currently connected to is going into scheduled, unattended, automated maintenance.`n `n" + `
    "Please save your work immediately, you will be disconnected shortly."

#Parse the list of VMs and start those which are stopped
#Azure VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId = $_
    
    $split = $vmId -split "/";
    $subscriptionId = $split[2]; 
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    $mute = Select-AzSubscription -Subscription $subscriptionId

    $vm = Get-AzVM -ResourceGroupName $rg -Name $name -Status -DefaultProfile $mute
    $VMResource = Get-AzVM -ResourceGroupName $rg -Name $name
    Write-Output "Processing virtual machine '$($vm.Name)'..."
    # Iterate through the host pools to check if the virtual machine is a member of any of them
    foreach ($AVDHostPool in $AVDHostPools) {
        # Get a list of session hosts members in the host pool
        $AVDSessionHosts = Get-AzWvdSessionHost -HostPoolName $AVDHostPool.Name -ResourceGroupName $AVDHostPool.ResourceGroupName

        # Check if the virtual machine is a member of a host pool
        foreach ($AVDSessionHost in $AVDSessionHosts) {
            if ($AVDSessionHost.ResourceId -eq $vmId) {
                # Virtual machine is a member of the host pool
                Write-Output "The virtual machine is a member of AVD host pool '$($AVDHostPool.Name)'"

                # Loop through each scaling plan to see if it assigned to the host pool
                foreach ($AVDScalingPlan in $AVDScalingPlans) {
                    # Assign the Assigned Host Pools to a Variable
                    $AssignedHostPools = $AVDScalingPlan.HostPoolID
                    # If there is assigned host pools (not null)
                    if ($AssignedHostPools) {
                        # Host Pool has a scaling plan assigned to it
                    
                        # Loop through each assigned host pool incase the scaling plan is assigned to multiple host pools
                        foreach ($AssignedHostPool in $AssignedHostPools) {
                            if ($AssignedHostPool.Split("/")[8] -like $AVDHostPool.ResourceId.Split("/")[8]) {
                                # Scaling Plan has been identified
                                Write-Output "The AVD Host pool '$($AVDHostPool.Name)' is assigned to scaling plan '$($AVDScalingPlan.Name)'"

                                # Check if the VM is tagged with the scaling plan exclusion tag
                                if (($VMResource.Tags.Keys) -Contains $AVDScalingPlan.ExclusionTag) {
                                    Write-Output "The virtual machine is already tagged with the scaling plan exclusion tag"
                                }
                                else {
                                    # Add the scaling plan exclusion tag to the virtual machine
                                    Update-AzTag -ResourceId $vmId -Tag @{$AVDScalingPlan.ExclusionTag = "" } -Operation "Merge" | Out-Null
                                    Write-Output "The scaling plan exclusion tag '$($AVDScalingPlan.ExclusionTag)' has been added to the virtual machine"
                                    # Add the drained session host to an automation account variable to disable drain mode later
                                    $taggedmachines += $vmId + '/' + "$($AVDScalingPlan.ExclusionTag)"
                                }
                            }
                        }
                    }
                }
            
                # check if the session host has drain mode enabled
                if ($AVDSessionHost.AllowNewSession -eq "True") {
                    Write-Output "The Session Host has drain mode disabled, turning drain mode on..."

                    # Enable Drain Mode on the Session Host
                    Update-AzWvdSessionHost `
                        -HostPoolName $AVDHostPool.Name `
                        -ResourceGroupName $AVDHostPool.ResourceGroupName `
                        -Name $AVDSessionHost.Name.Split("/")[1] `
                        -AllowNewSession:$false | Out-Null

                    # Add the drained session host to an automation account variable to disable drain mode later
                    $drainedmachines += $AVDSessionHost.Id
                }
                else {
                    Write-Output "The Session Host already has drain mode enabled"
                }

                # Check if there are any connected sessions
                if ($AVDSessionHost.Session -gt 0) {
                    Write-Output "The Session Host has conncted sessions"

                    # Get a list of all connected sessions on the session host
                    $ConnectedSessions = Get-AzWvdUserSession `
                        -HostPoolName $AVDHostPool.Name `
                        -ResourceGroupName $AVDHostPool.Id.Split("/")[4] `
                        -SessionHostName $AVDSessionHost.Name.Split("/")[1]

                    # loop through each session and take the appropriate action
                    foreach ($ConnectedSession in $ConnectedSessions) {
                        $SessionID = $ConnectedSession.name.Split("/")[2]

                        # Check if the Session is Active
                        if ($ConnectedSession.SessionState -eq "Active") {
                            # Session is Active, sending user a message

                            Send-AzWvdUserSessionMessage `
                                -HostPoolName $AVDHostPool.Name `
                                -ResourceGroupName $AVDHostPool.Id.Split("/")[4] `
                                -SessionHostName $AVDSessionHost.Name.Split("/")[1] `
                                -UserSessionId $SessionId `
                                -MessageTitle $MessageTitle `
                                -MessageBody $MessageBody

                            # Creating ThreadJob to Remove Sessions after specified interval
                            # I have not specified a ThrottleLimit as its not expected for more than 5 users to be online when Update Management Runs
                            $newJob = Start-ThreadJob -ScriptBlock {
                                param($ConnectedSession, $SessionId)
                                Start-Sleep -Seconds 90
                                Remove-AzWvdUserSession `
                                    -ResourceGroupName $ConnectedSession.Id.Split("/")[4] `
                                    -HostPoolName $ConnectedSession.Id.Split("/")[8] `
                                    -SessionHostName $ConnectedSession.Id.Split("/")[10] `
                                    -Id $SessionId `
                                    -Force
                            } -Name "DisconnectSession-$SessionId" -ArgumentList $ConnectedSession, $SessionId
                            $jobIDs.Add($newJob.Id)

                        }
                        else {
                            Remove-AzWvdUserSession `
                                -ResourceGroupName $ConnectedSession.Id.Split("/")[4] `
                                -HostPoolName $ConnectedSession.Id.Split("/")[8] `
                                -SessionHostName $ConnectedSession.Id.Split("/")[10] `
                                -Id $SessionId `
                                -Force
                        }
                    }
                }
                #}
                #break
            }
        }
    }

    #Query the state of the VM to see if it's already running or if it's already started
    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
    if ($state -in $startableStates) {
        Write-Output "Starting '$($name)' ..."
        #Store the VM we started so we remember to shut it down later
        $updatedMachines += $vmId
        $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname, $sub) $context = Select-AzSubscription -Subscription $sub; Start-AzVM -ResourceGroupName $resource -Name $vmname -DefaultProfile $context } -Name "StartVM-$name" -ArgumentList $rg, $name, $subscriptionId
        $jobIDs.Add($newJob.Id)
    }
    else {
        Write-Output ($name + ": no action taken. State: " + $state) 
    }

}

$updatedMachinesCommaSeperated = $updatedMachines -join ","
$taggedmachinesCommaSeperated = $taggedmachines -Join ","
$drainedmachinesCommaSeperated = $drainedmachines -Join ","
#Wait until all machines have finished starting before proceeding to the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList) {
    Write-Output "Waiting for all thread jobs to complete..."
    Wait-Job -Id $jobsList
}

foreach ($id in $jobsList) {
    $job = Get-Job -Id $id
    if ($job.Error) {
        Write-Output $job.Error
    }

}

Write-output $updatedMachinesCommaSeperated
#Store output in the automation variable
Set-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name "$runId" -Value $updatedMachinesCommaSeperated -Encrypted $false
Set-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name "$runId-UpdateManagementTaggedVMs" -Value $taggedmachinesCommaSeperated -Encrypted $false
Set-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name "$runId-UpdateManagementDrainedVMs" -Value $drainedmachinesCommaSeperated -Encrypted $false
