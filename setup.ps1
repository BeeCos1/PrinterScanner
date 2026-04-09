Write-Host "Скачивание Scanner PRO..." -ForegroundColor Cyan

# 1. Создаем папку на компе
$InstallDir = "C:\IT_Tools\Scanner"
if (!(Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

# 2. Скачиваем твой pscan.exe (ССЫЛКА ИСПРАВЛЕНА ПОД ТВОЙ РЕПО)
$ExePath = "$InstallDir\pscan.exe"
$Url = "https://github.com/BeeCos1/PrinterScanner/raw/main/pscan.exe"
Invoke-WebRequest -Uri $Url -OutFile $ExePath

# 3. Создаем глобальную команду pscan (Добавили -Force для обхода защиты)
$BatPath = "C:\Windows\pscan.bat"
$BatContent = "@echo off`nstart `"`" `"$ExePath`""
Set-Content -Path $BatPath -Value $BatContent -Force

Write-Host "Готово! Запускаю сканер..." -ForegroundColor Green
Start-Process $ExePath
