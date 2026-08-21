# Copilot CLI statusline -- reads the JSON Copilot sends on stdin and prints
# a one-line context-window readout for the footer. Prints nothing on
# garbage input so a mangled pipe never breaks the UI. Windows port of
# statusline.sh -- native PowerShell JSON handling, no python3 dependency.

function Format-TokenCount([long]$n) {
  if ($n -ge 1000000) { return "{0:N2}M" -f ($n / 1e6) }
  if ($n -ge 1000)    { return "{0:N1}k" -f ($n / 1e3) }
  return "$n"
}

try {
  $input_ = [Console]::In.ReadToEnd()
  $d = $input_ | ConvertFrom-Json -ErrorAction Stop
} catch {
  exit 0
}

$cw = $d.context_window
if (-not $cw) { exit 0 }
$used = $cw.used_percentage
if ($null -eq $used) { exit 0 }
$inp = if ($cw.total_input_tokens) { $cw.total_input_tokens } else { 0 }
$out = if ($cw.total_output_tokens) { $cw.total_output_tokens } else { 0 }

Write-Host ("ctx {0:N0}% · {1}/{2}" -f $used, (Format-TokenCount $inp), (Format-TokenCount $out))
