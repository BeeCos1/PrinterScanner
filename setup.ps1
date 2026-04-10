Clear-Host
# Проверка на права администратора (нужна для SFC, DISM и записи в C:\Windows)
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "!!! ОШИБКА: ЗАПУСТИТЕ POWERSHELL ОТ ИМЕНИ АДМИНИСТРАТОРА !!!" -ForegroundColor Red
    return
}

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   IT-TOOLSET BY BEECOS1 (HELPDESK EDITION)   " -ForegroundColor Yellow
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "1. [Scanner] - Запустить Сканер принтеров"
Write-Host "2. [Cleaner] - Очистка системы (Temp, DNS, SFC, DISM)"
Write-Host "3. [Office]  - Активация Office (Online)"
Write-Host "0. [Exit]    - Выход"
Write-Host "-----------------------------------------------"

$choice = Read-Host "Выберите пункт меню (0-3)"

switch ($choice) {
    "1" {
        Write-Host "[*] Работа со Сканером..." -ForegroundColor Green
        $InstallDir = "C:\IT_Tools\Scanner"
        if (!(Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
        
        $ExePath = "$InstallDir\pscan.exe"
        $Url = "https://github.com/BeeCos1/PrinterScanner/raw/main/pscan.exe"
        
        Write-Host "[>] Скачивание свежей версии..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $Url -OutFile $ExePath
        
        $BatPath = "C:\Windows\pscan.bat"
        "@echo off`nstart `"`" `"$ExePath`"" | Set-Content -Path $BatPath -Force
        
        Write-Host "[+] Готово. Запуск..." -ForegroundColor Green
        Start-Process $ExePath
    }
    
    "2" {
        Write-Host "[*] ЗАПУСК ОЧИСТКИ И ДИАГНОСТИКИ..." -ForegroundColor Yellow
        
        # Очистка Temp
        Write-Host "[>] Чистим временные файлы..." -ForegroundColor Gray
        $TempPaths = @("$env:TEMP\*", "C:\Windows\Temp\*", "C:\Windows\Prefetch\*")
        foreach ($path in $TempPaths) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Корзина
        Write-Host "[>] Чистим корзину..." -ForegroundColor Gray
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue

        # Сеть
        Write-Host "[>] Сброс DNS кэша..." -ForegroundColor Gray
        ipconfig /flushdns | Out-Null

        # Системные проверки
        Write-Host "[>] Запуск SFC (проверка файлов)..." -ForegroundColor Cyan
        sfc /scannow
        
        Write-Host "[>] Запуск DISM (восстановление хранилища)..." -ForegroundColor Cyan
        DISM /Online /Cleanup-Image /RestoreHealth

        Write-Host "[>] Проверка диска C:..." -ForegroundColor Cyan
        Start-Process -FilePath "chkdsk.exe" -ArgumentList "C: /scan" -Verb RunAs -Wait -NoNewWindow

        Write-Host "`n[+++] ОЧИСТКА ЗАВЕРШЕНА [+++]" -ForegroundColor Green
        Pause
    }
    
    "3" {
        Write-Host "[*] ЗАПУСК АКТИВАЦИИ OFFICE..." -ForegroundColor Magenta
        Write-Host "[!] Используется внешний скрипт activated.win" -ForegroundColor Gray
        irm https://get.activated.win | iex
    }
    
    "0" {
        Write-Host "Выход..." -ForegroundColor Red
        return
    }
}
