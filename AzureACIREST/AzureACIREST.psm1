<#
.SYNOPSIS
    Module for interacting with ACI using the ARM REST API.
    Designed to be invoked from an Azure web/function app or Azure Automation.
.DESCRIPTION

.LINK
    https://github.com/WebedMJ/General/tree/master/PowerShell/Azure/Modules/AzureACIREST
.NOTES
    Requires managed identity enabled on the app service or an automationrunas account.
#>
function Get-ACIContainerGroups {
    <#
    .SYNOPSIS
        Gets the list of ACI container groups in a subscription and/or resource group.
        See https://docs.microsoft.com/en-us/rest/api/container-instances/containergroups
    .LINK
        https://github.com/WebedMJ/General/tree/master/PowerShell/Azure/Modules/AzureACIREST
    #>
    [CMDLetBinding()]
    [OutputType("System.Collections.Hashtable")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName,
        # Get all jobs, default is just the first page from the API.
        [Parameter(Mandatory = $false)]
        [Switch]$All,
        [Parameter(Mandatory = $false)]
        [Switch]$AzureAutomationRunbook
    )
    $apiVersion = '2018-10-01'
    [PSCustomObject]$response = @()
    [System.String]$jobsnextlink = ''
    switch ($ResourceGroupName) {
        { [bool]$PSItem -eq $true } {
            $uripath = 'subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ContainerInstance/containerGroups' -f
            $SubscriptionId, $ResourceGroupName
        }
        Default {
            $uripath = 'subscriptions/{0}/providers/Microsoft.ContainerInstance/containerGroups' -f
            $SubscriptionId
        }
    }
    $uriquery = '?&api-version={0}' -f $apiVersion
    $builturi = [System.UriBuilder]::new('https', 'management.azure.com', '443', $uripath, $uriquery)
    [uri]$uri = $builturi.Uri
    do {
        switch ($AzureAutomationRunbook) {
            { [bool]$PSItem -eq $true } {
                $getjobssplat = @{
                    Headers     = Get-AzureRESTtoken -AzureResource 'ARM' -AzureIdentity 'AzureAutomationRunAs'
                    Uri         = $uri
                    Method      = 'Get'
                    ErrorAction = 'Stop'
                }
            }
            Default {
                $getjobssplat = @{
                    Headers     = Get-AzureRESTtoken -AzureResource 'ARM'
                    Uri         = $uri
                    Method      = 'Get'
                    ErrorAction = 'Stop'
                }
            }
        }
        try {
            $response += Invoke-RestMethod @getjobssplat
            if ($All) {
                $jobsnextlink = $response.nextLink
                [uri]$uri = $jobsnextlink
            }
        } catch {
            $funcerror = $Error[0].Exception
        }
    } while (![string]::IsNullOrEmpty($jobsnextlink))
    if (!$funcerror) {
        return $response
    } else {
        throw $funcerror
    }
}

function New-ACIContainerGroup {
    <#
    .SYNOPSIS
        Gets the list of ACI container groups in a subscription and/or resource group.
        See https://docs.microsoft.com/en-us/rest/api/container-instances/containergroups
    .LINK
        https://github.com/WebedMJ/General/tree/master/PowerShell/Azure/Modules/AzureACIREST
    #>
    [CMDLetBinding()]
    [OutputType("System.Collections.Hashtable")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "ContainerParams")]
        [string]$Name,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [string]$Command,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [string]$EnvironmentVariables,
        [Parameter(Mandatory = $true, ParameterSetName = "ContainerParams")]
        [string]$Image,
        [Parameter(Mandatory = $true, ParameterSetName = "ContainerParams")]
        [int16]$CPU,
        [Parameter(Mandatory = $true, ParameterSetName = "ContainerParams")]
        [string]$MemoryGB,
        [Parameter(Mandatory = $true, ParameterSetName = "ContainerParams")]
        [string]$Location,
        [Parameter(Mandatory = $true, ParameterSetName = "ContainerHash")]
        [hashtable]$Container,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Linux', 'Windows')]
        [Switch]$OSType,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [uri]$RegistryURI,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [string]$RegistryUser,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [securestring]$RegistryPassword,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false)]
        [Switch]$AzureAutomationRunbook
    )
    $apiVersion = '2018-10-01'
    [PSCustomObject]$response = @()
    $uripath = 'subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ContainerInstance/containerGroups/{2}' -f
    $SubscriptionId, $ResourceGroupName, $Name
    $uriquery = '?&api-version={0}' -f $apiVersion
    $builturi = [System.UriBuilder]::new('https', 'management.azure.com', '443', $uripath, $uriquery)
    [uri]$uri = $builturi.Uri
    $RegistryPasswordTXT = (New-Object PSCredential 'user', $RegistryPassword).GetNetworkCredential().Password
    if (!$Container) {
        $Container = @{
            name       = $Name
            properties = @{
                command              = $Command
                environmentVariables = $EnvironmentVariables
                image                = $Image
                resources            = @{
                    requests = @{
                        cpu        = $CPU
                        memoryInGB = $MemoryGB
                    }
                }
            }
        }
    }
    $body = @{
        name       = $Name
        location   = $Location
        properties = @{
            containers               = $Container
            imageRegistryCredentials = @{
                server   = $RegistryURI
                username = $RegistryUser
                password = $RegistryPasswordTXT
            }
            osType                   = $OSType
        }
    }
    switch ($AzureAutomationRunbook) {
        { [bool]$PSItem -eq $true } {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM' -AzureIdentity 'AzureAutomationRunAs'
                Body        = $body
                Uri         = $uri
                Method      = 'PUT'
                ErrorAction = 'Stop'
            }
        }
        Default {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM'
                Body        = $body
                Uri         = $uri
                Method      = 'PUT'
                ErrorAction = 'Stop'
            }
        }
    }
    try {
        $response = Invoke-RestMethod @getjobssplat
    } catch {
        $funcerror = $Error[0].Exception
    }
    if (!$funcerror) {
        return $response
    } else {
        throw $funcerror
    }
}