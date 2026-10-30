$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python'
$pyExe = Join-Path $dir 'python.exe'
if (-not (Test-Path -LiteralPath $pyExe -PathType Leaf)) { throw "python.exe not found: $pyExe" }
$norm = $dir.TrimEnd('\', '/')

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

try {
    if (-not ('DshEnvBroadcast' -as [type])) {
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class DshEnvBroadcast { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, string l, uint f, uint t, out IntPtr r); }'
    }
    $r = [IntPtr]::Zero
    [void][DshEnvBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [IntPtr]::Zero, 'Environment', 2, 2000, [ref]$r)
    Write-Output "BROADCAST: WM_SETTINGCHANGE sent"
} catch { Write-Output "BROADCAST: skipped ($($_.Exception.Message))" }

# --- Build effective PATH from registry (system + user) and verify ---
$mK = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($base)
$machinePath = [string]$mK.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$mK.Dispose()
$uK = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
$userPath = [string]$uK.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$uK.Dispose()
$env:PATH = ($machinePath.TrimEnd(';') + ';' + $userPath.TrimStart(';'))

Push-Location 'C:\Windows'
try {
    $v = & python.exe -c "import sys; print(sys.version.split()[0])"
    Write-Output "PYTHON_FROM_C:\Windows (effective system+user PATH): exit=$LASTEXITCODE version=$v"
    Write-Output "PYTHON_SOURCE: $((Get-Command python.exe -ErrorAction SilentlyContinue).Source)"
    $loc = & python.exe -c "import os; print(os.getcwd())"
    Write-Output "PYTHON_CWD: $loc"
} finally { Pop-Location }

$mK2 = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($base)
try {
    $readBack = [string]$mK2.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $found = @($readBack -split ';' | Where-Object { $_.Trim().Trim('"').TrimEnd('\', '/') -ieq $norm }).Count -gt 0
    Write-Output "SYSTEM_REGISTRY_CONTAINS: $found"
} finally { $mK2.Dispose() }
