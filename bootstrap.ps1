<#
.SYNOPSIS
  bootstrap.ps1 -- idempotent Windows setup of the opencode + Claude Code
  token optimization stack. Native PowerShell port of bootstrap.sh.

  Clone dojo wherever you like -- ~\dojo, or alongside your other repos --
  this script finds its own location via $PSScriptRoot, so either works:

    git clone https://github.com/Cyb3rRon1n/dojo.git $HOME\dojo
    & $HOME\dojo\bootstrap.ps1

  To update later: git -C $HOME\dojo pull; & $HOME\dojo\bootstrap.ps1

  Safe to re-run: existing files are backed up to .bak before replacement,
  and every step is a no-op when already in place.

  Known platform gaps vs. bootstrap.sh (not bugs -- real Windows differences):
   - The `dojo` CLI itself (dojo update/status/doctor/tokens) is a bash
     script. This wires a `dojo.cmd` shim through Git for Windows' bash.exe
     if found; without Git for Windows, the dojo command is unavailable
     (everything else still works).
   - Symlinks need either Developer Mode (Settings > For developers) or an
     elevated shell. Falls back to a copy + warning when neither is set up
     -- copies won't pick up a `dojo update` automatically; re-run this
     script after updating dojo to refresh them.
#>

$LocalBin    = Join-Path $HOME ".local\bin"
$ConfigHome  = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
$ClaudeHome  = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$DojoDir     = $PSScriptRoot

New-Item -ItemType Directory -Path $LocalBin -Force | Out-Null
if ($env:PATH -notlike "*$LocalBin*") { $env:PATH = "$LocalBin;$env:PATH" }

function Warn($msg) { Write-Host "[dojo][warn] $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Progress: "[dojo] (n/N) step description... ok/skip/FAILED" -- one line per
# step, matching bootstrap.sh's format.
# ---------------------------------------------------------------------------
$TotalSteps = 24
$script:StepN = 0
function Step($desc) {
  $script:StepN++
  Write-Host -NoNewline ("[dojo] ({0}/{1}) {2,-38}" -f $script:StepN, $TotalSteps, "$desc...")
}
function RunStep($desc, [scriptblock]$Action) {
  Step $desc
  try {
    $out = & $Action 2>&1 | Out-String
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE`n$out" }
    Write-Host "ok"
    return $true
  } catch {
    Write-Host "FAILED"
    ($_.Exception.Message -split "`n" | Select-Object -Last 20) | ForEach-Object {
      Write-Host $_ -ForegroundColor Red
    }
    return $false
  }
}
function SkipStep($desc, [string]$Reason = "already present") {
  Step $desc
  Write-Host "skip ($Reason)"
}

# ---------------------------------------------------------------------------
# Link-File <src> <dst> -- symlink, backing up any existing regular file.
# Falls back to a copy if symlink creation isn't permitted (no Developer
# Mode, not elevated).
# ---------------------------------------------------------------------------
function Link-File($Src, $Dst) {
  $dstDir = Split-Path $Dst -Parent
  if ($dstDir -and -not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
  if (Test-Path $Dst) {
    if (-not (Get-Item $Dst -Force).LinkType) {
      Move-Item $Dst "$Dst.bak" -Force
      Warn "backed up $Dst -> $Dst.bak"
    } else {
      Remove-Item $Dst -Force
    }
  }
  try {
    New-Item -ItemType SymbolicLink -Path $Dst -Target $Src -Force -ErrorAction Stop | Out-Null
  } catch {
    # -Recurse only matters for a directory source (e.g. the task-observer
    # skill folder below) - a no-op flag for the plain-file case every
    # other Link-File call here still uses.
    if (Test-Path $Src -PathType Container) {
      Copy-Item $Src $Dst -Recurse -Force
    } else {
      Copy-Item $Src $Dst -Force
    }
    Warn "symlink failed for $Dst (enable Developer Mode: Settings > Update & Security > For developers, or run as Administrator) -- copied instead; re-run bootstrap.ps1 after a dojo update to refresh"
  }
}

# ---------------------------------------------------------------------------
# 0. Tool binaries -- warn only, same as bootstrap.sh. Not auto-installed;
#    use install.ps1 or each tool's own installer.
# ---------------------------------------------------------------------------
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) { Warn "opencode not found -- see https://opencode.ai" }
if (-not (Get-Command claude   -ErrorAction SilentlyContinue)) { Warn "claude not found -- npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code" }
if (-not (Get-Command copilot  -ErrorAction SilentlyContinue)) { Warn "copilot not found -- npm install -g @github/copilot" }
if (-not (Get-Command aider    -ErrorAction SilentlyContinue)) { Warn 'aider not found -- powershell -ExecutionPolicy ByPass -c "irm https://aider.chat/install.ps1 | iex"' }
if (-not (Get-Command codex    -ErrorAction SilentlyContinue)) { Warn "codex not found -- npm install -g @openai/codex" }

