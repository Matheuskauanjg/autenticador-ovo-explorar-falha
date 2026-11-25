#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)]
    [ValidateSet('Inspect','Setup','Virtualization','EnableWHPX','Start','Stop','Restart','Install','Uninstall','Resources','Logs','Diagnose','Configure','Backup','Restore','Push','Pull','Test')]
    [string]$Action,
    [string]$Apk, [string]$Package, [string]$LocalPath, [string]$DevicePath,
    [ValidatePattern('^[a-zA-Z0-9_-]{1,64}$')][string]$Snapshot = 'backup',
    [ValidateRange(1,16)][int]$Cores,
    [ValidateRange(1536,8192)][int]$RamMB,
    [ValidateSet('auto','host','software')][string]$Gpu,
    [switch]$ConfirmRestore
)
$ErrorActionPreference = 'Stop'
$state = if ($env:ANDROID12_LOCAL_HOME) { $env:ANDROID12_LOCAL_HOME } else { Join-Path $PSScriptRoot '.local' }
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -First 1
if (!$sdk) { $sdk = Join-Path $state 'sdk' }
$oldHome = $env:ANDROID_HOME
$oldSdk = $env:ANDROID_SDK_ROOT
$oldAvd = $env:ANDROID_AVD_HOME
$oldJava = $env:JAVA_HOME
$env:ANDROID_HOME = $env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_AVD_HOME = Join-Path $state 'avd'
$avd = 'Android12Local_API31'
$image = 'system-images;android-31;google_apis_playstore;x86_64'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$ini = Join-Path $env:ANDROID_AVD_HOME "$avd.ini"
$config = Join-Path $state 'resources.json'
$connection = Join-Path $state 'connection.json'
$imageFolder = Join-Path $sdk 'system-images\android-31\google_apis_playstore\x86_64'
$serial = $null

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe terminou com código $LASTEXITCODE." }
}

function Get-HostInfo {
    $cpu = Get-Item 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
    $processor = try { Get-CimInstance Win32_Processor | Select-Object -First 1 } catch {}
    $computer = try { Get-CimInstance Win32_ComputerSystem } catch {}
    $memory = if ($computer) { $computer.TotalPhysicalMemory } else { [GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes }
    [pscustomobject]@{
        CPU = $cpu.GetValue('ProcessorNameString')
        Vendor = $cpu.GetValue('VendorIdentifier')
        Architecture = [string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        LogicalCores = [Environment]::ProcessorCount
        MemoryMB = [long]($memory / 1MB)
        FirmwareVirtualization = $processor.VirtualizationFirmwareEnabled
        SLAT = $processor.SecondLevelAddressTranslationExtensions
        HypervisorPresent = $computer.HypervisorPresent
        SdkFreeGB = [Math]::Round([IO.DriveInfo]::new([IO.Path]::GetPathRoot($sdk)).AvailableFreeSpace / 1GB, 1)
        StateFreeGB = [Math]::Round([IO.DriveInfo]::new([IO.Path]::GetPathRoot($state)).AvailableFreeSpace / 1GB, 1)
        SDK = $sdk
        ADB = Test-Path $adb
        Emulator = Test-Path $emulator
        Image = (Test-Path (Join-Path $imageFolder 'system.img')) -and
            ((Test-Path (Join-Path $imageFolder 'package.xml')) -or (Test-Path (Join-Path $imageFolder 'source.properties')))
    }
}

function Assert-Acceleration {
    if (!(Test-Path $emulator)) { throw 'O emulador ainda precisa ser instalado.' }
    $result = & $emulator -accel-check | Out-String
    if ($LASTEXITCODE -ne 0 -or $result -notmatch '(?m)^\s*0\s*$') {
        throw "Aceleração indisponível. Verifique SVM no UEFI e WHPX no Windows. $result"
    }
    $result.Trim()
}

function Get-Resources {
    if (Test-Path $config) { return Get-Content $config -Raw | ConvertFrom-Json }
    $hostInfo = Get-HostInfo
    [pscustomobject]@{
        Cores = [Math]::Max(1,[Math]::Min(4,[Math]::Floor($hostInfo.LogicalCores / 2)))
        RamMB = [Math]::Max(1536,[Math]::Min(4096,[Math]::Floor($hostInfo.MemoryMB / 4)))
        Gpu = 'auto'
    }
}

function Get-Java {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += "$env:JAVA_HOME\bin\java.exe" }
    $candidates += (Get-Command java.exe -ErrorAction SilentlyContinue).Source
    $candidates += "$env:ProgramFiles\Android\Android Studio\jbr\bin\java.exe"
    $candidates += "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\java.exe"
    $candidates += @(Get-ChildItem "$env:ProgramFiles\Microsoft\jdk-21*\bin\java.exe" -ErrorAction SilentlyContinue).FullName
    foreach ($candidate in $candidates) {
        if (!$candidate -or !(Test-Path -LiteralPath $candidate)) { continue }
        $version = & $candidate -version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $version -match 'version "(\d+)' -and [int]$Matches[1] -ge 17) {
            return $candidate
        }
    }
}

