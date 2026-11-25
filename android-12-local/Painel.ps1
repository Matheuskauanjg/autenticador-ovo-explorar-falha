#requires -Version 7.2
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$controller = Join-Path $PSScriptRoot 'Android.ps1'
$form = [Windows.Forms.Form]@{
    Text='Android 12 Local'; Width=790; Height=550; StartPosition='CenterScreen'
    MinimumSize=[Drawing.Size]::new(660,400)
}
$bar = [Windows.Forms.FlowLayoutPanel]@{Dock='Top'; Height=124; Padding=[Windows.Forms.Padding]::new(10); AutoScroll=$true}
$output = [Windows.Forms.TextBox]@{
    Multiline=$true; ReadOnly=$true; ScrollBars='Both'; Dock='Fill'; WordWrap=$false
    Font=[Drawing.Font]::new('Consolas',10)
}
$form.Controls.Add($output)
$form.Controls.Add($bar)
$script:job = $null
$timer = [Windows.Forms.Timer]@{Interval=350}
function Run-Action([string]$Command,[hashtable]$Parameters=@{}) {
    if ($script:job) { return }
    $bar.Enabled = $false
    $output.Text = "Executando $Command..."
    $script:job = Start-Job -ArgumentList $controller,$Command,$Parameters -ScriptBlock {
        param($scriptFile,$command,$parameters)
        & $scriptFile $command @parameters *>&1 | Out-String -Width 125
    }
    $timer.Start()
}
$timer.Add_Tick({
    if ($script:job.State -in 'Running','NotStarted') { return }
    $timer.Stop()
    $output.Text = (Receive-Job $script:job *>&1 | Out-String -Width 125).Trim()
    if (!$output.Text) { $output.Text = "Operação $($script:job.State)." }
    Remove-Job $script:job
    $script:job = $null
    $bar.Enabled = $true
})
function Add-Button([string]$Label,[scriptblock]$Handler) {
    $button = [Windows.Forms.Button]@{Text=$Label; AutoSize=$true; Height=32}
    $button.Add_Click($Handler)
    $bar.Controls.Add($button)
}
Add-Button 'Iniciar' { Run-Action Start }
Add-Button 'Parar' { Run-Action Stop }
Add-Button 'Reiniciar' { Run-Action Restart }
Add-Button 'Instalar APK' {
    $dialog = [Windows.Forms.OpenFileDialog]@{Filter='Android APK (*.apk)|*.apk'; CheckFileExists=$true}
    try {
        if ($dialog.ShowDialog($form) -eq 'OK') { Run-Action Install @{Apk=$dialog.FileName} }
    } finally { $dialog.Dispose() }
}
Add-Button 'Logs' { Run-Action Logs }
Add-Button 'Diagnóstico' { Run-Action Diagnose }
Add-Button 'Consumo' { Run-Action Resources }

$cores = [Windows.Forms.NumericUpDown]@{Minimum=0; Maximum=16; Width=60; AccessibleName='Núcleos'}
$ram = [Windows.Forms.NumericUpDown]@{Minimum=0; Maximum=8192; Increment=256; Width=75; AccessibleName='RAM em MiB'}
$gpu = [Windows.Forms.ComboBox]@{DropDownStyle='DropDownList'; Width=90; AccessibleName='Modo de GPU'}
[void]$gpu.Items.AddRange(@('Atual','auto','host','software'))
$gpu.SelectedIndex = 0
$bar.SetFlowBreak($bar.Controls[$bar.Controls.Count-1],$true)
$bar.Controls.Add([Windows.Forms.Label]@{Text='Núcleos / RAM MiB (0 mantém)'; AutoSize=$true; Padding=[Windows.Forms.Padding]::new(0,6,0,0)})
$bar.Controls.Add($cores)
$bar.Controls.Add($ram)
$bar.Controls.Add($gpu)
Add-Button 'Salvar recursos' {
    $parameters = @{}
    if ($cores.Value) { $parameters.Cores = [int]$cores.Value }
    if ($ram.Value) { $parameters.RamMB = [int]$ram.Value }
    if ($gpu.SelectedIndex -gt 0) { $parameters.Gpu = $gpu.SelectedItem }
    Run-Action Configure $parameters
}
$form.Add_FormClosing({ param($sender,$eventArgs) if ($script:job) { $eventArgs.Cancel = $true } })
try { [void]$form.ShowDialog() }
finally { $timer.Dispose(); $form.Dispose() }