if (Get-Command rtk -ErrorAction SilentlyContinue) {
  SkipStep "rtk binary"
} else {
  if (-not (RunStep "rtk binary" {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/rtk-ai/rtk/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -eq "rtk-x86_64-pc-windows-msvc.zip" }
    if (-not $asset) { throw "no Windows release asset found for $($release.tag_name)" }
    $checksumAsset = $release.assets | Where-Object { $_.name -eq "checksums.txt" }

    $tmpDir = Join-Path $env:TEMP "dojo-rtk-install"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpZip = Join-Path $tmpDir $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing

    if ($checksumAsset) {
      $tmpChecksums = Join-Path $tmpDir "checksums.txt"
      Invoke-WebRequest -Uri $checksumAsset.browser_download_url -OutFile $tmpChecksums -UseBasicParsing
      $expectedLine = Get-Content $tmpChecksums | Where-Object { $_ -match [regex]::Escape($asset.name) } | Select-Object -First 1
      if ($expectedLine) {
        $expected = ($expectedLine -split '\s+')[0].ToLower()
        $actual = (Get-FileHash $tmpZip -Algorithm SHA256).Hash.ToLower()
        if ($expected -ne $actual) { throw "checksum mismatch for $($asset.name)" }
      }
    }

    $extractDir = Join-Path $tmpDir "extracted"
    Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
    $exe = Get-ChildItem -Path $extractDir -Filter "rtk.exe" -Recurse | Select-Object -First 1
    if (-not $exe) { throw "rtk.exe not found in $($asset.name)" }
    Copy-Item $exe.FullName (Join-Path $LocalBin "rtk.exe") -Force
    # No Linux/Mac-style /usr/local/bin mirror here: on Windows the User PATH
    # entry below (section 0b) persists for every process launched after this,
    # and hook subprocesses inherit their parent's environment instead of
    # re-reading profile files -- the failure mode that mirror fixes doesn't exist.
    Remove-Item $tmpDir -Recurse -Force
  })) { Warn "rtk install failed -- see https://github.com/rtk-ai/rtk/releases" }
}

if (Get-Command graphify -ErrorAction SilentlyContinue) {
  SkipStep "graphify binary"
} elseif (Get-Command uv -ErrorAction SilentlyContinue) {
  if (-not (RunStep "graphify binary" { uv tool install graphifyy })) { Warn "graphify install failed" }
} else {
  SkipStep "graphify binary" "uv missing -- see https://docs.astral.sh/uv"
}

# Serena: symbol-level semantic code tools (LSP-backed) served over MCP to
# Claude Code and opencode below. Idempotent: re-run reports "already
# installed" and exits 0.
if (Get-Command serena -ErrorAction SilentlyContinue) {
  SkipStep "serena binary"
} elseif (Get-Command uv -ErrorAction SilentlyContinue) {
  # `uv tool install -p 3.13` fails outright if 3.13 isn't already a managed
  # interpreter and python-downloads is set to "manual" (uv won't fetch it
  # implicitly then) -- fetch it explicitly first; a no-op if already present.
  if (-not (RunStep "serena binary" {
    uv python install 3.13
    if ($LASTEXITCODE -ne 0) { throw "uv python install 3.13 failed" }
    uv tool install -p 3.13 serena-agent
  })) { Warn "serena install failed" }
} else {
  SkipStep "serena binary" "uv missing"
}

# ---------------------------------------------------------------------------
# 0a. dojo command (update/status/install/doctor/tokens) -- the CLI itself
#     is a bash script. Shim it through Git for Windows' bash.exe if found;

# ---------------------------------------------------------------------------
Step "dojo command (update/status/install/doctor)"
$GitBashCandidates = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)
$gitBashCmd = Get-Command bash.exe -ErrorAction SilentlyContinue
if ($gitBashCmd) { $GitBashCandidates += $gitBashCmd.Source }
$GitBash = $GitBashCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

