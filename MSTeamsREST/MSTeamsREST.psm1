<#
.SYNOPSIS
    Functions for interacting with MS Teams via the MSGraph API
.DESCRIPTION

.LINK
    https://github.com/WebedMJ/PSAzureREST
.NOTES
    Requires AzureRESTAuth module.
    Only supports SharedKey authorization using an Azure AD app registration

    USES BETA API!
#>

function Get-O365Group {
    [CmdletBinding()]
    [OutputType("System.Object[]")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "GroupId")]
        [ValidateCount(1, 1)]
        [string[]]$GroupId,
        [Parameter(Mandatory = $true, ParameterSetName = "All")]
        [switch]$All,
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        [Parameter(Mandatory = $true)]
        [string]$AADTenantDomain,
        [Parameter(Mandatory = $false, ParameterSetName = "All")]
        [switch]$TeamsOnly
    )

    begin {
        $MSGraphVersion = 'beta'
        $uripath = '{0}/groups' -f $MSGraphVersion
        $Groups = @()
        switch ([bool]$GroupId) {
            $true {
                Write-Verbose "Getting GroupId: $GroupId"
                $uripath = '{0}/groups/{1}' -f $MSGraphVersion, $GroupId[0]
            }
            Default {
                Write-Verbose 'No GroupId, getting all groups...'
                $uripath = '{0}/groups' -f $MSGraphVersion
            }
        }
        $tokensplat = @{
            AzureIdentity   = 'SharedKey'
            SharedKeyScope  = 'MSGraph'
            ClientId        = $ClientId
            ClientSecret    = $ClientSecret
            AADTenantDomain = $AADTenantDomain
        }
    }

    process {
        try {
            $builturi = [System.UriBuilder]::new('https', 'graph.microsoft.com', '443', $uripath)
            [uri]$uri = $builturi.Uri
            do {
                $getgroups = @{
                    Headers     = Get-AzureRESTtoken @tokensplat
                    Uri         = $uri
                    Method      = 'Get'
                    ErrorAction = 'Stop'
                }
                $getgroupsresponse = Invoke-RestMethod @getgroups
                $nextpage = $getgroupsresponse.'@odata.nextLink'
                [uri]$uri = $nextpage
                switch ([bool]$GroupId) {
                    $true { $Groups += $getgroupsresponse }
                    Default { $Groups += $getgroupsresponse.value }
                }
            } while (![string]::IsNullOrEmpty($nextpage))
        } catch {
            $funcerror = $Error[0].Exception
        }
    }

    end {
        if (!$funcerror) {
            if ($TeamsOnly) {
                Write-Verbose 'Returning Teams only...'
                $result = $Groups | Where-Object {
                    $PSItem.resourceProvisioningOptions -imatch 'Team'
                }
            } else {
                Write-Verbose 'Returning all group types...'
                $result = $Groups
            }
            return $result
        } else {
            throw $funcerror
        }
    }
}

function Get-MSTeamApps {
    [CmdletBinding()]
    [OutputType("System.Object[]")]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateCount(1, 1)]
        [string[]]$TeamId,
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        [Parameter(Mandatory = $true)]
        [string]$AADTenantDomain
    )

    begin {
        function Format-APIQuery {
            param (
                [Parameter(Mandatory = $true)]
                [ValidateCount(1, 1)]
                [string[]]$Id,
                [Parameter(Mandatory = $false)]
                [switch]$installedApps,
                [Parameter(Mandatory = $false)]
                [string]$APIVersion = $MSGraphVersion
            )
            switch ($installedApps) {
                $true {
                    $uripath = '{0}/teams/{1}/installedApps' -f $APIVersion, $Id[0]
                    $uriquery = '?$expand=teamsAppDefinition'
                    $builturi = [System.UriBuilder]::new('https', 'graph.microsoft.com', '443', $uripath, $uriquery)
                    [uri]$uri = $builturi.Uri
                }
                Default {
                    $uripath = '{0}/teams/{1}' -f $APIVersion, $Id[0]
                    $builturi = [System.UriBuilder]::new('https', 'graph.microsoft.com', '443', $uripath)
                    [uri]$uri = $builturi.Uri
                }
            }
            return $uri
        }
        $MSGraphVersion = 'beta'
        $tokensplat = @{
            AzureIdentity   = 'SharedKey'
            SharedKeyScope  = 'MSGraph'
            ClientId        = $ClientId
            ClientSecret    = $ClientSecret
            AADTenantDomain = $AADTenantDomain
        }
    }

    process {
        try {
            $getteam = @{
                Headers     = Get-AzureRESTtoken @tokensplat
                Uri         = Format-APIQuery -Id $TeamId[0]
                Method      = 'Get'
                ErrorAction = 'Stop'
            }
            $getteamresponse = Invoke-RestMethod @getteam
            $getapps = @{
                Headers     = Get-AzureRESTtoken @tokensplat
                Uri         = Format-APIQuery -Id $TeamId[0] -installedApps
                Method      = 'Get'
                ErrorAction = 'Stop'
            }
            $getappsresponse = Invoke-RestMethod @getapps
            $AppList = foreach ($app in $getappsresponse.value) {
                $AppDetails = [PSCustomObject]@{
                    AppId      = $app.teamsAppDefinition.teamsAppId
                    AppName    = $app.teamsAppDefinition.displayName
                    AppVersion = $app.teamsAppDefinition.version
                }
                $AppDetails
            }
        } catch {
            $funcerror = $Error[0].Exception
        }
    }

    end {
        if (!$funcerror) {
            $TeamApps = [PSCustomObject]@{
                TeamId          = $TeamId[0]
                TeamDisplayName = $getteamresponse.displayName
                TeamApps        = $AppList
            }
            return $TeamApps
        } else {
            throw $funcerror
        }
    }
}
