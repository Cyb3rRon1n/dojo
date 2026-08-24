<#
.SYNOPSIS
  install.ps1 -- one-shot fresh-Windows-machine build-out for the dojo repo:
  opencode, Claude Code, GitHub Copilot CLI, OpenAI Codex CLI, Aider, Google
  Antigravity CLI, OpenClaw, and Cursor, each wired up with whatever token-optimization
  each one supports (RTK hooks, graphify, and -- for Claude Code + opencode
  only, for now -- ponytail/token-optimizer) + (optionally) your own
  multi-repo GitHub workspace, cloned and submodule-linked into
  projects\github\repos. Native Windows port of install.sh.

    powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/Cyb3rRon1n/dojo/main/install.ps1 | iex"

  Idempotent -- safe to re-run on a machine that's already set up. The only
  manual step this doesn't cover is GitHub auth (SSH key or HTTPS login) --
  do that first, or this script will tell you to at the end.

  Interactive runs prompt for which tools to install, and (on a machine
  that hasn't cloned one yet) for your own owner/repo to use as the
  multi-repo workspace -- leave that blank to skip it entirely. To skip
  either prompt (e.g. scripted/headless), set the env vars first:
    $env:DOJO_TOOLS = "opencode,claude"
    $env:DOJO_REPOS_REPO = "you/your-workspace"
    irm .../install.ps1 | iex

  Install-method notes vs. install.sh (confirmed against each tool's own
  docs -- not guessed):
   - opencode has no official Windows installer from opencode.ai itself;
     `npm install -g opencode-ai` is the community-confirmed working method.
   - Aider, uv, and OpenClaw all ship official *.ps1 installers.
   - Cursor installs via winget (Anysphere.Cursor).
   - rtk (rtk-ai/rtk) now ships a real Windows build
     (rtk-x86_64-pc-windows-msvc.zip) -- bootstrap.ps1 (called at the end of
     this script) downloads and verifies it directly.
#>

function Log($msg)  { Write-Host "[dojo] $msg" }
function Warn($msg) { Write-Host "[dojo][warn] $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "[dojo][error] $msg" -ForegroundColor Red; exit 1 }

$DojoDir      = if ($env:DOJO_DIR) { $env:DOJO_DIR } else { Join-Path $HOME "dojo" }
$DojoRepoSsh  = "git@github.com:Cyb3rRon1n/dojo.git"
$DojoRepoHttps = "https://github.com/Cyb3rRon1n/dojo.git"
$ReposDir     = if ($env:REPOS_DIR) { $env:REPOS_DIR } else { Join-Path $HOME "projects\github\repos" }
$LocalBin     = Join-Path $HOME ".local\bin"
$OpencodeBin  = Join-Path $HOME ".opencode\bin"
$NpmGlobal    = Join-Path $HOME ".npm-global"

foreach ($p in @($LocalBin, $OpencodeBin, (Join-Path $NpmGlobal "bin"))) {
  if ($env:PATH -notlike "*$p*") { $env:PATH = "$p;$env:PATH" }
}

# ---------------------------------------------------------------------------
# 0. GitHub auth -- the one thing this script can't do for you. Detect it up
#    front so clone/push failures later point back here instead of confusing
#    you.
# ---------------------------------------------------------------------------
$GitAuthOk = $false
if (Get-Command ssh -ErrorAction SilentlyContinue) {
  # ConnectTimeout is ssh's own -- doesn't cover every way this can hang
  # (a restrictive firewall black-holing the connection, a console quirk
  # under non-interactive invocation, etc.), so this is wrapped in a real
  # job timeout too: this check must never be able to block the rest of
  # the script indefinitely.
  $job = Start-Job -ScriptBlock { ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 }
  $sshOut = if (Wait-Job $job -Timeout 10) { Receive-Job $job | Out-String } else { "" }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  if ($sshOut -match "successfully authenticated") { $GitAuthOk = $true; Log "GitHub SSH auth OK" }
}
if ((-not $GitAuthOk) -and (Get-Command gh -ErrorAction SilentlyContinue)) {
  gh auth status *>$null
  if ($LASTEXITCODE -eq 0) { $GitAuthOk = $true; Log "GitHub HTTPS auth OK (gh)" }
}
if (-not $GitAuthOk) {
  Warn "no GitHub auth detected -- repo clones below will fall back to HTTPS (read-only)."
  Warn "set up one of these before pushing anything:"
  Warn "  SSH:   ssh-keygen -t ed25519 -C you@example.com   (then add $HOME\.ssh\id_ed25519.pub at https://github.com/settings/keys)"
  Warn "  HTTPS: gh auth login"
  if ((-not [Console]::IsInputRedirected) -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    $reply = Read-Host "[dojo] run 'gh auth login' now (device flow)? [y/N]"
    if ($reply -match '^(y|yes)$') {
      gh auth login
      gh auth status *>$null
      if ($LASTEXITCODE -eq 0) { $GitAuthOk = $true }
    }
  }
}

# ---------------------------------------------------------------------------
# Tool selection -- $env:DOJO_TOOLS="opencode,claude" skips the prompt for
# scripted/headless runs; otherwise, in an interactive session, ask. Piped
# runs with no console input default to installing everything, same as
# install.sh's non-TTY default.
# ---------------------------------------------------------------------------
$AllTools = @("opencode", "claude", "copilot", "codex", "aider", "agy", "openclaw", "cursor", "cline", "qwen", "goose", "pi")
if ($env:DOJO_TOOLS) {
  $SelectedTools = $env:DOJO_TOOLS -split ',' | ForEach-Object { $_.Trim() }
} elseif (-not [Console]::IsInputRedirected) {
  Write-Host "Which tools should dojo install/update?"
  Write-Host "  1) opencode"
  Write-Host "  2) claude   (Claude Code)"
  Write-Host "  3) copilot  (GitHub Copilot CLI)"
  Write-Host "  4) codex    (OpenAI Codex CLI)"
  Write-Host "  5) aider"
  Write-Host "  6) agy      (Google Antigravity CLI)"
  Write-Host "  7) openclaw (agent + plugins, token-optimizer/ponytail)"
  Write-Host "  8) cursor   (IDE -- install only, no plugin API)"
  Write-Host "  9) cline    (Cline CLI -- headless agent from the VS Code extension)"
  Write-Host " 10) qwen     (Qwen Code -- Alibaba's agent, free Qwen OAuth tier)"
  Write-Host " 11) goose    (Block's Goose -- MCP-native agent)"
  Write-Host " 12) pi       (Pi -- minimal harness, any provider)"
  $reply = Read-Host "Enter numbers/names (space or comma separated), or blank for all"
  if (-not $reply) {
    $SelectedTools = $AllTools
  } else {
    $SelectedTools = @()
    foreach ($tok in ($reply -replace ',', ' ' -split '\s+' | Where-Object { $_ })) {
      switch ($tok) {
        { $_ -in "1", "opencode" } { $SelectedTools += "opencode" }
        { $_ -in "2", "claude" }   { $SelectedTools += "claude" }
        { $_ -in "3", "copilot" }  { $SelectedTools += "copilot" }
        { $_ -in "4", "codex" }    { $SelectedTools += "codex" }
        { $_ -in "5", "aider" }    { $SelectedTools += "aider" }
        { $_ -in "6", "agy" }      { $SelectedTools += "agy" }
        { $_ -in "7", "openclaw" } { $SelectedTools += "openclaw" }
        { $_ -in "8", "cursor" }   { $SelectedTools += "cursor" }
        { $_ -in "9", "cline" }    { $SelectedTools += "cline" }
        { $_ -in "10", "qwen" }    { $SelectedTools += "qwen" }
        { $_ -in "11", "goose" }   { $SelectedTools += "goose" }
        { $_ -in "12", "pi" }      { $SelectedTools += "pi" }
        default { Warn "unknown tool selection '$tok' -- ignoring" }
      }
    }
  }
} else {
  $SelectedTools = $AllTools
}
function Want($tool) { $SelectedTools -contains $tool }

# ---------------------------------------------------------------------------
# Multi-repo workspace -- *your* GitHub org/repo, not dojo's. This used to be
# hardcoded to the dojo author's own workspace repo, which meant anyone else
# running this installer got the author's personal projects cloned onto
# their machine. Ask instead. $env:DOJO_REPOS_REPO=owner/repo skips the
# prompt for scripted/headless runs; leaving it blank (prompt or env) skips
# this whole step -- no multi-repo workspace is a perfectly fine answer.
# ---------------------------------------------------------------------------
$ReposSlug = $env:DOJO_REPOS_REPO
if ((-not $ReposSlug) -and (-not (Test-Path (Join-Path $ReposDir ".git"))) -and (-not [Console]::IsInputRedirected)) {
  $defaultSlug = ""
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    $defaultOwner = (gh api user --jq .login 2>$null)
    if ($defaultOwner) { $defaultSlug = "$defaultOwner/foundry" }
  }
  $promptSuffix = if ($defaultSlug) { " [$defaultSlug]" } else { "" }
  $ReposSlug = Read-Host "GitHub owner/repo for your multi-repo workspace$promptSuffix, blank to skip"
  if (-not $ReposSlug) { $ReposSlug = $defaultSlug }
}
if ($ReposSlug -match '://' -or $ReposSlug -like 'git@*') {
  # Already a full URL (someone pasted one instead of owner/repo shorthand)
  # -- use it as-is rather than mangling it into git@github.com:https://....
  $ReposRepoSsh = $ReposSlug
  $ReposRepoHttps = $ReposSlug
} else {
  $ReposRepoSsh = "git@github.com:$ReposSlug.git"
  $ReposRepoHttps = "https://github.com/$ReposSlug.git"
}

# Node.js/npm aren't preinstalled on every fresh machine -- claude/copilot/
# codex installs below need npm. Bootstrap it via winget if
# missing and one of those was picked (simpler than nvm-windows' separate
# version-management paradigm for the one thing dojo actually needs: npm on
# PATH).
if ((Want "claude") -or (Want "copilot") -or (Want "codex") -or (Want "cline") -or (Want "qwen") -or (Want "pi")) {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Log "npm not found -- installing Node.js LTS via winget"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
      $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")
      if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Warn "npm still missing after Node.js install -- claude/copilot/codex installs below will fail" }
    } else {
      Warn "npm missing and winget unavailable -- install Node.js manually from https://nodejs.org, then re-run this script"
    }
  }
}