New-Item -ItemType Directory -Path $LocalBin -Force | Out-Null
if ($GitBash) {
  Set-Content -Path (Join-Path $LocalBin "dojo.cmd") -Encoding ASCII -Value @(
    "@echo off"
    "`"$GitBash`" `"$DojoDir\dojo`" %*"
  )
  Write-Host "ok (via git-bash: $GitBash)"
} else {
  Write-Host "skip (no git-bash found)"
  Warn "install Git for Windows (https://git-scm.com/download/win) to get the dojo CLI -- everything else in this script still works without it"
}

# ---------------------------------------------------------------------------
# 0a2. python3 shim -- dojo (the bash CLI, via the git-bash shim above)
#      hardcodes `python3`, but Windows Python installers only ever provide
#      python.exe, never a python3 alias. Get-Command alone can't detect
#      this either way -- Windows ships fake "app execution alias" stubs
#      for both names that report as present even with nothing real
#      installed (confirmed live: a real python.exe on PATH does NOT mean
#      python3 does too, they're two separate stubs).
# ---------------------------------------------------------------------------
Step "python3 shim (for the dojo CLI)"
function Test-RealPython($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { return $false }
  $out = (& $cmd --version 2>&1 | Out-String)
  return ($LASTEXITCODE -eq 0) -and ($out -match "Python \d")
}
if (Test-RealPython "python3") {
  Write-Host "skip (python3 already resolves)"
} elseif (Test-RealPython "python") {
  # git-bash (MSYS) does its own PATH resolution, not Windows'
  # PATHEXT-based one -- it auto-appends .exe to a bare name but does NOT
  # look for a .cmd/.bat shim the way cmd.exe/PowerShell do (confirmed
  # live: a python3.cmd shim was invisible to `python3` calls from inside
  # bash even though it worked fine called directly from PowerShell). A
  # real python3.exe is required; a hardlink gets one for free, same
  # bytes on disk, no symlink/Developer Mode permission issues since
  # hardlinks don't need either on NTFS.
  $pythonExe = (Get-Command python).Source
  $python3Path = Join-Path $LocalBin "python3.exe"
  if (Test-Path $python3Path) { Remove-Item $python3Path -Force }
  try {
    New-Item -ItemType HardLink -Path $python3Path -Target $pythonExe -ErrorAction Stop | Out-Null
    Write-Host "ok (hardlinked to $pythonExe)"
  } catch {
    Copy-Item $pythonExe $python3Path -Force
    Write-Host "ok (copied from $pythonExe -- different volume, hardlink unavailable)"
  }
} else {
  Write-Host "skip (no real python found)"
  Warn "dojo tokens needs python -- install via install.ps1, or: winget install Python.Python.3.13"
}

# ---------------------------------------------------------------------------
# 0b. PATH persistence + legacy prompt-hook removal. Windows equivalent of
#     bootstrap.sh's .bashrc/.zshrc block: a persistent User PATH entry (so
#     any launched process finds these bins, not just PowerShell). Also
#     strips the retired token-usage prompt block older versions wrote to
#     $PROFILE.
# ---------------------------------------------------------------------------
Step "PATH persistence"
$PathEntries = @("$HOME\.local\bin", "$HOME\.opencode\bin", "$HOME\.npm-global\bin")
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($null -eq $UserPath) { $UserPath = "" }
$missing = $PathEntries | Where-Object { $UserPath -notlike "*$_*" }
if ($missing) {
  [Environment]::SetEnvironmentVariable("PATH", (($missing -join ";") + ";" + $UserPath), "User")
  foreach ($p in $missing) { if ($env:PATH -notlike "*$p*") { $env:PATH = "$p;$env:PATH" } }
}

$ProfileMarker = "# >>> dojo >>>"
$ProfileTail   = "# <<< dojo <<<"

if (Test-Path $PROFILE) {
  $existingProfile = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
  if ($existingProfile -and $existingProfile.Contains($ProfileMarker)) {
    $pattern = "(?s)" + [regex]::Escape($ProfileMarker) + ".*?" + [regex]::Escape($ProfileTail)
    Set-Content -Path $PROFILE -Value ([regex]::Replace($existingProfile, $pattern, "").Trim() + "`n")
  }
}
Write-Host "ok"

