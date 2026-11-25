#requires -Version 5.1
<#
.SYNOPSIS
Настройка классической консоли Windows с резервной копией и восстановлением.
.EXAMPLE
.\Customize-Cmd.ps1 -Action Apply -Theme Dracula -Opacity 90 -WhatIf
.EXAMPLE
.\Customize-Cmd.ps1 -Action Restore
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Menu', 'Apply', 'Restore', 'Reset', 'Status')]
    [string]$Action = 'Menu',
    [ValidateSet('Matrix', 'Dracula', 'RetroAmber')][string]$Theme,
    [ValidateSet('Consolas', 'Lucida Console', 'Cascadia Code')][string]$Font,
    [ValidateRange(8, 72)][int]$FontSize = 18,
    [ValidateSet('Small', 'Full')][string]$Cursor,
    [ValidateRange(30, 100)][int]$Opacity,
    [string]$BackupPath = (Join-Path $PSScriptRoot 'backups\original-console.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ConsoleRegPath = 'HKCU:\Console'
$ManagedNames = @((0..15 | ForEach-Object { 'ColorTable{0:D2}' -f $_ })) + @(
    'ScreenColors', 'PopupColors', 'FaceName', 'FontSize', 'FontFamily',
    'FontWeight', 'CursorSize', 'CursorType', 'WindowAlpha'
)

function ConvertTo-ColorRef {
    param([ValidatePattern('^[0-9a-fA-F]{6}$')][string]$Rgb)
    $r = [Convert]::ToInt32($Rgb.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($Rgb.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($Rgb.Substring(4, 2), 16)
    return ($r -bor ($g -shl 8) -bor ($b -shl 16))
}

# Human-readable RGB; the registry expects COLORREF (0x00BBGGRR).
$Schemes = @{
    Matrix = @{
        Colors = '000000 003300 008000 005500 000011 330033 444400 00AA00 002200 00FF00 00CC00 66FF00 000033 660066 FFFF00 00FF00'
        Screen = 0x0A; Popup = 0x02
    }
    Dracula = @{
        Colors = '282A36 6272A4 50FA7B 8BE9FD FF5555 FF79C6 F1FA8C F8F8F2 44475A 6272A4 50FA7B 8BE9FD FF5555 FF79C6 F1FA8C FFFFFF'
        Screen = 0x07; Popup = 0x85
    }
    RetroAmber = @{
        Colors = '000000 201000 804000 603000 800000 400020 905000 FF8000 302000 FFA500 FFB500 FFD000 FF0000 800040 FFE000 FFFF00'
        Screen = 0x0E; Popup = 0x06
    }
}

function Get-ConsoleSnapshot {
    $values = @()
    if (Test-Path -LiteralPath $ConsoleRegPath) {
        $key = Get-Item -LiteralPath $ConsoleRegPath
        try {
            foreach ($name in $ManagedNames) {
                if ($key.GetValueNames() -contains $name) {
                    $values += [pscustomobject]@{
                        Name = $name
                        Kind = $key.GetValueKind($name).ToString()
                        Value = $key.GetValue($name)
                    }
                }
            }
        } finally { $key.Close() }
    }
    [pscustomobject]@{
        Version = 1
        Target = $ConsoleRegPath
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        Values = @($values)
    }
}

function Read-ConsoleBackup {
    $snapshot = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
    if ($snapshot.Version -ne 1 -or $snapshot.Target -ne $ConsoleRegPath -or $snapshot.Values -isnot [array]) {
        throw 'Несовместимая резервная копия: версия или ветка реестра не совпадает.'
    }
    $seen = @{}
    foreach ($entry in $snapshot.Values) {
        if ($entry.Name -notin $ManagedNames -or $seen.ContainsKey($entry.Name)) {
            throw 'Резервная копия содержит неизвестные или повторяющиеся параметры.'
        }
        $seen[$entry.Name] = $true
        if ($entry.Name -eq 'FaceName') {
            if ($entry.Kind -ne 'String' -or $entry.Value -isnot [string]) {
                throw 'Некорректный тип шрифта в резервной копии.'
            }
        } elseif ($entry.Kind -ne 'DWord' -or
            $entry.Value -isnot [ValueType] -or
            [double]$entry.Value -ne [Math]::Truncate([double]$entry.Value) -or
            [double]$entry.Value -lt [int]::MinValue -or
            [double]$entry.Value -gt [int]::MaxValue) {
            throw 'Некорректный DWORD в резервной копии.'
        }
    }
    return $snapshot
}

function Save-OriginalSettings {
    # Never replace the first snapshot with already customized settings.
    if (Test-Path -LiteralPath $BackupPath) {
        $null = Read-ConsoleBackup
        return
    }
    $snapshot = Get-ConsoleSnapshot
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($BackupPath))
    $null = New-Item -ItemType Directory -Path $parent -Force
    $stream = [IO.File]::Open($BackupPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($snapshot | ConvertTo-Json -Depth 5))
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    $null = Read-ConsoleBackup
    Write-Host "Исходные настройки сохранены: $BackupPath" -ForegroundColor DarkGray
}

function Write-ConsoleValues {
    param([System.Collections.IDictionary]$Values)
    if (-not (Test-Path -LiteralPath $ConsoleRegPath)) {
        $null = New-Item -Path $ConsoleRegPath -Force
    }
    foreach ($name in $Values.Keys) {
        $kind = if ($name -eq 'FaceName') { 'String' } else { 'DWord' }
        $null = New-ItemProperty -LiteralPath $ConsoleRegPath -Name $name -Value $Values[$name] -PropertyType $kind -Force
    }
}

function Get-ApplyValues {
    param([hashtable]$Options)
    $values = [ordered]@{}
    if ($Options.ContainsKey('Theme') -and $Options.Theme) {
        $scheme = $Schemes[$Options.Theme]
        $colors = $scheme.Colors.Split(' ')
        for ($i = 0; $i -lt 16; $i++) {
            $values[('ColorTable{0:D2}' -f $i)] = ConvertTo-ColorRef $colors[$i]
        }
        $values.ScreenColors = $scheme.Screen
        $values.PopupColors = $scheme.Popup
    }
    if ($Options.ContainsKey('Font') -and $Options.Font) {
        Add-Type -AssemblyName System.Drawing
        $collection = New-Object System.Drawing.Text.InstalledFontCollection
        try {
            if ($Options.Font -notin @($collection.Families | ForEach-Object { $_.Name })) {
                throw "Шрифт '$($Options.Font)' не установлен. Установите его или выберите другой."
            }
        } finally { $collection.Dispose() }
        $values.FaceName = $Options.Font
        $values.FontSize = $Options.FontSize -shl 16
        $values.FontFamily = 0x36
        $values.FontWeight = 400
    }
    if ($Options.ContainsKey('Cursor') -and $Options.Cursor) {
        $values.CursorSize = if ($Options.Cursor -eq 'Full') { 100 } else { 25 }
        $values.CursorType = 0
    }
    if ($Options.ContainsKey('Opacity')) {
        $values.WindowAlpha = [int][Math]::Round($Options.Opacity * 255 / 100, [MidpointRounding]::AwayFromZero)
    }
    if ($values.Count -eq 0) { throw 'Для Apply укажите Theme, Font, Cursor или Opacity.' }
    return ,$values
}

function Invoke-ConsoleAction {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Operation, [hashtable]$Options = @{})
    if ($Operation -eq 'Status') {
        (Get-ConsoleSnapshot).Values | Format-Table Name, Kind, Value -AutoSize
        return
    }
    $values = $null
    if ($Operation -eq 'Apply') { $values = Get-ApplyValues $Options }
    if ($Operation -eq 'Restore') { $snapshot = Read-ConsoleBackup }
    $description = switch ($Operation) {
        'Apply' { 'Применить: ' + (($values.Keys | ForEach-Object { "$_=$($values[$_])" }) -join ', ') }
        'Restore' { "Восстановить исходные настройки из $BackupPath" }
        'Reset' { 'Удалить управляемые переопределения консоли (включая шрифт и тип курсора)' }
        default { throw "Неизвестная операция: $Operation" }
    }
    if (-not $PSCmdlet.ShouldProcess($ConsoleRegPath, $description)) { return }
    if ($Operation -ne 'Restore') { Save-OriginalSettings }
    if ($Operation -eq 'Apply') {
        Write-ConsoleValues $values
    } else {
        # Keep unrelated settings and all per-app subkeys.
        if (Test-Path -LiteralPath $ConsoleRegPath) {
            $existing = @((Get-ItemProperty -LiteralPath $ConsoleRegPath).PSObject.Properties | ForEach-Object { $_.Name })
            foreach ($name in $ManagedNames) {
                if ($name -in $existing) {
                    Remove-ItemProperty -LiteralPath $ConsoleRegPath -Name $name
                }
            }
        }
        if ($Operation -eq 'Restore') {
            $restored = [ordered]@{}
            foreach ($entry in $snapshot.Values) { $restored[$entry.Name] = $entry.Value }
            if ($restored.Count -gt 0) { Write-ConsoleValues $restored }
        }
    }
    Write-Host 'Готово. Откройте новое окно классической консоли Windows.' -ForegroundColor Green
}

function Show-ConsoleMenu {
    while ($true) {
        Write-Host "`n=== Настройка классической консоли Windows ===" -ForegroundColor Cyan
        Write-Host 'HKCU:\Console: общие настройки Console Host, включая другие консольные приложения.'
        Write-Host '1 Matrix | 2 Dracula | 3 Retro Amber'
        Write-Host '4 Consolas (18 px) | 5 Lucida Console (16 px) | 6 Cascadia Code (18 px)'
        Write-Host '7 Тонкий курсор | 8 Полный курсор | 9 Непрозрачность'
        Write-Host '0 Сброс переопределений | R Восстановление | S Текущие настройки | Q Выход'
        $choice = Read-Host 'Выберите пункт'
        if ($null -eq $choice) { return }
        $choice = $choice.Trim().ToUpperInvariant()
        if ($choice -eq 'Q') { return }
        try {
            switch ($choice) {
                '1' { Invoke-ConsoleAction Apply @{Theme = 'Matrix'} }
                '2' { Invoke-ConsoleAction Apply @{Theme = 'Dracula'} }
                '3' { Invoke-ConsoleAction Apply @{Theme = 'RetroAmber'} }
                '4' { Invoke-ConsoleAction Apply @{Font = 'Consolas'; FontSize = 18} }
                '5' { Invoke-ConsoleAction Apply @{Font = 'Lucida Console'; FontSize = 16} }
                '6' { Invoke-ConsoleAction Apply @{Font = 'Cascadia Code'; FontSize = 18} }
                '7' { Invoke-ConsoleAction Apply @{Cursor = 'Small'} }
                '8' { Invoke-ConsoleAction Apply @{Cursor = 'Full'} }
                '9' {
                    $inputValue = Read-Host 'Непрозрачность (30-100%)'
                    $percent = 0
                    if (-not [int]::TryParse($inputValue, [ref]$percent) -or $percent -lt 30 -or $percent -gt 100) {
                        throw 'Введите целое число от 30 до 100.'
                    }
                    Invoke-ConsoleAction Apply @{Opacity = $percent}
                }
                '0' {
                    if ((Read-Host 'Удалить переопределения? Введите ДА') -eq 'ДА') { Invoke-ConsoleAction Reset }
                }
                'R' { Invoke-ConsoleAction Restore }
                'S' { Invoke-ConsoleAction Status }
                default { Write-Warning 'Неизвестный пункт меню.' }
            }
        } catch { Write-Warning $_.Exception.Message }
    }
}

# Dot-sourcing loads functions for isolated tests without executing the menu.
if ($MyInvocation.InvocationName -ne '.') {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Утилита поддерживает только Windows.'
    }
    $settingNames = @('Theme', 'Font', 'FontSize', 'Cursor', 'Opacity')
    $specifiedSettings = @($settingNames | Where-Object { $PSBoundParameters.ContainsKey($_) })
    if ($Action -ne 'Apply' -and $specifiedSettings.Count -gt 0) {
        throw 'Параметры оформления требуют -Action Apply.'
    }
    if ($PSBoundParameters.ContainsKey('FontSize') -and -not $Font) {
        throw 'Укажите -Font вместе с -FontSize.'
    }
    if ($Action -eq 'Menu') {
        Show-ConsoleMenu
    } else {
        $options = @{Theme = $Theme; Font = $Font; FontSize = $FontSize; Cursor = $Cursor}
        if ($PSBoundParameters.ContainsKey('Opacity')) { $options.Opacity = $Opacity }
        Invoke-ConsoleAction -Operation $Action -Options $options
    }
}
