$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$processor = Join-Path $scriptDir "process-photo.ps1"

& $processor -Preset "web_1600_soft"