# ---------------------------------------------------------------------------
# 1. opencode global config + plugin dependencies
# ---------------------------------------------------------------------------
Step "opencode global config"
$OConf = Join-Path $ConfigHome "opencode"
New-Item -ItemType Directory -Path $OConf -Force | Out-Null
Link-File (Join-Path $DojoDir "opencode\opencode.jsonc") (Join-Path $OConf "opencode.jsonc")
Copy-Item (Join-Path $DojoDir "opencode\package.json") (Join-Path $OConf "package.json") -Force
Copy-Item (Join-Path $DojoDir "opencode\package-lock.json") (Join-Path $OConf "package-lock.json") -Force
Write-Host "ok"

if (Get-Command npm -ErrorAction SilentlyContinue) {
  if (-not (RunStep "opencode plugin dependencies" { Push-Location $OConf; try { npm install --legacy-peer-deps } finally { Pop-Location } })) {
    Warn "opencode plugin install failed"
  }
} else {
  SkipStep "opencode plugin dependencies" "npm missing -- opencode installs them at first launch"
  New-Item -ItemType Directory -Path (Join-Path $OConf "plugins") -Force | Out-Null
  Link-File (Join-Path $DojoDir "opencode\plugins\token-gauge.js") (Join-Path $OConf "plugins\token-gauge.js")
}

# ---------------------------------------------------------------------------
# 2. Claude Code user-level instructions
# ---------------------------------------------------------------------------
Step "Claude Code user config"
New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null
Link-File (Join-Path $DojoDir "claude\CLAUDE.md") (Join-Path $ClaudeHome "CLAUDE.md")
Link-File (Join-Path $DojoDir "claude\RTK.md") (Join-Path $ClaudeHome "RTK.md")
# task-observer has no plugin-marketplace manifest upstream, so it's
# vendored under claude\skills\ (see that dir's UPSTREAM.md) and linked
# directly, same as bootstrap.sh.
Link-File (Join-Path $DojoDir "claude\skills\task-observer") (Join-Path $ClaudeHome "skills\task-observer")
Write-Host "ok"

