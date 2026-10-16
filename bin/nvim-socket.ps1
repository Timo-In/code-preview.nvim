# nvim-socket.ps1 — Windows counterpart to nvim-socket.sh. Discovers the
# running Neovim's named-pipe address (\\.\pipe\nvim.<pid>.0) and exposes it
# via Find-NvimSocket. See issue #46 / docs/adr/0007-windows-shim-via-shared-powershell-discovery.md.
#
# Usage (dot-source, then call):
#   . "$PSScriptRoot\nvim-socket.ps1"
#   $socket = Find-NvimSocket -ProjectCwd $cwd
#
# Discovery order mirrors the Unix resolver, minus the Unix-only globs:
#   1. $env:NVIM_LISTEN_ADDRESS, if responsive.
#   2. Pidfile lookup under %LOCALAPPDATA%\code-preview\sockets (preferred path;
#      written by lua/code-preview/pidfile.lua, same dir formula).
#   3. Named-pipe enumeration fallback (\\.\pipe\nvim.*).
# Every candidate is validated for responsiveness, hook eligibility, and
# project identity. There is no is-socket precheck (named pipes have no
# reliable existence test on Windows).

# Probe a server address for responsiveness. We only care about the exit code;
# all stdout/stderr is discarded.
#
# --headless is REQUIRED on Windows: without it, `nvim --server <addr>
# --remote-expr ...` starts a local TUI instead of acting purely as a remote
# client, and that local instance exits 0 even when <addr> is dead — a false
# positive that would make this probe accept stale pidfiles. With --headless,
# a dead server correctly yields a non-zero exit. (Validated on nvim 0.11,
# Windows; the Unix shim does not need this flag.)
function Test-NvimResponsive {
  param([string]$Server)
  if ([string]::IsNullOrEmpty($Server)) { return $false }
  try {
    & nvim --headless --server $Server --remote-expr "1" *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

# A live pipe may belong to a GUI or headless Neovim. Ask the plugin whether
# this instance is eligible before adding it to the hook target candidates.
function Test-NvimHookTarget {
  param(
    [string]$Server,
    [string]$ProjectCwd = "",
    [string]$TargetFile = ""
  )
  if (-not (Test-NvimResponsive $Server)) { return $false }
  if ([string]::IsNullOrEmpty($ProjectCwd)) {
    $expr = 'luaeval("require(''code-preview.hook_target'').is_enabled() and 1 or 0")'
  } else {
    $argsJson = ConvertTo-Json -Compress -InputObject @($ProjectCwd, $TargetFile)
    $expr = 'luaeval("(function() local h=require(''code-preview.hook_target''); return h.is_enabled() and h.matches_project(_A[1], _A[2]) and 1 or 0 end)()", ' + $argsJson + ')'
  }
  try {
    $enabled = & nvim --headless --server $Server --remote-expr $expr 2>$null
    return ($LASTEXITCODE -eq 0 -and "$enabled".Trim() -eq "1")
  } catch {
    return $false
  }
}

# Pidfile directory — MUST match lua/code-preview/pidfile.lua's Windows branch
# (%LOCALAPPDATA%\code-preview\sockets). Both sides compute it independently.
function Get-PidfileDir {
  return (Join-Path $env:LOCALAPPDATA "code-preview\sockets")
}

function Test-NvimHasBuffer {
  param([string]$Server, [string]$TargetFile)
  if ([string]::IsNullOrEmpty($TargetFile)) { return $false }
  $targetJson = ConvertTo-Json -Compress -InputObject $TargetFile
  try {
    $exists = & nvim --headless --server $Server --remote-expr "bufexists($targetJson)" 2>$null
    return ($LASTEXITCODE -eq 0 -and "$exists".Trim() -eq "1")
  } catch {
    return $false
  }
}

function Find-NvimSocket {
  param(
    [string]$ProjectCwd = "",
    [string]$TargetFile = ""
  )

  # 1. Explicit env var — probe it directly (no is-socket precheck on Windows).
  $envAddr = $env:NVIM_LISTEN_ADDRESS
  if (-not [string]::IsNullOrEmpty($envAddr) -and
      (Test-NvimHookTarget -Server $envAddr -ProjectCwd $ProjectCwd -TargetFile $TargetFile)) {
    return $envAddr
  }

  $live = New-Object System.Collections.Generic.List[string]

  # 2. Pidfile lookup. File format (two lines): line 1 = pipe path, line 2 = cwd.
  $pidDir = Get-PidfileDir
  if (Test-Path $pidDir) {
    foreach ($pf in (Get-ChildItem -Path $pidDir -File -ErrorAction SilentlyContinue)) {
      $lines = @(Get-Content -Path $pf.FullName -ErrorAction SilentlyContinue)
      if ($lines.Count -lt 1) { continue }
      $pipe = $lines[0]
      if ([string]::IsNullOrEmpty($pipe)) { continue }

      # Responsiveness probe self-heals stale pidfiles (crashed nvim, recycled PID).
      if (-not (Test-NvimHookTarget -Server $pipe -ProjectCwd $ProjectCwd -TargetFile $TargetFile)) { continue }

      $live.Add($pipe)
    }
  }

  # 3. Named-pipe enumeration fallback. Project matching is performed by RPC,
  # so enumerated pipes are held to the same rule as pidfile candidates.
  try {
    foreach ($path in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
      $leaf = Split-Path $path -Leaf
      if ($leaf -like 'nvim.*') {
        $pipe = "\\.\pipe\$leaf"
        if (-not $live.Contains($pipe) -and
            (Test-NvimHookTarget -Server $pipe -ProjectCwd $ProjectCwd -TargetFile $TargetFile)) {
          $live.Add($pipe)
        }
      }
    }
  } catch {
    # Pipe enumeration can throw on exotic pipe names; treat as "no fallback hits".
  }

  if ($live.Count -eq 0) { return "" }

  # 4. Prefer the project-matching instance that already has the target open.
  if (-not [string]::IsNullOrEmpty($TargetFile)) {
    foreach ($pipe in $live) {
      if (Test-NvimHasBuffer -Server $pipe -TargetFile $TargetFile) { return $pipe }
    }
  }

  # All candidates are already project-matched; use the first remaining one.
  return $live[0]
}