# npm's default Windows prefix (under Program Files) is admin-protected,
# which turns `npm install -g` into an EPERM this script can't answer.
# Repoint npm at a user-owned prefix instead -- no elevation required, ever.
if (Get-Command npm -ErrorAction SilentlyContinue) {
  $npmPrefix = (npm config get prefix 2>$null)
  if ($npmPrefix -and ($npmPrefix -ne $NpmGlobal)) {
    $writable = $true
    try {
      $testFile = Join-Path $npmPrefix ".dojo-write-test"
      New-Item -ItemType File -Path $testFile -Force -ErrorAction Stop | Out-Null
      Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    } catch { $writable = $false }
    if (-not $writable) {
      Log "npm global prefix ($npmPrefix) isn't user-writable -- switching to $NpmGlobal"
      New-Item -ItemType Directory -Path $NpmGlobal -Force | Out-Null
      npm config set prefix $NpmGlobal
      if ($env:PATH -notlike "*$NpmGlobal*") { $env:PATH = "$NpmGlobal;$NpmGlobal\bin;$env:PATH" }
    }
  }
}

# ---------------------------------------------------------------------------
# 1. Core tools
# ---------------------------------------------------------------------------
if (Want "opencode") {
  if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Log "installing opencode"
    if (Get-Command npm -ErrorAction SilentlyContinue) {
      npm install -g opencode-ai *>$null
      if ($LASTEXITCODE -ne 0) { Warn "opencode install failed (community npm package, unofficial -- see https://opencode.ai)" }
    } else {
      Warn "opencode needs npm -- install Node.js first, or see https://opencode.ai"
    }
  } else {
    Log "opencode already installed ($(opencode --version))"
  }
}

