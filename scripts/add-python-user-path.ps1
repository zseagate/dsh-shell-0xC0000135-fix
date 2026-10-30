$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python'
$pyExe = Join-Path $dir 'python.exe'
if (-not (Test-Path -LiteralPath $pyExe -PathType Leaf)) { throw "python.exe not found: $pyExe" }
$norm = $dir.TrimEnd('\', '/')

# --- Update the persistent user PATH in the registry ---
$envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
try {
    $raw = $envKey.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $kind = if ($null -ne $raw) { $envKey.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
    $parts = if ($null -eq $raw) { @() } else { @([string]$raw -split ';') }
    $already = @($parts | Where-Object { $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $norm }).Count -gt 0
    if (-not $already) {
        $next = (@($dir) + $parts) -join ';'
        $envKey.SetValue('Path', $next, $kind)
        Write-Output "ADDED: $dir prepended to user PATH (value kind: $kind)"
    } else {
        Write-Output "ALREADY_PRESENT: $dir already in user PATH"
    }
} finally { $envKey.Dispose() }

# --- Broadcast WM_SETTINGCHANGE ---
try {
    if (-not ('DshEnvBroadcast' -as [type])) {
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class DshEnvBroadcast { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, string l, uint f, uint t, out IntPtr r); }'
    }
    $r = [IntPtr]::Zero
    [void][DshEnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [IntPtr]::Zero, 'Environment', 2, 2000, [ref]$r)
    Write-Output "BROADCAST: WM_SETTINGCHANGE sent"
} catch { Write-Output "BROADCAST: skipped ($($_.Exception.Message))" }

# --- Set the current process PATH so the demonstration works immediately ---
$env:PATH = $dir + ';' + $env:PATH

# --- Verify from a different directory ---
Push-Location 'C:\Windows'
try {
    $v = & python.exe -c "import sys; print(sys.version.split()[0])"
    Write-Output "PYTHON_FROM_C:\Windows: exit=$LASTEXITCODE version=$v"
    $which = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
    Write-Output "PYTHON_SOURCE: $which"
    $loc = & python.exe -c "import os; print(os.getcwd())"
    Write-Output "PYTHON_CWD: $loc"
} finally { Pop-Location }

# --- Read back the registry to confirm persistence ---
$envKey2 = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
try {
    $readBack = [string]$envKey2.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $found = @($readBack -split ';' | Where-Object { $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $norm }).Count -gt 0
    Write-Output "REGISTRY_CONTAINS: $found"
} finally { $envKey2.Dispose() }
