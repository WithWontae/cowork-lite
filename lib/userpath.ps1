# 사용자 PATH(HKCU\Environment\Path)에 폴더를 넣거나 뺀다. 이 파일은 ASCII만 쓴다(인코딩 문제를 피하려고).
#   powershell -NoProfile -ExecutionPolicy Bypass -File userpath.ps1 add|remove <폴더>
# 출력: added | already | removed | absent
# 값 종류(REG_EXPAND_SZ)를 그대로 둔다. [Environment]::SetEnvironmentVariable 이나 setx 는 값을 REG_SZ로 바꾸거나
# 1024자에서 자르므로 쓰지 않는다.
# 테스트용: COWORK_LITE_ENV_KEY=<HKCU 아래 하위 키>가 있으면 그 키를 대신 고친다(실제 PATH를 건드리지 않는다).
param(
    [Parameter(Mandatory = $true)][ValidateSet('add', 'remove')][string]$Action,
    [Parameter(Mandatory = $true)][string]$Dir
)
$ErrorActionPreference = 'Stop'

$custom = [bool]$env:COWORK_LITE_ENV_KEY
$keyPath = if ($custom) { $env:COWORK_LITE_ENV_KEY } else { 'Environment' }
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($keyPath, $true)
if (-not $key) {
    if (-not $custom) { throw 'HKCU Environment key not found' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($keyPath)
}
try {
    $names = $key.GetValueNames()
    $cur = ''
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    if ($names -contains 'Path') {
        $cur = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind('Path')
    }
    $parts = @($cur -split ';' | Where-Object { $_ -ne '' })
    $want = $Dir.TrimEnd('\')
    $has = @($parts | Where-Object { $_.TrimEnd('\') -ieq $want }).Count -gt 0

    if ($Action -eq 'add') {
        if ($has) { 'already'; return }
        $parts = @($parts) + $Dir
        $result = 'added'
    } else {
        if (-not $has) { 'absent'; return }
        $parts = @($parts | Where-Object { $_.TrimEnd('\') -ine $want })
        $result = 'removed'
    }
    $key.SetValue('Path', ($parts -join ';'), $kind)
} finally {
    $key.Close()
}

if (-not $custom) {
    # 레지스트리만 고치면 이미 떠 있는 탐색기가 모른다. 사용자 환경변수를 하나 썼다 지워서 변경 알림(WM_SETTINGCHANGE)을 보낸다.
    [Environment]::SetEnvironmentVariable('COWORK_LITE_PATH_REFRESH', '1', 'User')
    [Environment]::SetEnvironmentVariable('COWORK_LITE_PATH_REFRESH', $null, 'User')
}
$result