if (Want "claude") {
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Log "installing Claude Code"
    # newer npm gates postinstall scripts (allow-scripts) -- claude-code's
    # postinstall fetches its native binary, so it must be allowed explicitly
    # or `claude` ends up a broken shim with no binary behind it.
    npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code
    if ($LASTEXITCODE -ne 0) { Die "claude install failed (no elevation used -- check npm prefix with 'npm config get prefix')" }
    claude --version *>$null
    if ($LASTEXITCODE -ne 0) { Die "claude installed but its postinstall (native binary fetch) didn't run -- try: npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code" }
  } else {
    Log "claude already installed ($(claude --version))"
  }
}

if (Want "copilot") {
  if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    Log "installing GitHub Copilot CLI"
    npm install -g @github/copilot
    if ($LASTEXITCODE -ne 0) { Warn "copilot install failed (needs Node 22+; check npm prefix with 'npm config get prefix')" }
  } else {
    Log "copilot already installed"
  }
}

if (Want "codex") {
  if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Log "installing OpenAI Codex CLI"
    npm install -g @openai/codex
    if ($LASTEXITCODE -ne 0) { Warn "codex install failed (needs Node 22+; check npm prefix with 'npm config get prefix')" }
  } else {
    Log "codex already installed"
  }
}

if (Want "aider") {
  if (-not (Get-Command aider -ErrorAction SilentlyContinue)) {
    Log "installing Aider"
    try {
      Invoke-Expression (Invoke-RestMethod -Uri "https://aider.chat/install.ps1")
    } catch { Warn "aider install failed: $($_.Exception.Message)" }
  } else {
    Log "aider already installed"
  }
}

