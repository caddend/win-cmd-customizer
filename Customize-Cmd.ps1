# Customize-Cmd.ps1
# Настройка внешнего вида командной строки Windows (cmd.exe) через реестр HKCU:\Console

[CmdletBinding()]
param()

$ConsoleRegPath = "HKCU:\Console"

function Ensure-RegistryPath {
    if (-not (Test-Path $ConsoleRegPath)) {
        New-Item -Path $ConsoleRegPath -Force | Out-Null
    }
}

function Set-ConsoleProperty {
    param (
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord"
    )
    Ensure-RegistryPath
    Set-ItemProperty -Path $ConsoleRegPath -Name $Name -Value $Value -Type $Type -Force
}

$ColorSchemes = @{
    "1" = @{
        Name       = "Matrix (Зеленый на черном)"
        ColorTable = @(
            0x00000000, 0x00003300, 0x00008000, 0x00005500,
            0x00110000, 0x00330033, 0x00004444, 0x0000aa00,
            0x00002200, 0x0000ff00, 0x0000cc00, 0x0000ff66,
            0x00330000, 0x00660066, 0x0000ffff, 0x0000ff00
        )
        ScreenColors = 0x0A
        PopupColors  = 0x02
    }
    "2" = @{
        Name       = "Dracula (Темно-фиолетовая тема)"
        ColorTable = @(
            0x00282a36, 0x006272a4, 0x0050fa7b, 0x008be9fd,
            0x00ff5555, 0x00ff79c6, 0x00f1fa8c, 0x00f8f8f2,
            0x0044475a, 0x006272a4, 0x0050fa7b, 0x008be9fd,
            0x00ff5555, 0x00ff79c6, 0x00f1fa8c, 0x00ffffff
        )
        ScreenColors = 0x07
        PopupColors  = 0x85
    }
    "3" = @{
        Name       = "Retro Amber (Янтарный терминал)"
        ColorTable = @(
            0x00000000, 0x00001020, 0x00004080, 0x00003060,
            0x00000080, 0x00200040, 0x00005090, 0x000080ff,
            0x00002030, 0x0000a5ff, 0x0000b5ff, 0x0000d0ff,
            0x000000ff, 0x00400080, 0x0000e0ff, 0x0000ffff
        )
        ScreenColors = 0x0E
        PopupColors  = 0x06
    }
}

$Fonts = @{
    "1" = @{ Name = "Consolas"; Size = 0x00120000 }      # 18 pt
    "2" = @{ Name = "Lucida Console"; Size = 0x00100000 }# 16 pt
    "3" = @{ Name = "Cascadia Code"; Size = 0x00120000 } # 18 pt
}

function Apply-Scheme {
    param ([string]$Key)

    if (-not $ColorSchemes.ContainsKey($Key)) {
        Write-Warning "Неверный выбор схемы."
        return
    }

    $scheme = $ColorSchemes[$Key]
    Ensure-RegistryPath

    for ($i = 0; $i -lt 16; $i++) {
        $regName = "ColorTable{0:D2}" -f $i
        Set-ConsoleProperty -Name $regName -Value $scheme.ColorTable[$i] -Type "DWord"
    }

    Set-ConsoleProperty -Name "ScreenColors" -Value $scheme.ScreenColors -Type "DWord"
    Set-ConsoleProperty -Name "PopupColors" -Value $scheme.PopupColors -Type "DWord"
    Write-Host "Цветовая схема '$($scheme.Name)' успешно применена!" -ForegroundColor Green
}

function Apply-Font {
    param ([string]$Key)

    if (-not $Fonts.ContainsKey($Key)) {
        Write-Warning "Неверный выбор шрифта."
        return
    }

    $font = $Fonts[$Key]
    Set-ConsoleProperty -Name "FaceName" -Value $font.Name -Type "String"
    Set-ConsoleProperty -Name "FontSize" -Value $font.Size -Type "DWord"
    Set-ConsoleProperty -Name "FontFamily" -Value 0x00000036 -Type "DWord"
    Set-ConsoleProperty -Name "FontWeight" -Value 400 -Type "DWord"
    Write-Host "Шрифт '$($font.Name)' успешно применен!" -ForegroundColor Green
}

