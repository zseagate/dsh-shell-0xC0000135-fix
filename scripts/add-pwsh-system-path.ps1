$ErrorActionPreference = 'Stop'
$dir = 'D:\Program Files\PowerShell-7'
$pwshExe = Join-Path $dir 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshExe -PathType Leaf)) { throw "pwsh.exe not found: $pwshExe" }
$norm = $dir.TrimEnd('\', '/')

# --- Update the persistent SYSTEM (machine) PATH ---
$base = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$envKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($base, $true)
try {
    $raw = $envKey.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $kind = if ($null -ne $raw) { $envKey.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::String }
    $parts = if ($null -eq $raw) { @() } else { @([string]$raw -split ';') }
    $already = @($parts | Where-Object { $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $norm }).Count -gt 0
    if (-not $already) {
        $next = (@($dir) + $parts) -join ';'
        $envKey.SetValue('Path', $next, $kind)
        Write-Output "ADDED: $dir prepended to SYSTEM PATH (value kind: $kind)"
    } else {
        Write-Output "ALREADY_PRESENT: $dir already in SYSTEM PATH"
    }
} finally { $envKey.Dispose() }

# --- Broadcast WM_SETTINGCHANGE so running processes re-read the environment ---
try {
    if (-not ('DshEnvBroadcast' -as [type])) {
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class DshEnvBroadcast { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, string l, uint f, uint t, out IntPtr r); }'
    }
    $r = [IntPtr]::Zero
    [void][DshEnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [IntPtr]::Zero, 'Environment', 2, 2000, [ref]$r)
    Write-Output "BROADCAST: WM_SETTINGCHANGE sent"
} catch { Write-Output "BROADCAST: skipped ($($_.Exception.Message))" }

# --- Build the effective PATH from registry (machine + user) and verify from another directory ---
$mK = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($base)
$machinePath = [string]$mK.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$mK.Dispose()
$uK = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
$userPath = [string]$uK.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$uK.Dispose()
$effective = ($machinePath.TrimEnd(';') + ';' + $userPath.TrimStart(';'))
$env:PATH = $effective

Push-Location 'C:\Windows'
try {
    $v = & pwsh.exe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    Write-Output "PWSH_FROM_C:\Windows (effective system+user PATH): exit=$LASTEXITCODE version=$v"
    $which = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    Write-Output "PWSH_SOURCE: $which"
    $loc = & pwsh.exe -NoLogo -NoProfile -Command '(Get-Location).Path'
    Write-Output "PWSH_CWD: $loc"
} finally { Pop-Location }

# --- Read back machine registry to confirm persistence ---
$mK2 = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($base)
try {
    $readBack = [string]$mK2.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $found = @($readBack -split ';' | Where-Object { $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $norm }).Count -gt 0
    Write-Output "SYSTEM_REGISTRY_CONTAINS: $found"
} finally { $mK2.Dispose() }