# ---------------------------------------------------------------------------
# 3. Claude Code plugins (marketplace + install are idempotent)
# ---------------------------------------------------------------------------
$GithubMcpNew = $false
if (Get-Command claude -ErrorAction SilentlyContinue) {
  if (-not (RunStep "Claude Code plugin marketplaces" {
    claude plugin marketplace add alexgreensh/token-optimizer
    claude plugin marketplace add DietrichGebert/ponytail
    claude plugin marketplace add obra/superpowers
    # Anthropic's official marketplace ships preconfigured with recent CLI
    # versions; this is a no-op there and covers older installs.
    claude plugin marketplace add anthropics/claude-plugins-official
  })) { Warn "plugin marketplace registration failed" }

  # Same reasoning as bootstrap.sh: detect -y/--yes support instead of
  # assuming it, since an already-installed claude can predate the flag.
  $ClaudeInstallYesFlag = ""
  $helpOut = (& claude plugin install --help 2>&1 | Out-String)
  if ($helpOut -match '(^|[ ,])(-y|--yes)([ ,]|$)') { $ClaudeInstallYesFlag = "-y" }

  # superpowers@superpowers-dev -- the marketplace name comes from that
  # repo's own .claude-plugin/marketplace.json "name" field, not derived
  # from the obra/superpowers owner/repo string above, same as bootstrap.sh.
  if (-not (RunStep "Claude Code plugins" {
    if ($ClaudeInstallYesFlag) {
      claude plugin install token-optimizer@alexgreensh-token-optimizer $ClaudeInstallYesFlag
      claude plugin install ponytail@ponytail $ClaudeInstallYesFlag
      claude plugin install superpowers@superpowers-dev $ClaudeInstallYesFlag
      claude plugin install code-review@claude-plugins-official $ClaudeInstallYesFlag
      claude plugin install pr-review-toolkit@claude-plugins-official $ClaudeInstallYesFlag
    } else {
      claude plugin install token-optimizer@alexgreensh-token-optimizer
      claude plugin install ponytail@ponytail
      claude plugin install superpowers@superpowers-dev
      claude plugin install code-review@claude-plugins-official
      claude plugin install pr-review-toolkit@claude-plugins-official
    }
  })) { Warn "plugin install failed" }

  if (Get-Command rtk -ErrorAction SilentlyContinue) {
    if (-not (RunStep "RTK Claude Code hook" { rtk init -g --auto-patch })) { Warn "rtk hook install failed" }
  } else {
    SkipStep "RTK Claude Code hook" "rtk missing"
  }

  if (Get-Command graphify -ErrorAction SilentlyContinue) {
    if (-not (RunStep "graphify for Claude Code" { graphify install --platform claude })) { Warn "graphify claude install failed" }
  } else {
    SkipStep "graphify for Claude Code" "graphify missing"
  }

  # Shared MCP servers. Neither `serena setup` nor `claude mcp add` is
  # idempotent (both exit non-zero on "already exists"), so probe first.
  # github/context7 are remote HTTP servers -- no local deps. GitHub needs a
  # one-time interactive auth (/mcp in Claude Code) since its OAuth server
  # doesn't support dynamic client registration; flag a fresh registration
  # so the end-of-run verification can tell the user exactly that.
  claude mcp get github *>$null
  $GithubMcpNew = ($LASTEXITCODE -ne 0)

  claude mcp get serena *>$null
  if ($LASTEXITCODE -ne 0) {
    if (Get-Command serena -ErrorAction SilentlyContinue) {
      if (-not (RunStep "Serena MCP for Claude Code" { serena setup claude-code })) { Warn "serena claude setup failed" }
    } else {
      SkipStep "Serena MCP for Claude Code" "serena missing"
    }
  } else {
    SkipStep "Serena MCP for Claude Code" "(already registered)"
  }

  if (-not (RunStep "MCP servers for Claude Code (github, context7)" {
    claude mcp get github *>$null
    if ($LASTEXITCODE -ne 0) {
      claude mcp add --scope user --transport http github https://api.githubcopilot.com/mcp/ *>$null
      if ($LASTEXITCODE -ne 0) { throw "github mcp add failed" }
    }
    claude mcp get context7 *>$null
    if ($LASTEXITCODE -ne 0) {
      claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp/ *>$null
      if ($LASTEXITCODE -ne 0) { throw "context7 mcp add failed" }
    }
  })) { Warn "mcp server registration failed" }
} else {
  SkipStep "Claude Code plugin marketplaces" "claude missing"
  SkipStep "Claude Code plugins" "claude missing"
  SkipStep "RTK Claude Code hook" "claude missing"
  SkipStep "graphify for Claude Code" "claude missing"
  SkipStep "Serena MCP for Claude Code" "claude missing"
  SkipStep "MCP servers for Claude Code (github, context7)" "claude missing"
}