function Invoke-Setup {
    $hostInfo = Get-HostInfo
    $hostInfo | Out-Host
    if ($hostInfo.Architecture -ne 'X64') { throw 'Este projeto requer Windows x64.' }
    if ((!$hostInfo.Image -or !$hostInfo.Emulator) -and $hostInfo.SdkFreeGB -lt 12) {
        throw 'Reserve pelo menos 12 GiB livres no volume do SDK.'
    }
    if (!(Test-Path $ini) -and $hostInfo.StateFreeGB -lt 8) { throw 'Reserve 8 GiB para o AVD.' }
    if ($hostInfo.ADB -and $hostInfo.Emulator -and $hostInfo.Image -and (Test-Path $ini)) {
        Assert-Acceleration
        return
    }
    $java = Get-Java
    if (!$java) {
        $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
        if (!$winget) { throw 'Instale um JDK 21 e defina JAVA_HOME ou disponibilize o WinGet.' }
        Invoke-Checked $winget @('install','--id','Microsoft.OpenJDK.21','-e','--source','winget')
        $java = Get-Java
        if (!$java) { throw 'Defina JAVA_HOME para o JDK 21 e execute Setup novamente.' }
    }
    $env:JAVA_HOME = Split-Path (Split-Path $java)
    $manager = Get-ChildItem (Join-Path $sdk 'cmdline-tools\*\bin\sdkmanager.bat') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (!$manager) {
        $cache = Join-Path $state 'downloads'
        New-Item -ItemType Directory -Force $cache, "$sdk\cmdline-tools" | Out-Null
        $archive = Join-Path $cache 'commandlinetools-win-15859902.zip'
        $hash = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
        if (!(Test-Path $archive) -or (Get-FileHash $archive).Hash -ne $hash) {
            Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' -OutFile $archive
        }
        if ((Get-FileHash $archive).Hash -ne $hash) { throw 'SHA-256 das ferramentas Android diverge do valor oficial.' }
        $stage = Join-Path $cache ([guid]::NewGuid().ToString())
        Expand-Archive -LiteralPath $archive -DestinationPath $stage
        $destination = Join-Path $sdk 'cmdline-tools\15859902'
        if (Test-Path $destination) { throw "Diretório existente incompleto: $destination" }
        Move-Item -LiteralPath (Join-Path $stage 'cmdline-tools') -Destination $destination
        $manager = Get-Item (Join-Path $destination 'bin\sdkmanager.bat')
    }
    $needed = @()
    if (!$hostInfo.ADB) { $needed += 'platform-tools' }
    if (!$hostInfo.Emulator) { $needed += 'emulator' }
    if (!$hostInfo.Image) { $needed += $image }
    if ($needed) { Invoke-Checked $manager.FullName (@("--sdk_root=$sdk",'--install') + $needed) }
    New-Item -ItemType Directory -Force $env:ANDROID_AVD_HOME | Out-Null
    if (!(Test-Path $ini)) {
        'no' | & (Join-Path $manager.DirectoryName 'avdmanager.bat') create avd --name $avd --package $image --device pixel_5
        if ($LASTEXITCODE -ne 0 -or !(Test-Path $ini)) { throw 'Falha ao criar o AVD.' }
    }
    Assert-Acceleration
}

function Find-Device {
    if (!(Test-Path $connection) -or !(Test-Path $adb)) { return }
    $record = Get-Content $connection -Raw | ConvertFrom-Json
    if ($record.Serial -notmatch '^emulator-\d+$') { return }
    $name = & $adb -s $record.Serial emu avd name 2>$null
    if ($LASTEXITCODE -eq 0 -and $name -contains $avd) { $record.Serial }
}

