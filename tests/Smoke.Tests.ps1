#requires -Version 5.1
# No Pester dependency. Every registry write is restricted to a unique test key.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'Customize-Cmd.ps1')
$id = [guid]::NewGuid().ToString('N')
$ConsoleRegPath = "HKCU:\Software\WinCmdCustomizerTests\$id"
$scratch = Join-Path $PSScriptRoot ".scratch-$id"
$BackupPath = Join-Path $scratch 'original.json'
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
}
function Assert-Throws {
    param([scriptblock]$Code, [string]$Message)
    $thrown = $false
    try { & $Code | Out-Null } catch { $thrown = $true }
    Assert-True $thrown $Message
}

try {
    Assert-True ((ConvertTo-ColorRef '282A36') -eq 0x362A28) 'Dracula RGB conversion'
    Assert-True ((ConvertTo-ColorRef 'FF0000') -eq 255) 'Red COLORREF'
    foreach ($name in $Schemes.Keys) {
        $values = Get-ApplyValues @{Theme = $name}
        Assert-True ($values.Count -eq 18) "Complete palette: $name"
    }
    Assert-True ((Get-ApplyValues @{Opacity = 30}).WindowAlpha -eq 77) 'Minimum alpha'
    Assert-True ((Get-ApplyValues @{Opacity = 100}).WindowAlpha -eq 255) 'Maximum alpha'
    Assert-Throws { Get-ApplyValues @{} } 'Empty apply rejected'
    Assert-Throws { Get-ApplyValues @{Font = 'Missing-font-for-test-123'; FontSize = 18} } 'Unavailable font rejected'
    Add-Type -AssemblyName System.Drawing
    $fonts = New-Object System.Drawing.Text.InstalledFontCollection
    try { $installedFont = $fonts.Families[0].Name } finally { $fonts.Dispose() }
    $fontValues = Get-ApplyValues @{Font = $installedFont; FontSize = 20}
    Assert-True ($fontValues.FaceName -eq $installedFont -and $fontValues.FontSize -eq 0x00140000) 'Installed font and pixel size'

    Invoke-ConsoleAction Apply @{Theme = 'Dracula'} -WhatIf
    Assert-True (-not (Test-Path $ConsoleRegPath)) 'WhatIf does not create registry key'
    Assert-True (-not (Test-Path $BackupPath)) 'WhatIf does not create backup'

    $null = New-Item -Path $ConsoleRegPath -Force
    $null = New-ItemProperty $ConsoleRegPath -Name ScreenColors -Value 23 -PropertyType DWord
    $null = New-ItemProperty $ConsoleRegPath -Name FaceName -Value 'Original font' -PropertyType String
    $null = New-ItemProperty $ConsoleRegPath -Name Unrelated -Value 'keep' -PropertyType String
    $null = New-Item -Path "$ConsoleRegPath\Child" -Force
    Invoke-ConsoleAction Apply @{Theme = 'Dracula'; Cursor = 'Full'; Opacity = 30}
    Assert-True ((Get-ItemProperty $ConsoleRegPath).ColorTable00 -eq 0x362A28) 'Dracula registry value'
    Assert-True ((Get-ItemProperty $ConsoleRegPath).CursorSize -eq 100) 'Full cursor'
    $firstBackup = Get-Content $BackupPath -Raw
    Invoke-ConsoleAction Apply @{Theme = 'Matrix'}
    Assert-True ((Get-Content $BackupPath -Raw) -ceq $firstBackup) 'First backup preserved'

    Invoke-ConsoleAction Restore -WhatIf
    Assert-True ((Get-ItemProperty $ConsoleRegPath).ScreenColors -eq 10) 'Restore WhatIf does not write'
    Invoke-ConsoleAction Restore
    $state = Get-ItemProperty $ConsoleRegPath
    Assert-True ($state.ScreenColors -eq 23 -and $state.FaceName -eq 'Original font') 'Original values restored'
    Assert-True ('CursorSize' -notin $state.PSObject.Properties.Name) 'Originally absent value removed'
    Assert-True ($state.Unrelated -eq 'keep') 'Unrelated value preserved'
    Assert-True (Test-Path "$ConsoleRegPath\Child") 'Subkey preserved'

    Invoke-ConsoleAction Reset -WhatIf
    Assert-True ((Get-ItemProperty $ConsoleRegPath).ScreenColors -eq 23) 'Reset WhatIf does not write'
    Invoke-ConsoleAction Reset
    $state = Get-ItemProperty $ConsoleRegPath
    Assert-True ('ScreenColors' -notin $state.PSObject.Properties.Name) 'Reset removes managed values'
    Assert-True ($state.Unrelated -eq 'keep') 'Reset preserves unrelated values'
    Invoke-ConsoleAction Restore

    $bad = $firstBackup | ConvertFrom-Json
    $bad.Values[0].Name = 'Unrelated'
    $bad | ConvertTo-Json -Depth 5 | Set-Content $BackupPath -Encoding UTF8
    Assert-Throws { Invoke-ConsoleAction Restore } 'Unknown backup property rejected'
    Assert-True ((Get-ItemProperty $ConsoleRegPath).ScreenColors -eq 23) 'Invalid backup does not mutate registry'
    $bad.Values = $null
    $bad | ConvertTo-Json -Depth 5 | Set-Content $BackupPath -Encoding UTF8
    Assert-Throws { Invoke-ConsoleAction Restore } 'Null backup values rejected'
    Set-Content $BackupPath -Value $firstBackup -Encoding UTF8
    Assert-Throws { & (Join-Path $repo 'Customize-Cmd.ps1') -Action Apply -Opacity 29 -WhatIf } 'CLI opacity validation'
    Assert-Throws { & (Join-Path $repo 'Customize-Cmd.ps1') -Action Apply -FontSize 20 -WhatIf } 'Font size requires font'
    Assert-Throws { & (Join-Path $repo 'Customize-Cmd.ps1') -Theme Matrix -WhatIf } 'CLI settings require Apply'

    $script:answers = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($answer in @('9', 'abc', '9', '101', 'q')) { $script:answers.Enqueue($answer) }
    function Read-Host { param([string]$Prompt) $script:answers.Dequeue() }
    $warnings = @(Show-ConsoleMenu 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    Assert-True ($warnings.Count -eq 2 -and $script:answers.Count -eq 0) 'Invalid interactive input recovers and q exits'
    Remove-Item Function:\Read-Host

    # A backup with no managed values must also round-trip correctly.
    $ConsoleRegPath = "$ConsoleRegPath\Empty"
    $BackupPath = Join-Path $scratch 'empty.json'
    Invoke-ConsoleAction Apply @{Cursor = 'Small'}
    Invoke-ConsoleAction Restore
    $emptyNames = @((Get-ItemProperty $ConsoleRegPath).PSObject.Properties | ForEach-Object { $_.Name })
    Assert-True ('CursorSize' -notin $emptyNames) 'Empty snapshot restored'
    Invoke-ConsoleAction Reset
    Write-Host "PASS: $passed assertions ($($PSVersionTable.PSVersion))" -ForegroundColor Green
} finally {
    # Exact generated paths only; never touch HKCU:\Console.
    $testKey = "HKCU:\Software\WinCmdCustomizerTests\$id"
    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    if (Test-Path -LiteralPath $scratch) {
        $resolved = [IO.Path]::GetFullPath($scratch)
        $expected = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".scratch-$id"))
        if ($resolved -ne $expected) { throw 'Unexpected scratch path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
