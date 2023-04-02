<#
.SYNOPSIS
	This script is used to exported a detailed list of all tags names and values used in an Azure Tenant
.DESCRIPTION
	This script is used to exported a detailed list of all tags names and values used in an Azure Tenant
    It retrieves a unique list of tag names and tags values by Subscription and exports it to csv
.NOTES
	Author:         Timothy Ransom
    Version:        1.0.0.0
    Version Date:   02-APR-2023

    1.0.0 - (02-APR-2023) - Script Created
#>

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

# Set output file path and header
$outputFilePath = "$Env:UserProfile\Downloads\AzureTags-Detailed.csv"
$outputHeader = "Tag Name,Tag Value,Subscription"
$outputHeader | Out-File -FilePath $outputFilePath -Encoding UTF8

##*===============================================
##* EXECUTION
##*===============================================

# Connect to Azure account
Connect-AzAccount

# Get all subscriptions in the Azure account
$subscriptions = Get-AzSubscription

# Loop through each subscription and process its resources
foreach ($subscription in $subscriptions) {
    # Set the current subscription context
    Write-Host "Processing subscription: $($subscription.Name) $($subscription.id)"
    Set-AzContext -Subscription $subscription.Id | Out-Null

    # Get all resources in the current subscription
    $resources = Get-AzResource

    # Hashtable to track which tags have been outputted for the current subscription
    $outputtedTags = @{}

    # Loop through each resource in the current subscription
    foreach ($resource in $resources) {
        # Check if the resource has any tags
        if ($resource.Tags) {
            # Loop through each tag in the resource tags
            foreach ($tag in $resource.Tags.GetEnumerator()) {
                $tagName = $tag.Key
                # Skip null tag names
                if (!$tagName) { continue }
                $tagValue = $tag.Value

                # Check if the tag name and value have already been outputted for the current subscription
                if (!$outputtedTags.ContainsKey($tagName) -or !$outputtedTags[$tagName].Contains($tagValue)) {
                    # Add the tag to the outputted tags hashtable
                    $outputtedTags[$tagName] += $tagValue
                    # Build the output line for the current tag and subscription
                    $subscriptionName = $subscription.Name
                    $subscriptionId = $subscription.Id
                    $outputLine = "$tagName,"
                    if ($tagValue -match ",") {
                        # If tag value contains a comma, enclose it in double quotes
                        $outputLine += "`"$($tagValue)`","
                    }
                    else {
                        $outputLine += "$tagValue,"
                    }
                    $outputLine += "$subscriptionName"
                    $outputLine += "$subscriptionId"

                    # Output the tag and subscription to the CSV file
                    $outputLine | Out-File -FilePath $outputFilePath -Encoding UTF8 -Append
                }

            }

        }

    }
    # Check if no resources were found with tags in the current subscription
    if (!(Get-Content $outputFilePath)) {
        Write-Host "No resources found with tags in subscription: $($subscription.Name)"
    }

}

# Output the file path where the tags have been exported
Write-Host "Tags used in all subscriptions have been exported to: $outputFilePath"