# ---------------------------------------------------------------------------
# 4. GitHub Copilot CLI -- RTK + graphify + statusline
# ---------------------------------------------------------------------------
if (Get-Command copilot -ErrorAction SilentlyContinue) {
  if (Get-Command rtk -ErrorAction SilentlyContinue) {
    if (-not (RunStep "RTK Copilot CLI hook" { rtk init -g --copilot })) { Warn "rtk copilot install failed" }
  } else {
    SkipStep "RTK Copilot CLI hook" "rtk missing"
  }
  if (Get-Command graphify -ErrorAction SilentlyContinue) {
    if (-not (RunStep "graphify for Copilot CLI" { graphify install --platform copilot })) { Warn "graphify copilot install failed" }
  } else {
    SkipStep "graphify for Copilot CLI" "graphify missing"
  }

  # Same statusline idea as bootstrap.sh, ported natively -- no python3
  # dependency needed, PowerShell's JSON cmdlets cover it directly.
  Step "Copilot CLI statusline"
  $CopilotHome = Join-Path $HOME ".copilot"
  New-Item -ItemType Directory -Path $CopilotHome -Force | Out-Null
  Link-File (Join-Path $DojoDir "copilot\statusline.ps1") (Join-Path $CopilotHome "statusline.ps1")
  $settingsPath = Join-Path $CopilotHome "settings.json"
  $settings = [PSCustomObject]@{}
  if (Test-Path $settingsPath) {
    try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { $settings = [PSCustomObject]@{} }
  }
  if (($settings.PSObject.Properties.Name -contains "statusLine") -and $settings.statusLine) {
    Write-Host "skip (statusLine already set)"
  } else {
    if ($settings.PSObject.Properties.Name -notcontains "feature_flags") {
      $settings | Add-Member -NotePropertyName feature_flags -NotePropertyValue ([PSCustomObject]@{ enabled = @() })
    }
    if ($settings.feature_flags.PSObject.Properties.Name -notcontains "enabled") {
      $settings.feature_flags | Add-Member -NotePropertyName enabled -NotePropertyValue @()
    }
    if ($settings.feature_flags.enabled -notcontains "STATUS_LINE") {
      $settings.feature_flags.enabled = @($settings.feature_flags.enabled) + "STATUS_LINE"
    }
    $cmd = "powershell -NoProfile -File `"$CopilotHome\statusline.ps1`""
    $statusLine = [PSCustomObject]@{ type = "command"; command = $cmd; padding = 1 }
    if ($settings.PSObject.Properties.Name -contains "statusLine") {
      $settings.statusLine = $statusLine
    } else {
      $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    Write-Host "ok"
  }
} else {
  SkipStep "RTK Copilot CLI hook" "copilot missing"
  SkipStep "graphify for Copilot CLI" "copilot missing"
  SkipStep "Copilot CLI statusline" "copilot missing"
}

# ---------------------------------------------------------------------------
# 5. OpenAI Codex CLI -- RTK + graphify + statusline
# ---------------------------------------------------------------------------
if (Get-Command codex -ErrorAction SilentlyContinue) {
  if (Get-Command rtk -ErrorAction SilentlyContinue) {
    if (-not (RunStep "RTK Codex CLI instructions" { rtk init -g --codex })) { Warn "rtk codex install failed" }
  } else {
    SkipStep "RTK Codex CLI instructions" "rtk missing"
  }
  if (Get-Command graphify -ErrorAction SilentlyContinue) {
    if (-not (RunStep "graphify for Codex CLI" { graphify install --platform codex })) { Warn "graphify codex install failed" }
  } else {
    SkipStep "graphify for Codex CLI" "graphify missing"
  }

  $codexConfig = Join-Path $HOME ".codex\config.toml"
  $hasTuiSection = (Test-Path $codexConfig) -and (Select-String -Path $codexConfig -Pattern '^\s*\[tui\]' -Quiet)
  if ($hasTuiSection) {
    SkipStep "Codex CLI statusline" "[tui] already defined -- add status_line manually"
  } else {
    Step "Codex CLI statusline"
    New-Item -ItemType Directory -Path (Join-Path $HOME ".codex") -Force | Out-Null
    $existingToml = if (Test-Path $codexConfig) { Get-Content $codexConfig -Raw } else { "" }
    $addition = "`n[tui]`nstatus_line = [`"model`", `"context-used`", `"tokens`", `"git-branch`"]`n"
    Set-Content -Path $codexConfig -Value ($existingToml + $addition) -NoNewline
    Write-Host "ok"
  }
} else {
  SkipStep "RTK Codex CLI instructions" "codex missing"
  SkipStep "graphify for Codex CLI" "codex missing"
  SkipStep "Codex CLI statusline" "codex missing"
}

# ---------------------------------------------------------------------------
# 6. Aider -- graphify + config
# ---------------------------------------------------------------------------
if (Get-Command aider -ErrorAction SilentlyContinue) {
  if (Get-Command graphify -ErrorAction SilentlyContinue) {
    if (-not (RunStep "graphify for Aider" { graphify install --platform aider })) { Warn "graphify aider install failed" }
  } else {
    SkipStep "graphify for Aider" "graphify missing"
  }
  Step "Aider global config"
  Link-File (Join-Path $DojoDir "aider\aider.conf.yml") (Join-Path $HOME ".aider.conf.yml")
  Write-Host "ok"
} else {
  SkipStep "graphify for Aider" "aider missing"
  SkipStep "Aider global config" "aider missing"
}

# ---------------------------------------------------------------------------
# 6b. OpenClaw -- token-optimizer + ponytail plugins when present
# ---------------------------------------------------------------------------
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
  if (-not (RunStep "OpenClaw plugins" {
    openclaw plugins install token-optimizer
    openclaw plugins install ponytail
  })) { Warn "openclaw plugins install failed" }
} else {
  SkipStep "OpenClaw plugins" "openclaw missing"
}

# 6c. Orca -- the desktop work environment. The `orca` CLI ships with the
#     desktop app (register it under Settings -> Orca CLI). It reads the
#     agents' own configs dojo already optimizes, so a dojo machine is an
#     Orca machine that runs token-efficient. Only the headless skill install
#     is done here; worktrees/terminals need the app paired once.
if (Get-Command orca -ErrorAction SilentlyContinue) {
  if (-not (RunStep "Orca agent skills" {
    orca skills install --skill orca-cli --skill orchestration --skill computer-use --agent claude-code,codex,copilot,opencode 2>$null
  })) { Warn "orca skills install failed (needs the desktop app paired once; rerun 'dojo update' after)" }
} else {
  SkipStep "Orca agent skills" "orca missing -- install the desktop app and register its CLI (Settings -> Orca CLI)"
}

# $TotalSteps is a hand-maintained constant (self-counting it would mean
# parsing this script's own if/elseif/else branches for distinct step
# labels -- more fragile than the drift it'd prevent). Catch drift here
# instead of letting the "(n/N)" progress display silently go wrong again.
if ($script:StepN -ne $TotalSteps) {
  Warn "TotalSteps=$TotalSteps but $($script:StepN) steps actually ran -- update the `$TotalSteps constant near the top of this script"
}

