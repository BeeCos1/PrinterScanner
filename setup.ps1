Write-Host "Скачивание Scanner PRO..." -ForegroundColor Cyan

# 1. Создаем папку на компе (скрытая установка)
$InstallDir = "C:\IT_Tools\Scanner"
New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

# 2. Скачиваем твой pscan.exe (!!! ЗАМЕНИ ССЫЛКУ НА СВОЮ !!!)
$ExePath = "$InstallDir\pscan.exe"
Invoke-WebRequest -Uri "https://github.com/ТВОЙ_ЛОГИН/ТВОЙ_РЕПОЗИТОРИЙ/raw/main/pscan.exe" -OutFile $ExePath

# 3. Создаем глобальную команду pscan
$BatPath = "C:\Windows\pscan.bat"
"@echo off`nstart `"`" `"$ExePath`"" | Out-File -FilePath $BatPath -Encoding ascii

Write-Host "Готово! Запускаю сканер..." -ForegroundColor Green
Start-Process $ExePath