param(
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateSet('test','demo','replay','import','smoke','visual','closeout','inspector-headless','fronts','front-demo','decisions','decision-demo','needs','need-demo','arbitration','integrated','observer')][string]$Mode = 'test',
    [string]$Package = 'res://artifacts/run_demo',
    [int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if ($Mode -eq 'front-demo' -and -not $PSBoundParameters.ContainsKey('Package')) { $Package = 'res://artifacts/run_step103' }
if ($Mode -eq 'decision-demo' -and -not $PSBoundParameters.ContainsKey('Package')) { $Package = 'res://artifacts/run_step104' }
if ($Mode -eq 'need-demo' -and -not $PSBoundParameters.ContainsKey('Package')) { $Package = 'res://artifacts/run_step105' }
if (-not $GodotPath) {
    $localEngine = Join-Path (Split-Path (Split-Path $projectRoot -Parent) -Parent) '.tools/godot-4.7.2/godot.exe'
    if (Test-Path -LiteralPath $localEngine) { $GodotPath = $localEngine }
    elseif (Get-Command godot -ErrorAction SilentlyContinue) { $GodotPath = (Get-Command godot).Source }
    else { $GodotPath = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' }
}
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = $GodotPath
$start.WorkingDirectory = $projectRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$logDirectory = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$dataDirectory = Join-Path $logDirectory 'windows_data'
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
$start.Environment['APPDATA'] = $dataDirectory
$start.Environment['LOCALAPPDATA'] = $dataDirectory
$engineArguments = @('--headless','--path',$projectRoot,'--log-file',(Join-Path $logDirectory ($Mode + '.godot.log')))
if ($Mode -eq 'visual') { $engineArguments = @('--audio-driver','Dummy','--path',$projectRoot,'--log-file',(Join-Path $logDirectory 'visual.godot.log')) }
switch ($Mode) {
    'import' { $engineArguments += @('--editor','--import') }
    'smoke' { $engineArguments += @('--quit-after','3') }
    'test' { $engineArguments += @('--script','res://tests/acceptance.gd') }
    'closeout' { $engineArguments += @('--script','res://tests/closeout_regression.gd') }
    'observer' { $engineArguments += @('--script','res://tests/player_observation_regression.gd') }
    'integrated' { $engineArguments += @('--script','res://tests/integrated_regression.gd') }
    'arbitration' { $engineArguments += @('--script','res://tests/arbitration_regression.gd') }
    'needs' { $engineArguments += @('--script','res://tests/resource_resolution_regression.gd') }
    'decisions' { $engineArguments += @('--script','res://tests/decision_regression.gd') }
    'fronts' { $engineArguments += @('--script','res://tests/front_regression.gd') }
    'inspector-headless' { $engineArguments += @('--script','res://tests/inspector_headless.gd') }
    'visual' { $engineArguments += @('--script','res://tests/inspector_smoke.gd') }
    'demo' { $engineArguments += @('--script','res://tools/cli.gd','--','demo',$Package) }
    'need-demo' { $engineArguments += @('--script','res://tools/cli.gd','--','need-demo',$Package) }
    'decision-demo' { $engineArguments += @('--script','res://tools/cli.gd','--','decision-demo',$Package) }
    'front-demo' { $engineArguments += @('--script','res://tools/cli.gd','--','front-demo',$Package) }
    'replay' { $engineArguments += @('--script','res://tools/cli.gd','--','replay',$Package) }
}
foreach ($argument in $engineArguments) { $start.ArgumentList.Add($argument) }
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $start
try {
    if (-not $process.Start()) { throw 'Godot failed to launch' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        throw "Godot timed out after $TimeoutSeconds seconds"
    }
    $output = $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    Write-Output $output
    if ($errors) { Write-Output $errors }
    if ($process.ExitCode -ne 0 -or ($output + $errors) -match '(SCRIPT ERROR:|ERROR:|FATAL:|WARNING:.*leaked)') {
        throw "Godot validation failed (exit $($process.ExitCode))"
    }
} finally { $process.Dispose() }
