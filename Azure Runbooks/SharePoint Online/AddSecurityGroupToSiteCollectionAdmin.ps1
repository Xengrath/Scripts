<#
.SYNOPSIS
    This script is used to add a Security Group as Site Collection Administrator to all SharePoint Online Sites.
.DESCRIPTION
    This script is used to add a Security Group as Site Collection Administrator to all SharePoint Online Sites.
    It loops through each site to ensure the Security Group is a Site Collection Administrator.
    The Admin Center URL and Security Group Object ID must be supplied as parameters to the script
.NOTES
    Author:         Timothy Ransom
    Version:        1.0.0
    Version Date:   05-APR-2023
    
    1.0.0 - (05-APR-2023) - Script Created
#>

#requires -Modules PnP.PowerShell
#requires -Modules ThreadJob

# Retrieve parameters from the Azure Automation Runbook
param(
    [Parameter(Mandatory = $true)]
    [string]$AdminURL,

    [Parameter(Mandatory = $true)]
    [string]$SecurityGroupObjectID
)

# Convert the Parameters into Variables to be used in the script
$GroupObjectID = $SecurityGroupObjectID.Trim().Replace("`"", "")
$SiteCollectionAdmin = "c:0t.c|tenant|$GroupObjectID"

# Check if the Admin URL is a valid URL
try {
    $URL = New-Object System.Uri $AdminURL.Trim().Replace("`"", "")
    Write-Output "$AdminURL is a Valid URL"
}
catch {
    Write-Output "$AdminURL URL is an Invalid URL"
    return
}

# Connect to SharePoint Online using App-only authentication
try {
    Connect-PnPOnline $URL -ManagedIdentity
}
catch {
    Write-Error "Failed to connect to SharePoint Online: $($_.Exception.Message)"
    return
}

# Retrieve all SharePoint Online sites
$SiteCollections = Get-PnPTenantSite

# Create an array to store the thread jobs
$jobs = @()

# Loop through each site and add the Security Group as Site Collection Administrator using a thread job
foreach ($Site in $SiteCollections) {
    $job = Start-ThreadJob -ScriptBlock {
        param($Site, $SiteCollectionAdmin)
        try {
            Add-PnPSiteCollectionAdmin -Owners $SiteCollectionAdmin
        }
        catch {
            # Output an error if adding the Site Collection Admin Failed
            Write-Error "Failed to add security group as site collection admin to $($site.Url): $($_.Exception.Message)"
            return $Site.Url
        }
    } -ArgumentList $Site, $SiteCollectionAdmin

    $jobs += $job

}

# Wait for all thread jobs to complete
Wait-Job $jobs | Out-Null

# Retrieve the URLs of the sites that failed to add the Security Group as Site Collection Administrator
$failedSites = $jobs | Receive-Job -ErrorAction SilentlyContinue | Where-Object { $_ -ne $null }

# Output a message indicating whether the Security Group was successfully added as Site Collection Administrator or not
if ($failedSites.Count -gt 0) {
    Write-Output "Failed to add security group as site collection admin to the following sites: $($failedSites -join ', ')"
}
else {
    Write-Output "Successfully added security group as site collection admin to all sites"
}

# Disconnect from PnPOnline
Disconnect-PnPOnline
