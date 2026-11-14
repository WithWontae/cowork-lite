# cowork-lite Windows 설치기. PowerShell에 한 줄로 붙여넣어 실행한다.
#   irm https://raw.githubusercontent.com/WithWontae/cowork-lite/main/install.ps1 | iex
#
# 하는 일: (1) Git Bash가 없으면 winget으로 Git을 설치하고 (2) install.sh를 Git Bash로 실행한다.
#   Claude Code·Node.js 설치, 작업 폴더, 안전장치 등록은 install.sh가 한다(Mac과 같은 흐름).
# 환경변수(테스트·개발용): COWORK_LITE_SRC=<로컬 소스 폴더>, COWORK_LITE_YES=1, COWORK_LITE_NAME=<표시 이름>,
#   COWORK_LITE_INSTALL_URL=<install.sh 주소>, COWORK_LITE_BASH=<Git Bash의 bash.exe 경로>
#
# 인코딩 주의: 이 파일은 BOM 포함 UTF-8로 저장한다. Windows PowerShell 5.1은 BOM이 없으면 한글을 깨뜨린다.
# iex로 실행될 때 `exit`를 쓰면 사용자의 PowerShell 창이 닫히므로, 함수 안에서는 값을 돌려주기만 한다.

function Find-CoworkGitBash {
    # 사용자가 위치를 지정했으면 그 파일만 본다(없으면 찾지 못한 것으로 처리).
    if ($env:COWORK_LITE_BASH) {
        if (Test-Path -LiteralPath $env:COWORK_LITE_BASH) { return $env:COWORK_LITE_BASH }
        return $null
    }
    # WSL의 bash.exe(System32)는 Git Bash가 아니므로 PATH에서 bash를 찾지 않고 Git 설치 위치만 본다.
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and $git.Source) {
        $root = Split-Path -Parent (Split-Path -Parent $git.Source)
        $c = Join-Path $root 'bin\bash.exe'
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Update-CoworkPath {
    # 방금 설치한 프로그램이 이 창에서 보이도록 레지스트리의 PATH를 다시 읽는다.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Invoke-CoworkBash([string]$bash, [string]$scriptPath) {
    # 자식 프로세스가 콘솔을 직접 쓰게 한다. 함수 안에서 `& 명령`을 쓰면 출력이 화면이 아니라 반환값으로 들어가
    # 안내 문구가 보이지 않고 종료 코드와도 섞인다. 질문(/dev/tty)도 콘솔을 그대로 쓴다.
    $p = Start-Process -FilePath $bash -ArgumentList ('"' + $scriptPath + '"') -NoNewWindow -Wait -PassThru
    return [int]$p.ExitCode
}

function Install-CoworkLite {
    $ErrorActionPreference = 'Stop'
    $oldEncoding = $null
    try {
        # 화면에 나오는 한글이 깨지지 않게 이 창의 출력 인코딩을 UTF-8로 맞췄다가 끝나면 되돌린다.
        $oldEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch { }
    try {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        } catch { }

        Write-Host 'cowork-lite 설치를 시작합니다.'

        $bash = Find-CoworkGitBash
        if (-not $bash -and -not $env:COWORK_LITE_BASH) {
            Write-Host 'Git이 없어 먼저 설치합니다. 몇 분 걸릴 수 있습니다.'
            Write-Host '권한 확인 창이 나오면 [예]를 눌러 주세요.'
            $winget = Get-Command winget -ErrorAction SilentlyContinue
            if (-not $winget) {
                Write-Host '✘ winget을 찾을 수 없어 Git을 설치하지 못했습니다.'
            } else {
                & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements | Out-Host
                if ($LASTEXITCODE -ne 0) { Write-Host '✘ Git 설치에 실패했습니다. 인터넷 연결이나 회사 보안 때문일 수 있습니다.' }
                Update-CoworkPath
                $bash = Find-CoworkGitBash
            }
        }
        if (-not $bash) {
            Write-Host '문제가 계속되면 같은 명령을 다시 실행해 보시고, 그래도 안 되면 아래 내용을 IT 담당자에게 전달해 주세요.'
            Write-Host 'IT 담당자에게 이렇게 요청해 주세요:'
            Write-Host '- 설치할 프로그램: Git for Windows'
            Write-Host '- 공식 주소: https://git-scm.com/download/win'
            Write-Host '- 개인 PC에 설치하려면 관리자 권한이 필요합니다.'
            return 1
        }

        if ($env:COWORK_LITE_SRC) {
            # 로컬 소스 폴더로 설치(개발·테스트). Git Bash가 읽도록 역슬래시를 슬래시로 바꾼다.
            $script = ($env:COWORK_LITE_SRC -replace '\\', '/').TrimEnd('/') + '/install.sh'
            return (Invoke-CoworkBash $bash $script)
        }

        $url = $env:COWORK_LITE_INSTALL_URL
        if (-not $url) { $url = 'https://raw.githubusercontent.com/WithWontae/cowork-lite/main/install.sh' }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('cowork-lite-install-' + [Guid]::NewGuid().ToString('N') + '.sh')
        try {
            Write-Host 'cowork-lite를 내려받는 중입니다…'
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
            } catch {
                Write-Host '✘ 내려받지 못했습니다. 인터넷 연결이나 회사 보안 때문일 수 있습니다. 잠시 뒤에 다시 시도해 주세요.'
                return 1
            }
            return (Invoke-CoworkBash $bash ($tmp -replace '\\', '/'))
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    } finally {
        if ($oldEncoding) { try { [Console]::OutputEncoding = $oldEncoding } catch { } }
    }
}

$cowork_lite_code = Install-CoworkLite
if ($cowork_lite_code -ne 0) { $global:LASTEXITCODE = $cowork_lite_code }
# 파일로 실행했을 때만 종료 코드를 돌려준다. iex로 실행한 경우 exit는 사용자의 창을 닫아 버린다.
if ($MyInvocation.MyCommand.Path) { exit $cowork_lite_code }
