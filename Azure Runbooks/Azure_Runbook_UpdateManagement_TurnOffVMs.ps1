<# 
.SYNOPSIS
 Stops Azure virtual machines as part of an Update Management deployment.
 Handles AVD session hosts and performs additional tasks for them.
.DESCRIPTION
 This PowerShell script is designed to be run as part of an Azure Update Management Pre/Post script.
 The script will retrieve all Azure Virtual Machines that were started by the pre-script and stop & deallocate them.
 The script can handle Azure Virtual Desktop (AVD) session hosts, and performs additional tasks for them such as disabling drain mode
 and removing exclusion tags for AVD scaling plans.
.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.
.NOTES
	Editor:         Timothy Ransom
    Version:        5.0.0
    Version Date:   18-JAN-2023

    5.0.0 - (18-JAN-2023) - 
        - Updated Get-AutomationVariable with Get-AzAutomationVariable
        - Added Additional AzAutomationVariables for Tagged VMs and Drained VMs
        - Added Section to Disable Drained Mode on Drained VMs
        - Added Section to Remove AVD Scaling Plan Exclusion Tag on Tagged VMs
        - Added Job Name to Start-ThreadJob for VM Stop
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
$runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

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

$stoppableStates = "starting", "running"
$jobIDs = New-Object System.Collections.Generic.List[System.Object]

#Retrieve the automation variable, which we named using the runID from our run context. 
#See: https://docs.microsoft.com/en-us/azure/automation/automation-variables#activities

$startedmachinesCommaSeperated = (Get-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -Name "$runId").Value
$taggedmachinesCommaSeperated = (Get-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -Name "$runId-UpdateManagementTaggedVMs").Value
$drainedmachinesCommaSeperated = (Get-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -Name "$runId-UpdateManagementDrainedVMs").Value

#This script can run across subscriptions, so we need unique identifiers for each VMs
#Azure VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
if ($startedmachinesCommaSeperated) {
    $vmIds = $startedmachinesCommaSeperated -split ","
    $vmIds | ForEach-Object {
        $vmId = $_
    
        $split = $vmId -split "/";
        $subscriptionId = $split[2]; 
        $rg = $split[4];
        $name = $split[8];
        Write-Output ("Subscription Id: " + $subscriptionId)
        $mute = Select-AzSubscription -Subscription $subscriptionId

        $vm = Get-AzVM -ResourceGroupName $rg -Name $name -Status -DefaultProfile $mute

        $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
        if ($state -in $stoppableStates) {
            Write-Output "Stopping '$($name)' ..."
            $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname, $sub) $context = Select-AzSubscription -Subscription $sub; Stop-AzVM -ResourceGroupName $resource -Name $vmname -Force -DefaultProfile $context } -Name "StopVM-$name" -ArgumentList $rg, $name, $subscriptionId
            $jobIDs.Add($newJob.Id)
        }
        else {
            Write-Output ($name + ": already stopped. State: " + $state) 
        }
    }
}
else {
    Write-Output "No VMs were started by the Pre-Script..."
}

#Wait for all machines to finish stopping so we can include the results as part of the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList) {
    Write-Output "Waiting for machines to finish stopping..."
    Wait-Job -Id $jobsList
}

foreach ($id in $jobsList) {
    $job = Get-Job -Id $id
    if ($job.Error) {
        Write-Output $job.Error
    }
}

# Loop through each Session Host that was drained and turn drain mode off
# Drained Session Hosts are expressed by:
# subscriptions/$subscriptionID/resourcegroups/$resourceGroup/providers/Microsoft.DesktopVirtualization/hostpools/$hostpool/sessionhosts/$sessionhost
if ($drainedmachinesCommaSeperated) {
    $DrainedSessionHostIds = $drainedmachinesCommaSeperated -Split ","
    foreach ($DrainedSessionHostId in $DrainedSessionHostIds) {
        Update-AzWvdSessionHost `
            -HostPoolName $DrainedSessionHostId.Split("/")[8] `
            -ResourceGroupName $DrainedSessionHostId.Split("/")[4] `
            -Name $DrainedSessionHostId.Split("/")[10] `
            -AllowNewSession:$true | Out-Null
    }
}
else {
    Write-Output "No VMs had drained mode enabled by the Pre-Script..."
}

# loop through each tagged VM ID and remove the tag that was added
# Tagged VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name/$Tag.Key
if ($taggedmachinesCommaSeperated) { 
    $TaggedVMIds = $taggedmachinesCommaSeperated -split ","
    foreach ($TaggedVMId in $TaggedVMIds) {
        $TagToRemove = $TaggedVMId.Split("/")[9]
        $TaggedVM = $TaggedVMId.Split("/")[1..8] -join "/"
        Update-AzTag -ResourceId $TaggedVM -Tag @{$TagToRemove = "" } -Operation "Delete" | Out-Null
    }
}
else {
    Write-Output "No VMs were tagged by the Pre-Script..."
}


#Clean up our variables:
Remove-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -name "$runID"
Remove-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -name "$runId-UpdateManagementTaggedVMs"
Remove-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -name "$runId-UpdateManagementDrainedVMs"