# ---------------------------------------------------------------------------
# 7. Verify
# ---------------------------------------------------------------------------
Write-Host "[dojo] verification"
function Have($cmd) { if (Get-Command $cmd -ErrorAction SilentlyContinue) { "installed" } else { "MISSING" } }
Write-Host "  plugins (opencode):   $(Have opencode)"
$claudePluginCount = 0
if (Get-Command claude -ErrorAction SilentlyContinue) {
  $claudePluginCount = @(claude plugin list 2>$null | Select-String -Pattern 'ponytail|token-optimizer|superpowers|code-review|pr-review-toolkit').Count
}
Write-Host "  plugins (claude):     $claudePluginCount of 5"
$taskObserverInstalled = Test-Path (Join-Path $ClaudeHome "skills\task-observer\SKILL.md")
Write-Host "  task-observer:        $(if ($taskObserverInstalled) { 'installed' } else { 'MISSING' })"
Write-Host "  serena (MCP):         $(Have serena)"
Write-Host "  copilot:              $(Have copilot)"
Write-Host "  codex:                $(Have codex)"
Write-Host "  aider:                $(Have aider)"
Write-Host "  openclaw:             $(Have openclaw)"
Write-Host "  orca:                 $(Have orca)"
Write-Host "  rtk:                  $(if (Get-Command rtk -ErrorAction SilentlyContinue) { (rtk --version | Select-Object -First 1) } else { 'MISSING' })"
Write-Host "  graphify:             $(if (Get-Command graphify -ErrorAction SilentlyContinue) { (graphify --version | Select-Object -First 1) } else { 'MISSING' })"
Write-Host "  dojo CLI:             $(if (Test-Path (Join-Path $LocalBin 'dojo.cmd')) { 'wired via git-bash' } else { 'unavailable -- see warning above' })"

if ($GithubMcpNew -and (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "[dojo]"
  Write-Host "[dojo] ONE MANUAL STEP (once per machine): the GitHub MCP server needs an"
  Write-Host "[dojo]   interactive login. Open Claude Code, type /mcp, pick 'github',"
  Write-Host "[dojo]   and authorize. opencode users: run 'opencode mcp auth github'."
}

# ---------------------------------------------------------------------------
# 8. SSH agent setup -- Windows' built-in OpenSSH Authentication Agent
#    service, not a per-shell sourced script like ssh-agent.sh on Linux/Mac.
# ---------------------------------------------------------------------------
Step "SSH agent setup"
try {
  $svc = Get-Service -Name ssh-agent -ErrorAction Stop
  if ($svc.StartType -ne "Automatic") { Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction Stop }
  if ($svc.Status -ne "Running") { Start-Service ssh-agent -ErrorAction Stop }
  $keyPath = Join-Path $HOME ".ssh\id_ed25519"
  if (Test-Path $keyPath) {
    $listed = (ssh-add -l 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { ssh-add $keyPath 2>&1 | Out-Null }
  }
  Write-Host "ok"
} catch {
  Write-Host "FAILED"
  Warn "couldn't configure the ssh-agent service ($($_.Exception.Message))"
  Warn "run PowerShell as Administrator once: Set-Service -Name ssh-agent -StartupType Automatic; Start-Service ssh-agent -- then re-run bootstrap.ps1"
  Warn "if the service doesn't exist at all, install it first: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
}

Write-Host "[dojo] done. Restart opencode and Claude Code on this machine."
