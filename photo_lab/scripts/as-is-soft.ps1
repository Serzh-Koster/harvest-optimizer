$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$processor = Join-Path $scriptDir "process-photo.ps1"

& $processor -Preset "as_is_soft"
