Describe 'Loading Shim' {
  Mock Add-Type { throw "Could not load file or assembly 'System.ServiceModel.Web, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35' or one of its dependencies. The system cannot find the file specified." }

  It 'Throws a helpful error message' {
    { . $PSScriptRoot\..\PowershellShim-Helper.ps1 } | Should -Throw "PXP Agent could not load the assemblies needed for JSON parsing. Please install .NET Framework 3.5 or greater, or rewrite the task to use a different input method than 'powershell'."
  }
}

. $PSScriptRoot\..\PowershellShim-Helper.ps1

Describe 'ConvertFrom-Json2 | ConvertFrom-PSCustomObject' {
  It 'Given an empty string, will return an empty object' {
    $result = '{}' | ConvertFrom-Json2 -Type PSObject | ConvertFrom-PSCustomObject
    $result | Should -Be $null
  }

  It 'Given boolean json, should return a hash containing a boolean' {
    $result = '{"boolKey": true}' | ConvertFrom-Json2 -Type PSObject | ConvertFrom-PSCustomObject
    $result.Count | Should -Be 1
    $result['boolKey'] | Should -Be $true
  }

  It 'Given integer json, should return a hash containing an int' {
    $result = '{"intKey": 5}' | ConvertFrom-Json2 -Type PSObject | ConvertFrom-PSCustomObject
    $result.Count | Should -Be 1
    $result['intKey'] | Should -Be 5
  }

  It 'Given float json, should return a hash containing a float' {
    $result = '{"floatKey": 5.5}' | ConvertFrom-Json2 -Type PSObject | ConvertFrom-PSCustomObject
    $result.Count | Should -Be 1
    $result['floatKey'] | Should -Be 5.5
  }

  It 'Given string json, should return a hash containing a string' {
    $result = '{"stringKey": "hello world"}' | ConvertFrom-Json2 -Type PSObject | ConvertFrom-PSCustomObject
    $result.Count | Should -Be 1
    $result['stringKey'] | Should -Be "hello world"
  }

  It 'Given array json, should return a hash containing the array' {
    $result = Get-ContentAsJson '{"arrayOfHashes": [{"name": "puppet", "version": 42}, {"name": "pe", "version": 2015}]}'
    $result.Count | Should -Be 1
    $arr = $result['arrayOfHashes']
    $arr.Count | Should -Be 2
    $arr[0]['name'] | Should -Be 'puppet'
    $arr[0]['version'] | Should -Be 42
    $arr[1]['name'] | Should -Be 'pe'
    $arr[1]['version'] | Should -Be 2015
  }
}

Describe 'PowershellShim' {
  it 'Runs the powershell script with the parameters supplied as JSON' {
    $result = '{"message": "hello world"}' | & $PSScriptRoot\..\PowershellShim.ps1 $PSScriptRoot\Echo.ps1
    $result | Should -Be "hello world"
  }

  it 'Runs the powershell script with only the parameters it understands' {
    $result = '{"message": "hello world", "_task": "echo"}' | & $PSScriptRoot\..\PowershellShim.ps1 $PSScriptRoot\Echo.ps1
    $result | Should -Be "hello world"
  }
}