# Gemini CLI stopped serving consumer requests on 2026-06-18 (Google moved
# everyone to Antigravity CLI -- a Go binary with its own installer).
if (Want "agy") {
  if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
    Log "installing Google Antigravity CLI"
    irm https://antigravity.google/cli/install.ps1 | iex
    if (-not (Get-Command agy -ErrorAction SilentlyContinue)) { Warn "agy install failed" }
  } else {
    Log "agy already installed"
  }
}

if (Want "openclaw") {
  if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    Log "installing OpenClaw"
    try {
      # -NoOnboard, matching install.sh's --no-onboard: without it the
      # installer launches an interactive onboarding wizard that can't
      # run headlessly (confirmed live -- it fails outright with no TTY).
      # Invoke-Expression alone can't pass switches to the downloaded
      # script; scriptblock creation can.
      & ([scriptblock]::Create((Invoke-RestMethod -Uri "https://openclaw.ai/install.ps1"))) -NoOnboard
    } catch { Warn "openclaw install failed: $($_.Exception.Message)" }
  } else {
    Log "openclaw already installed"
  }
}

if (Want "cursor") {
  if (-not (Get-Command cursor -ErrorAction SilentlyContinue)) {
    Log "installing Cursor (IDE)"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      winget install --id=Anysphere.Cursor -e --accept-source-agreements --accept-package-agreements --disable-interactivity
      if ($LASTEXITCODE -ne 0) { Warn "cursor install failed" }
    } else {
      Warn "cursor needs winget (App Installer, ships with Windows 10 1709+/11) -- see https://cursor.com/downloads"
    }
  } else {
    Log "cursor already installed"
  }
}

if (Want "cline") {
  if (-not (Get-Command cline -ErrorAction SilentlyContinue)) {
    Log "installing Cline CLI"
    npm install -g cline
    if ($LASTEXITCODE -ne 0) { Warn "cline install failed (needs Node 22+)" }
  } else {
    Log "cline already installed"
  }
}

if (Want "qwen") {
  if (-not (Get-Command qwen -ErrorAction SilentlyContinue)) {
    Log "installing Qwen Code"
    npm install -g @qwen-code/qwen-code
    if ($LASTEXITCODE -ne 0) { Warn "qwen install failed" }
  } else {
    Log "qwen already installed"
  }
}

# Prebuilt zip from GitHub releases (~90MB), self-contained binary into the
# user-local bin dir that bootstrap.ps1 already puts on the User PATH.
if (Want "goose") {
  if (-not (Get-Command goose -ErrorAction SilentlyContinue)) {
    Log "installing Goose (Block)"
    $GooseDir = Join-Path $HOME ".local\bin"
    New-Item -ItemType Directory -Path $GooseDir -Force | Out-Null
    $GooseZip = Join-Path $env:TEMP "goose.zip"
    try {
      Invoke-WebRequest "https://github.com/block/goose/releases/latest/download/goose-x86_64-pc-windows-msvc.zip" -OutFile $GooseZip
      Expand-Archive $GooseZip -DestinationPath $env:TEMP\goose-extract -Force
      Copy-Item (Join-Path $env:TEMP\goose-extract "goose.exe") $GooseDir -Force
      if (-not (Get-Command goose -ErrorAction SilentlyContinue)) { Warn "goose installed to $GooseDir -- open a new shell so it lands on PATH" }
    } catch {
      Warn "goose install failed: $($_.Exception.Message)"
    } finally {
      Remove-Item $GooseZip -Force -ErrorAction SilentlyContinue
      Remove-Item $env:TEMP\goose-extract -Recurse -Force -ErrorAction SilentlyContinue
    }
  } else {
    Log "goose already installed"
  }
}

if (Want "pi") {
  if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
    Log "installing Pi coding agent"
    npm install -g @earendil-works/pi-coding-agent
    if ($LASTEXITCODE -ne 0) { Warn "pi install failed" }
  } else {
    Log "pi already installed"
  }
}

# uv is the Python tool manager graphify installs through
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Log "installing uv (needed for graphify)"
  try {
    Invoke-Expression (Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1")
  } catch { Warn "uv install failed -- graphify will be skipped by bootstrap" }
} else {
  Log "uv already installed"
}

