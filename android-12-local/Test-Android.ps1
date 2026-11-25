$timer = [Diagnostics.Stopwatch]::StartNew()
Start-Android
$bootTime = $timer.Elapsed.TotalSeconds
$build = Invoke-Adb @('shell','getprop','ro.build.type')
$selinux = Invoke-Adb @('shell','getenforce')
$uid = Invoke-Adb @('shell','id','-u')
if ($build -ne 'user' -or $selinux -ne 'Enforcing' -or $uid -ne '2000') {
    throw "Estado de segurança inesperado: build=$build SELinux=$selinux UID=$uid."
}

$token = [guid]::NewGuid().ToString('N')
$marker = "/sdcard/Download/android12local-$token.txt"
$screenshot = "/sdcard/Download/android12local-$token.png"
$hostMarker = Join-Path $state "test-$token.txt"
$hostScreenshot = Join-Path $state "screen-$token.png"
if ($Apk -and $Package -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$') {
    throw 'Use -Package com o identificador do APK de teste.'
}
try {
    if ($Apk) {
        $file = Get-Item -LiteralPath $Apk
        if ($file.PSIsContainer -or $file.Extension -ne '.apk') { throw 'Forneça um APK de teste.' }
        Invoke-Adb @('install','-r',$file.FullName)
        if ((Invoke-Adb @('shell','pm','path',$Package)) -notmatch '^package:') { throw 'O pacote esperado não foi instalado.' }
    }
    Set-Content -LiteralPath $hostMarker -Value $token -NoNewline -Encoding ascii
    Invoke-Adb @('push',$hostMarker,$marker)
    $timer.Restart()
    Stop-Android
    Start-Android
    $restartTime = $timer.Elapsed.TotalSeconds
    if ((Invoke-Adb @('shell','cat',$marker)) -ne $token) { throw 'Falha de persistência no armazenamento compartilhado.' }
    if ($Apk -and (Invoke-Adb @('shell','pm','path',$Package)) -notmatch '^package:') { throw 'APK ausente após reiniciar.' }
    Invoke-Adb @('shell','am','start','-a','android.intent.action.MAIN','-c','android.intent.category.HOME')
    Start-Sleep -Seconds 2
    Invoke-Adb @('shell','screencap','-p',$screenshot)
    Invoke-Adb @('pull',$screenshot,$hostScreenshot)
    $png = [IO.File]::ReadAllBytes($hostScreenshot)
    if ($png.Length -lt 1024 -or [BitConverter]::ToString($png,0,8) -ne '89-50-4E-47-0D-0A-1A-0A') {
        throw 'Captura de tela inválida.'
    }
    [pscustomobject]@{
        InicializacaoOuEsperaSeg = [Math]::Round($bootTime,2)
        CicloDesligarEIniciarSeg = [Math]::Round($restartTime,2)
        ABI = 'x86_64'
        API = 31
        Build = $build
        SELinux = $selinux
        Captura = $hostScreenshot
        PersistenciaDeArquivo = $true
        PersistenciaDeAPK = if ($Apk) { $true } else { 'Sem APK de teste fornecido' }
    }
} finally {
    if (Find-Device) { Invoke-Adb @('shell','rm','-f',$marker,$screenshot) }
    if (Test-Path -LiteralPath $hostMarker) { Remove-Item -LiteralPath $hostMarker }
}
