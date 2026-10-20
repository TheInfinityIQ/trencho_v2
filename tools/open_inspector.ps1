param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $GodotPath) {
    if (Get-Command godot -ErrorAction SilentlyContinue) { $GodotPath = (Get-Command godot).Source }
    else { $GodotPath = Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' }
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Pass -GodotPath with the Godot 4.7.2 executable location.' }
$logRoot = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = $GodotPath
$start.WorkingDirectory = $projectRoot
$start.UseShellExecute = $false
# Interactive launch requested by the user running this helper; no editor --wid embedding.
foreach ($argument in @('--path',$projectRoot,'--max-fps','30','--log-file',(Join-Path $logRoot 'standalone.godot.log'),'res://debug/inspector.tscn')) {
    $start.ArgumentList.Add($argument)
}
$process = [System.Diagnostics.Process]::Start($start)
Write-Output "Standalone inspector process $($process.Id); simulation starts only when Run demonstration is clicked."
$process.Dispose()