# python3 -- linux/mac never need this step (ships by default on virtually
# every distro); Windows doesn't ship one. dojo-tokens.py (behind
# `dojo tokens`) needs a real python3.
# Get-Command alone isn't enough to detect this: Windows ships fake
# "app execution alias" stubs for both python.exe and python3.exe that
# Get-Command happily reports as present even when nothing real is
# installed -- actually invoking one is the only way to tell the
# difference (confirmed live: a real python.exe existing on PATH does NOT
# mean python3 does too, they're two separate stubs).
function Test-RealPython($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { return $false }
  $out = (& $cmd --version 2>&1 | Out-String)
  return ($LASTEXITCODE -eq 0) -and ($out -match "Python \d")
}
if (-not ((Test-RealPython "python3") -or (Test-RealPython "python"))) {
  Log "installing Python (needed for dojo tokens)"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Python.Python.3.13 -e --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
    $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not (Test-RealPython "python")) { Warn "python still missing after install -- dojo tokens will be silently unavailable" }
  } else {
    Warn "python missing and winget unavailable -- install manually from https://python.org, or dojo tokens stays silently unavailable"
  }
} else {
  Log "python already installed"
}

# ---------------------------------------------------------------------------
# 2. dojo checkout
# ---------------------------------------------------------------------------
if (Test-Path (Join-Path $DojoDir ".git")) {
  Log "updating $DojoDir"
  git -C $DojoDir pull --ff-only
  if ($LASTEXITCODE -ne 0) { Warn "dojo pull failed" }
} else {
  Log "cloning dojo -> $DojoDir"
  git clone $DojoRepoSsh $DojoDir 2>$null
  if ($LASTEXITCODE -ne 0) {
    git clone $DojoRepoHttps $DojoDir
    if ($LASTEXITCODE -ne 0) { Die "clone failed" }
  }
}

# ---------------------------------------------------------------------------
# 3. Full stack (plugins, hooks, binaries, configs)
# ---------------------------------------------------------------------------
Log "running bootstrap"
& (Join-Path $DojoDir "bootstrap.ps1")

# ---------------------------------------------------------------------------
# 4. projects\github\repos -- the multi-repo workspace (submodule-linked)
# ---------------------------------------------------------------------------
if (Test-Path (Join-Path $ReposDir ".git")) {
  Log "updating $ReposDir"
  git -C $ReposDir pull --ff-only
  if ($LASTEXITCODE -ne 0) { Warn "repos pull failed" }
  git -C $ReposDir submodule update --init --recursive
  if ($LASTEXITCODE -ne 0) { Warn "submodule update failed" }
} elseif ($ReposSlug) {
  Log "cloning repos workspace -> $ReposDir"
  New-Item -ItemType Directory -Path (Split-Path $ReposDir -Parent) -Force | Out-Null
  git clone $ReposRepoSsh $ReposDir 2>$null
  if ($LASTEXITCODE -ne 0) {
    git clone $ReposRepoHttps $ReposDir
    if ($LASTEXITCODE -ne 0) { Die "repos clone failed" }
  }
  git -C $ReposDir submodule update --init --recursive
  if ($LASTEXITCODE -ne 0) { Warn "submodule update failed" }
} else {
  Log 'no multi-repo workspace configured -- skipping (set $env:DOJO_REPOS_REPO to add one later)'
}

Log "done. Restart opencode / Claude Code / Copilot CLI / Codex CLI / Aider / Antigravity (agy) / OpenClaw / Cursor / Cline / Qwen / Goose / Pi -- you're ready to launch in any repo."
if ($SelectedTools -contains "claude") {
  Log "one manual step, once per machine: open Claude Code and run '/mcp', pick 'github', authorize -- that wires up GitHub Issues/PRs tooling for every session after"
}
if (-not $GitAuthOk) {
  Warn "reminder: no GitHub auth was detected, so pushes will fail until you run"
  Warn "  ssh-keygen -t ed25519 -C you@example.com   (then add the key on GitHub)"
  Warn "or"
  Warn "  gh auth login"
}

# ---------------------------------------------------------------------------
# 5. Drop into the repos workspace, if this is an interactive session.
# ---------------------------------------------------------------------------
if ((-not [Console]::IsInputRedirected) -and (Test-Path $ReposDir)) {
  Write-Host ""
  $reply = Read-Host "[dojo] enter dojo (cd into $ReposDir) or exit? [enter/exit]"
  if ($reply -match '^(exit|n|no)$') {
    Log "staying put -- cd $ReposDir whenever you're ready."
  } else {
    Log "entering $ReposDir -- type 'exit' to leave."
    Set-Location $ReposDir
  }
}
