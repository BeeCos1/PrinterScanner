[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
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
Write-Host "4. [ProcKill]- поиск подозрительных фоновых процессов (Графическое окно)"
Write-Host "0. [Exit]    - Выход"
Write-Host "-----------------------------------------------"

$choice = Read-Host "Выберите пункт меню (0-4)"

switch ($choice) {
    "1" {
        Write-Host "[*] Работа со Сканером..." -ForegroundColor Green
        $InstallDir = "C:\IT_Tools\Scanner"
        if (!(Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
        
        $ExePath = "$InstallDir\pscan.exe"
        $Url = "https://cdn.jsdelivr.net/gh/BeeCos1/PrinterScanner@main/pscan.png"
        
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
        cmd.exe /c "chkdsk C: /scan"

        Write-Host "`n[+++] ОЧИСТКА ЗАВЕРШЕНА [+++]" -ForegroundColor Green
        Pause
    }
    
    "3" {
        Write-Host "[*] ЗАПУСК АКТИВАЦИИ OFFICE..." -ForegroundColor Magenta
        Write-Host "[!] Используется внешний скрипт activated.win" -ForegroundColor Gray
        irm https://get.activated.win | iex
    }

 "4" {
        while ($true) {
            Clear-Host
            Write-Host "[*] АНАЛИЗ ФОНОВЫХ ПРОЦЕССОВ..." -ForegroundColor Yellow
            Write-Host "[>] Идет сбор данных. Пожалуйста, подождите..." -ForegroundColor Gray

            # Список для поиска фейков
            $fakeNames = "(?i)^(svchost|lsass|csrss|smss|wininit|services|explorer|winlogon|spoolsv)$"

            # Собираем процессы
            $suspicious = Get-Process | Where-Object {
                $_.Path -and
                $_.Path -notmatch "(?i)^C:\\Windows\\" -and
                $_.Name -notmatch "(?i)chrome|firefox|msedge|opera|Taskmgr"
            } | Select-Object Id, 
                Name, 
                @{Name='СТАТУС';Expression={if ($_.Name -match $fakeNames) { "⚠️ ФЕЙК СИСТЕМЫ!" } else { "Обычный" }}},
                @{Name='RAM (MB)';Expression={[double]([math]::Round($_.WorkingSet64 / 1MB, 1))}}, 
                Path | Sort-Object 'СТАТУС' -Descending

            if ($suspicious.Count -eq 0) {
                Write-Host "[+] Подозрительных активностей не найдено." -ForegroundColor Green
                Pause
                break # Выход из цикла обратно в главное меню
            }

            # Вызов окна
            $toKill = $suspicious | Out-GridView -Title "ВЫБЕРИТЕ ПРОЦЕССЫ -> НАЖМИТЕ 'ОК'. (Нажмите 'Отмена' для выхода в меню)" -PassThru

            # Если пользователь выделил процессы и нажал ОК:
            if ($toKill) {
                Write-Host "`nВы выбрали $($toKill.Count) процесс(ов). Как их завершить?" -ForegroundColor Cyan
                Write-Host "1 - Точечно (только выбранный процесс)"
                Write-Host "2 - С корнями (процесс + все его скрытые 'матрешки' / дочерние процессы)"
                $killChoice = Read-Host "Ваш выбор (1 или 2)"

                foreach ($proc in $toKill) {
                    if ($killChoice -eq "2") {
                        # Выстрел из базуки: убиваем дерево процессов через taskkill
                        taskkill.exe /F /T /PID $proc.Id *>&1 | Out-Null
                        Write-Host "[+] Процесс $($proc.Name) (PID: $($proc.Id)) убит ВМЕСТЕ С КОРНЯМИ!" -ForegroundColor Green
                    } else {
                        # Снайперский выстрел: только точечный процесс
                        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                        Write-Host "[+] Процесс $($proc.Name) (PID: $($proc.Id)) точечно убит." -ForegroundColor Green
                    }
                }
                Write-Host "[>] Обновление списка через 2 секунды..." -ForegroundColor Gray
                Start-Sleep -Seconds 2
            } 
            # Если пользователь нажал Отмена или крестик:
            else {
                Write-Host "[*] Выход из сканера. Возврат в главное меню." -ForegroundColor Gray
                Start-Sleep -Seconds 1
                break # Ломаем цикл и возвращаемся в главное меню
            }
        }
    }
    
    "0" {
        Write-Host "Выход..." -ForegroundColor Red
        return
    }

    Default {
        Write-Host "Неверный выбор, попробуйте еще раз." -ForegroundColor Red
        Pause
    }
}