function Invoke-Adb([string[]]$Arguments) {
    if (!$serial) { $script:serial = Find-Device }
    if (!$serial) { throw 'O AVD deste projeto não foi encontrado por ADB.' }
    Invoke-Checked $adb (@('-s',$serial) + $Arguments)
}

function Wait-Boot {
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        $script:serial = Find-Device
        if ($serial) {
            $boot = & $adb -s $serial shell getprop sys.boot_completed 2>$null
            if ($boot -eq '1') {
                $api = Invoke-Adb @('shell','getprop','ro.build.version.sdk')
                $abi = Invoke-Adb @('shell','getprop','ro.product.cpu.abi')
                $activity = Invoke-Adb @('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.HOME')
                if ($api -ne '31' -or $abi -ne 'x86_64') { throw "Imagem inesperada: API $api, ABI $abi." }
                if ($activity -match '/\S+') { return }
            }
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Android não concluiu a inicialização em cinco minutos. Execute Diagnose.'
}

function Get-ListeningPorts {
    [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port
}

function Start-Android {
    if (Find-Device) { Wait-Boot; return }
    if (!(Test-Path $ini)) { throw 'Execute Setup para criar o AVD.' }
    if (Test-Path $connection) {
        $prior = Get-Content $connection -Raw | ConvertFrom-Json
        $process = Get-Process -Id $prior.Pid -ErrorAction SilentlyContinue
        if ($process -and $process.StartTime.ToUniversalTime().Ticks -eq $prior.StartTicks) { Wait-Boot; return }
    }
    Assert-Acceleration | Out-Host
    $resources = Get-Resources
    $used = Get-ListeningPorts
    $port = 5554..5584 | Where-Object { $_ % 2 -eq 0 -and $_ -notin $used -and ($_ + 1) -notin $used } | Select-Object -First 1
    if (!$port) { throw 'Não há um par de portas livre para este AVD.' }
    $launch = @{
        FilePath = $emulator
        ArgumentList = @('-avd',$avd,'-port',$port,'-accel','on','-cores',$resources.Cores,
            '-memory',$resources.RamMB,'-gpu',$resources.Gpu,'-no-snapshot-load','-no-snapshot-save',
            '-data',('"' + (Join-Path $env:ANDROID_AVD_HOME "$avd.avd\userdata-qemu.img") + '"'))
        PassThru = $true
        RedirectStandardOutput = Join-Path $state 'emulator.stdout.log'
        RedirectStandardError = Join-Path $state 'emulator.stderr.log'
    }
    $process = Start-Process @launch
    if ($process.HasExited) { throw 'O processo do emulador terminou. Execute Diagnose.' }
    @{Serial="emulator-$port"; Pid=$process.Id; StartTicks=$process.StartTime.ToUniversalTime().Ticks} |
        ConvertTo-Json | Set-Content $connection
    Wait-Boot
}

function Stop-Android {
    $script:serial = Find-Device
    if (!$serial) { throw 'O AVD está desligado ou ainda não responde ao ADB.' }
    Invoke-Adb @('shell','sync')
    Invoke-Adb @('emu','kill')
    $port = [int]($serial -replace 'emulator-')
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while ($port -in (Get-ListeningPorts) -or ($port + 1) -in (Get-ListeningPorts)) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'O console do emulador ainda está ativo.' }
        Start-Sleep -Milliseconds 500
    }
    $script:serial = $null
}

function Invoke-Snapshot([string[]]$Arguments) {
    $result = Invoke-Adb (@('emu','avd','snapshot') + $Arguments)
    if ($result -match '^KO' -or $result -notcontains 'OK') { throw "Falha de snapshot. $($result -join ' ')" }
    $result
}

