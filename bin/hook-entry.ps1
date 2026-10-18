# hook-entry.ps1 — generic per-OS hook entry (Windows), parameterized by
# backend + event. Windows counterpart to bin/hook-entry.sh; replaces the
# per-backend backends/<agent>/code-{preview,close}-diff.ps1 shims. See ADR-0008.
#
# Invoked by the installer as:
#   powershell -NoProfile -ExecutionPolicy Bypass -File hook-entry.ps1 <backend> <pre|post>
#
# Reads the agent's hook payload on stdin, optionally fast-path-filters noisy
# tools, discovers the running Neovim (named pipe), and makes a single RPC into
# the in-process orchestrator. Abstains (exit 0, no stdout) on any failure.

# $HookEvent, not $Event: $Event is a PowerShell automatic variable (eventing
# subsystem). Harmless here, but renamed to avoid the foot-gun.
param([string]$Backend, [string]$HookEvent)

try {
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

  # ConvertFrom-Json is read-only and unbounded in depth, so this never
  # truncates; we use it only for the shallow fields below. The payload itself
  # is spliced verbatim into the RPC args (ADR-0007), never re-serialised.
  $payload = $raw | ConvertFrom-Json

  # Per-backend fast-path filter (perf gate; the Lua normaliser is the source of
  # truth). Only codex/copilot need it; claudecode filters via its settings
  # matcher, opencode via its TS allowlist.
  switch ($Backend) {
    'codex' {
      $tool = $payload.tool_name
      if ([string]::IsNullOrEmpty($tool) -or
          $tool -in @('read','view','glob','grep','ls','list_files') -or
          $tool -like 'mcp__*') { exit 0 }
    }
    'copilot' {
      $tool = $payload.toolName
      if ([string]::IsNullOrEmpty($tool) -or
          $tool -in @('view','glob','grep','ls','report_intent')) { exit 0 }
    }
  }

  $cwd = $payload.cwd
  if ([string]::IsNullOrEmpty($cwd) -and $payload.toolCall -and $payload.toolCall.args) {
    $cwd = $payload.toolCall.args.Cwd
  }
  if ([string]::IsNullOrEmpty($cwd) -and $payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) {
    $cwd = $payload.workspacePaths[0]
  }
  if ([string]::IsNullOrEmpty($cwd)) { $cwd = (Get-Location).Path }

  $targetFile = $payload.tool_input.file_path
  if ([string]::IsNullOrEmpty($targetFile)) { $targetFile = $payload.file_path }
  if ([string]::IsNullOrEmpty($targetFile)) { $targetFile = $payload.args.filePath }
  if ([string]::IsNullOrEmpty($targetFile)) { $targetFile = $payload.args.path }
  if ([string]::IsNullOrEmpty($targetFile) -and $payload.toolCall -and $payload.toolCall.args) {
    $targetFile = $payload.toolCall.args.TargetFile
  }

  . (Join-Path $PSScriptRoot "nvim-socket.ps1")
  . (Join-Path $PSScriptRoot "nvim-call.ps1")

  $socket = Find-NvimSocket -ProjectCwd $cwd -TargetFile $targetFile
  if ([string]::IsNullOrEmpty($socket)) {
    if ($Backend -eq 'agy') {
      if ($HookEvent -eq 'post') { Write-Output '{}' } else { Write-Output '{"decision":"allow"}' }
    }
    exit 0
  }

  # Verbatim splice of the raw payload; add the routing cwd separately so the
  # in-process handler can independently reject a cross-project RPC.
  $backendJson = ConvertTo-Json -Compress -InputObject $Backend
  $cwdJson = ConvertTo-Json -Compress -InputObject $cwd
  $argsJson = "[$raw,$backendJson,$cwdJson]"

  if ($HookEvent -eq 'post') {
    $null = Invoke-NvimCall -Server $socket -Module 'code-preview.post_tool' `
                            -Function 'handle' -ArgsJson $argsJson
    if ($Backend -eq 'agy') { Write-Output '{}' }
  } else {
    $result = Invoke-NvimCall -Server $socket -Module 'code-preview.pre_tool' `
                              -Function 'handle' -ArgsJson $argsJson
    if ($null -ne $result -and $result -ne '') {
      Write-Output $result
    } elseif ($Backend -eq 'agy') {
      Write-Output '{"decision":"allow"}'
    }
  }
} catch {
  # Boundary between agent and plugin: abstain on any failure.
  if ($Backend -eq 'agy') {
    if ($HookEvent -eq 'post') { Write-Output '{}' } else { Write-Output '{"decision":"allow"}' }
  }
  exit 0
}