function Apply-CursorSettings {
    param (
        [int]$CursorSize,
        [int]$CursorType = 0
    )
    Set-ConsoleProperty -Name "CursorSize" -Value $CursorSize -Type "DWord"
    Set-ConsoleProperty -Name "CursorType" -Value $CursorType -Type "DWord"
    Write-Host "Параметры курсора обновлены!" -ForegroundColor Green
}

function Apply-Opacity {
    param ([int]$Percent)
    if ($Percent -lt 30 -or $Percent -gt 100) {
        Write-Warning "Прозрачность должна быть в диапазоне от 30 до 100."
        return
    }
    $val = [int]($Percent * 255 / 100)
    Set-ConsoleProperty -Name "WindowAlpha" -Value $val -Type "DWord"
    Write-Host "Непрозрачность установлена на $Percent%." -ForegroundColor Green
}

function Reset-ToDefaults {
    $defaultColors = @(
        0x00000000, 0x00800000, 0x00008000, 0x00808000,
        0x00000080, 0x00800080, 0x00008080, 0x00c0c0c0,
        0x00808080, 0x00ff0000, 0x0000ff00, 0x00ffff00,
        0x000000ff, 0x00ff00ff, 0x0000ffff, 0x00ffffff
    )

    Ensure-RegistryPath
    for ($i = 0; $i -lt 16; $i++) {
        $regName = "ColorTable{0:D2}" -f $i
        Set-ConsoleProperty -Name $regName -Value $defaultColors[$i] -Type "DWord"
    }

    Set-ConsoleProperty -Name "ScreenColors" -Value 0x07 -Type "DWord"
    Set-ConsoleProperty -Name "PopupColors" -Value 0x85 -Type "DWord"
    Set-ConsoleProperty -Name "FaceName" -Value "Consolas" -Type "String"
    Set-ConsoleProperty -Name "FontSize" -Value 0x00100000 -Type "DWord"
    Set-ConsoleProperty -Name "CursorSize" -Value 25 -Type "DWord"
    Set-ConsoleProperty -Name "WindowAlpha" -Value 255 -Type "DWord"

    Write-Host "Настройки консоли сброшены к значениям по умолчанию!" -ForegroundColor Yellow
}

function Show-Menu {
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "       Кастомизация Windows CMD (HKCU)        " -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "1. Цветовая схема Matrix (Green on Black)"
    Write-Host "2. Цветовая схема Dracula"
    Write-Host "3. Цветовая схема Retro Amber"
    Write-Host "4. Шрифт Consolas (18pt)"
    Write-Host "5. Шрифт Lucida Console (16pt)"
    Write-Host "6. Шрифт Cascadia Code (18pt)"
    Write-Host "7. Курсор: Тонкий блок (Small)"
    Write-Host "8. Курсор: Полный квадрат (Full)"
    Write-Host "9. Настроить прозрачность окна (30-100%)"
    Write-Host "0. Сбросить все настройки к стандартным"
    Write-Host "Q. Выход"
    Write-Host "----------------------------------------------"
}

do {
    Show-Menu
    $choice = Read-Host "Выберите пункт меню"
    switch ($choice) {
        "1" { Apply-Scheme -Key "1" }
        "2" { Apply-Scheme -Key "2" }
        "3" { Apply-Scheme -Key "3" }
        "4" { Apply-Font -Key "1" }
        "5" { Apply-Font -Key "2" }
        "6" { Apply-Font -Key "3" }
        "7" { Apply-CursorSettings -CursorSize 25 }
        "8" { Apply-CursorSettings -CursorSize 100 }
        "9" {
            $p = Read-Host "Введите процент непрозрачности (30-100)"
            Apply-Opacity -Percent ([int]$p)
        }
        "0" { Reset-ToDefaults }
        "Q" { Write-Host "Выход из программы..."; break }
        "q" { Write-Host "Выход из программы..."; break }
        default { Write-Warning "Неизвестный параметр. Нажмите Enter для повтора." }
    }
    if ($choice -notin @("Q", "q")) {
        Write-Host "`nИзменения применятся к новым окнам cmd.exe." -ForegroundColor DarkGray
        Pause
    }
} while ($choice -notin @("Q", "q"))