$lockId = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(
    [IO.Path]::GetFullPath($state).ToUpperInvariant()
)))
$mutex = [Threading.Mutex]::new($false,"Android12Local-$lockId")
$locked = $false
try {
    if ($Action -notin @('Inspect','Diagnose','Logs','Resources','Virtualization')) {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw 'Já existe outra operação em andamento neste AVD.' }
    }
    switch ($Action) {
        Inspect { Get-HostInfo }
        Setup { Invoke-Setup }
        Virtualization { Get-HostInfo; Assert-Acceleration }
        EnableWHPX {
            & "$env:SystemRoot\System32\dism.exe" /Online /Enable-Feature /FeatureName:HypervisorPlatform /All /NoRestart
            if ($LASTEXITCODE -notin @(0,3010)) { throw 'A ativação de WHPX exige PowerShell elevado.' }
            'Reinicie o Windows se solicitado pelo DISM.'
        }
        Start { Start-Android; "Android pronto em $serial." }
        Stop { Stop-Android }
        Restart { Stop-Android; Start-Android }
        Install {
            if (!$Apk -or [IO.Path]::GetExtension($Apk) -ne '.apk') { throw 'Informe -Apk com um arquivo APK.' }
            $file = Get-Item -LiteralPath $Apk
            if ($file.PSIsContainer) { throw 'Selecione um arquivo APK.' }
            Invoke-Adb @('install','-r',$file.FullName)
        }
        Uninstall {
            if ($Package -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$') { throw 'Informe um identificador Android válido.' }
            $packages = Invoke-Adb @('shell','pm','list','packages','-3')
            if ($packages -notcontains "package:$Package") { throw 'O pacote não consta entre os apps de usuário.' }
            Invoke-Adb @('uninstall',$Package)
        }
        Resources {
            Get-Resources
            if (Find-Device) {
                $record = Get-Content $connection -Raw | ConvertFrom-Json
                Get-Process -Id $record.Pid -ErrorAction SilentlyContinue |
                    Select-Object Id,ProcessName,CPU,WorkingSet64,PrivateMemorySize64
                Invoke-Adb @('shell','dumpsys','cpuinfo')
                Invoke-Adb @('shell','cat','/proc/meminfo')
            }
        }
        Logs { Invoke-Adb @('logcat','-d','-t','300') }
        Diagnose {
            Get-HostInfo
            if (Test-Path $emulator) { try { Assert-Acceleration } catch { Write-Warning $_ } }
            if (Test-Path $adb) { Invoke-Checked $adb @('devices','-l') }
            foreach ($log in 'emulator.stdout.log','emulator.stderr.log') {
                $path = Join-Path $state $log
                if (Test-Path $path) { Get-Content $path -Tail 80 }
            }
        }
        Configure {
            $current = Get-Resources
            if ($Cores) { $current.Cores = $Cores }
            if ($RamMB) { $current.RamMB = $RamMB }
            if ($Gpu) { $current.Gpu = $Gpu }
            $hostInfo = Get-HostInfo
            if ($current.Cores -gt $hostInfo.LogicalCores -or $current.RamMB -ge $hostInfo.MemoryMB) { throw 'A configuração excede os recursos do host.' }
            New-Item -ItemType Directory -Force $state | Out-Null
            $current | ConvertTo-Json | Set-Content $config
            $current
        }
        Backup {
            $list = Invoke-Snapshot @('list')
            if (($list -join [Environment]::NewLine) -match "(?m)(?:^|\s)$([regex]::Escape($Snapshot))(?:\s|$)") { throw 'Já existe um snapshot com esse nome.' }
            Invoke-Adb @('shell','sync')
            Invoke-Snapshot @('save',$Snapshot)
        }
        Restore {
            if (!$ConfirmRestore) { throw 'O snapshot substitui o estado atual. Confirme com -ConfirmRestore.' }
            Invoke-Snapshot @('load',$Snapshot)
            Wait-Boot
        }
        Push {
            if (!$LocalPath -or !$DevicePath) { throw 'Informe -LocalPath e -DevicePath.' }
            Invoke-Adb @('push',(Get-Item -LiteralPath $LocalPath).FullName,$DevicePath)
        }
        Pull {
            if (!$LocalPath -or !$DevicePath) { throw 'Informe -LocalPath e -DevicePath.' }
            Invoke-Adb @('pull',$DevicePath,$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LocalPath))
        }
        Test { . (Join-Path $PSScriptRoot 'Test-Android.ps1') }
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    $env:ANDROID_HOME = $oldHome
    $env:ANDROID_SDK_ROOT = $oldSdk
    $env:ANDROID_AVD_HOME = $oldAvd
    $env:JAVA_HOME = $oldJava
}
