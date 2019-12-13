# Code snippet to get all Teams and export apps and team info to CSV

$CSVFilePath = 'C:\Files\TeamsReports\AppsByTeam.csv'

if (!(Test-Path -Path $CSVFilePath -IsValid)) {
    throw 'CSV file path not valid, aborting!'
}
try {
    Write-Verbose "Exporting to $CSVFilePath"
    $Directory = $CSVFilePath | Split-Path -Parent
    if (!(Test-Path -Path $Directory)) {
        New-Item -Path $Directory -ItemType Directory
    }
    $AllTeams = Get-O365Group -All -TeamsOnly -ClientId $ClientId -ClientSecret $ClientSecret -AADTenantDomain $AADTenantDomain
    $AllTeamApps = $AllTeams.ForEach( {
            Get-MSTeamApps -TeamId $PSItem.Id -ClientId $ClientId -ClientSecret $ClientSecret -AADTenantDomain $AADTenantDomain
        })
    $AllTeamApps.ForEach( {
            [PSCustomObject]@{
                TeamId          = $PSItem.TeamId
                TeamDisplayName = $PSItem.TeamDisplayName
                TeamApps        = ($PSItem.TeamApps |
                    Select-Object @{Name = 'AppName'; Expression = { ($_.AppName) } } |
                    Select-Object -ExpandProperty AppName) -join ','
            }
        }) | Export-Csv -Path $CSVFilePath -NoTypeInformation -Force
} catch {
    Write-Error -Message 'Error exporting to CSV!'
}

$CSVFilePath = 'C:\Files\TeamsReports\TeamsByApp.csv'

if (!(Test-Path -Path $CSVFilePath -IsValid)) {
    throw 'CSV file path not valid, aborting!'
}
try {
    Write-Verbose "Exporting to $CSVFilePath"
    $Directory = $CSVFilePath | Split-Path -Parent
    if (!(Test-Path -Path $Directory)) {
        New-Item -Path $Directory -ItemType Directory
    }
    $UniqueApps = $AllTeamApps.TeamApps.AppName | Select-Object -Unique
    $UniqueApps.ForEach( {
            $thisapp = $PSItem
            $Teams = ($AllTeamApps | Where-Object { $_.TeamApps.AppName -imatch $thisapp }).TeamDisplayName
            $TeamList = [PSCustomObject]@{
                AppName   = $thisapp
                AppId     = (($AllTeamApps.TeamApps).Where( { $_.AppName -imatch $thisapp }) | Select-Object -Unique).AppId
                TeamNames = $Teams -join ','
            }
            $TeamList
        }) | Export-Csv -Path $CSVFilePath -NoTypeInformation -Force
} catch {
    Write-Error -Message 'Error exporting to CSV!'
}