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
        Write-Error $Error[0]
        throw $funcerror
    }
}

function New-ACIContainerGroup {
    <#
    .SYNOPSIS
        Creates or updates an ACI container group in a subscription and/or resource group.
        See https://docs.microsoft.com/en-us/rest/api/container-instances/containergroups
    .PARAMETER Image
        Image name plus tag to use for the container, e.g. 'nginx:latest'
    .PARAMETER RegistryServer
        FQDN of image registry server, without protocol (e.g. https).
        i.e. 'myreg.azurecr.io'
    .PARAMETER EnvironmentVariables
        Array of hastables defining environment variables that should be passed to the container on start up.
        All variables are passed as secure environment variables.

        Example structure:

        EnvironmentVariables   = @(
                @{
                    Name        = 'var1'
                    secureValue = 'var1value'
                }
                @{
                    Name        = 'var2'
                    secureValue = 'var2value'
                }
                @{
                    Name        = 'var3'
                    secureValue = 'var3value'
                }
            )
    .PARAMETER RestartPolicy
        Restert policy of the container group, default is 'Always'.
        Valid values are 'Always', 'OnFailure', 'Never'.
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
        [array]$EnvironmentVariables,
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
        [string]$OSType,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [string]$RegistryServer,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [string]$RegistryUser,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [securestring]$RegistryPassword,
        [Parameter(Mandatory = $false, ParameterSetName = "ContainerParams")]
        [ValidateSet('Always', 'OnFailure', 'Never')]
        [string]$RestartPolicy = 'Always',
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
                image                = "$RegistryServer/$Image"
                resources            = @{
                    requests = @{
                        cpu        = $CPU
                        memoryInGB = $MemoryGB
                    }
                }
            }
        }
    }
    $new = @{
        name       = $Name
        location   = $Location
        properties = @{
            containers               = @($Container)
            imageRegistryCredentials = @(
                @{
                    server   = $RegistryServer
                    username = $RegistryUser
                    password = $RegistryPasswordTXT
                }
            )
            osType                   = $OSType
            restartPolicy            = $RestartPolicy
        }
    }
    $body = $new | ConvertTo-Json -Depth 6
    $ContentType = 'application/json'
    switch ($AzureAutomationRunbook) {
        { [bool]$PSItem -eq $true } {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM' -AzureIdentity 'AzureAutomationRunAs'
                Body        = $body
                Uri         = $uri
                ContentType = $ContentType
                Method      = 'PUT'
                ErrorAction = 'Stop'
            }
        }
        Default {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM'
                Body        = $body
                Uri         = $uri
                ContentType = $ContentType
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
        Write-Verbose "Successfully created container group: $Name"
        return $response
    } else {
        Write-Error $Error[0]
        throw $funcerror
    }
}

function Start-ACIContainerGroup {
    <#
    .SYNOPSIS
        Starts an existing ACI container group in a subscription and/or resource group.
        See https://docs.microsoft.com/en-us/rest/api/container-instances/containergroups
    .LINK
        https://github.com/WebedMJ/General/tree/master/PowerShell/Azure/Modules/AzureACIREST
    #>
    [CMDLetBinding([String])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false)]
        [Switch]$AzureAutomationRunbook
    )
    $apiVersion = '2018-10-01'
    [PSCustomObject]$response = @()
    $uripath = 'subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.ContainerInstance/containerGroups/{2}/start' -f
    $SubscriptionId, $ResourceGroupName, $Name
    $uriquery = '?&api-version={0}' -f $apiVersion
    $builturi = [System.UriBuilder]::new('https', 'management.azure.com', '443', $uripath, $uriquery)
    [uri]$uri = $builturi.Uri
    switch ($AzureAutomationRunbook) {
        { [bool]$PSItem -eq $true } {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM' -AzureIdentity 'AzureAutomationRunAs'
                Uri         = $uri
                Method      = 'POST'
                ErrorAction = 'Stop'
            }
        }
        Default {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM'
                Uri         = $uri
                Method      = 'POST'
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
        Write-Verbose "Successfully started container group: $Name"
    } else {
        Write-Error $Error[0]
        throw $funcerror
    }
}

function Remove-ACIContainerGroup {
    <#
    .SYNOPSIS
        Deletes an existing ACI container group in a subscription and/or resource group.
        See https://docs.microsoft.com/en-us/rest/api/container-instances/containergroups
    .LINK
        https://github.com/WebedMJ/General/tree/master/PowerShell/Azure/Modules/AzureACIREST
    #>
    [CMDLetBinding()]
    [OutputType([String])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $false)]
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
    switch ($AzureAutomationRunbook) {
        { [bool]$PSItem -eq $true } {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM' -AzureIdentity 'AzureAutomationRunAs'
                Uri         = $uri
                Method      = 'DELETE'
                ErrorAction = 'Stop'
            }
        }
        Default {
            $getjobssplat = @{
                Headers     = Get-AzureRESTtoken -AzureResource 'ARM'
                Uri         = $uri
                Method      = 'DELETE'
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
        Write-Verbose "Deleted container group: $Name"
    } else {
        Write-Error $Error[0]
        throw $funcerror
    }
}