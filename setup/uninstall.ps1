<#
.SYNOPSIS
    Uninstalls EDAMAME for Cursor on Windows.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$UserProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$AppDataRoot = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $UserProfile "AppData\Roaming" }
$LocalAppDataRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $UserProfile "AppData\Local" }

$ConfigHome = Join-Path $AppDataRoot "cursor-edamame"
$StateHome = Join-Path $LocalAppDataRoot "cursor-edamame\state"
$DataHome = Join-Path $LocalAppDataRoot "cursor-edamame"
$GlobalMcpPath = Join-Path $UserProfile ".cursor\mcp.json"

function Remove-McpEntry {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if (-not (Test-Path $ConfigPath)) { return }
    try {
        $root = Get-Content -Raw $ConfigPath | ConvertFrom-Json
    } catch {
        return
    }

    if (-not $root.PSObject.Properties["mcpServers"]) { return }
    $servers = $root.mcpServers
    if (-not $servers.PSObject.Properties[$Key]) { return }

    Copy-Item -Force $ConfigPath "$ConfigPath.bak"
    $null = $servers.PSObject.Properties.Remove($Key)
    $root | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
}

Remove-McpEntry -ConfigPath $GlobalMcpPath -Key "edamame"

foreach ($PathToRemove in @($DataHome, $ConfigHome, $StateHome)) {
    if (Test-Path $PathToRemove) {
        Remove-Item -Recurse -Force $PathToRemove
    }
}

Write-Host @"
Uninstalled EDAMAME for Cursor from:
  $DataHome
"@
