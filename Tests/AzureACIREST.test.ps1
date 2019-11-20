$modulepath = "$PSScriptRoot\..\AzureACIREST"

try {
    $result = Invoke-ScriptAnalyzer -Path $modulepath -Recurse
    switch ($result) {
        { 0 -lt $PSItem.count } {
            $result
            throw 'Issues detected by PSScriptAnalyzer, aborting further tests'
        }
        Default {
            $result
        }
    }
} catch {
    Write-Error $error[0]
    throw 'Script Analyzer failed'
}

# Import-Module -Name $PSScriptRoot\..\AzureACIREST
# Pester testing to follow...