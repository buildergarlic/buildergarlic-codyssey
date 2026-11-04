## 1. 실행환경
- OS: 윈도우즈 11 버전 26H2 (OS 빌드 26300.9711) with WSL2
- OS Sub System: WSL(Windows Subsystme for Linux) 2
- Shell: bash
- Docker: Docker version 29.9.2, build a82e528
- Docker Desktop: version 4.98.0
- Git: git version 2.56.0.windows.4

## 2. 설치 진행
2-1. WSL2 활성화
wsl --install --no-distribution
백엔드 엔진만 활성화

2-1-1. 왜 WSL 설치?
- Windows 11에서 Windows용 Docker Desktop을 설치할 때 WSL2(Windows Subsystem for Linux 2)는 사실상 필수입니다. 단, 사용자가 직접 Ubuntu 배포판을 따로 설치할 필요는 없습니다.
- 도커의 태생적 구조: 도커 컨테이너(Linux 컨테이너)는 Linux 커널의 핵심 기능(Cgroups, Namespaces)을 공유하여 작동합니다. Windows 커널에는 이 기능이 직접 들어있지 않으므로, 백그라운드에서 경량 Linux 커널을 띄워줄 가상화 계층(WSL2)이 반드시 필요합니다.

2-1-2. WSL vs WSL2
- WSL 1은 윈도우가 리눅스 흉내를 내는 번역기라면, WSL 2는 윈도우 안에 진짜 리눅스 커널을 통째로 집어넣은 가상 머신입니다.
- Docker를 구축할 때 WSL 2는 별도 설정 없이 완벽하게 기본 지원하지만, WSL 1은 아키텍처 한계로 Docker를 정상적으로 구동할 수 없습니다.

2-1-3. WSL2 (경량 Hyper-V 기반)
1) 윈도우즈 Hyper-V 설치 필요
2) 윈도우즈 "선택적 기능"(설정->앱->선택 기능)에서 추가
3) 명령어줄에서 다음 명령어 실행
3-1) 키보드에서 Win + R 키를 눌러 실행창을 엽니다.
3-2) 열기 칸에 ms-settings:optionalfeatures를 입력하고 확인을 누릅니다.
3-3) 선택적 기능 설정 화면이 즉시 나타납니다
**코디세이 코딩스튜디오에서는 실행 안됨.(설정 진입 막혀 있음)
**설치된 것을 가정하고 진행한다.

2-2. Docker Desktop for Windows
2-2-1. Docker 왜 설치?
"내 컴퓨터에서는 잘 돌아가는데, 서버나 다른 사람 컴퓨터에서는 왜 안 되지?"(일명 "It works on my machine") 문제를 원천 차단하기 위함입니다.

#git user setting 
PS D:\buildergarlic-codyssey> git config --global buildergarlic
error: key does not contain a section: buildergarlic
PS D:\buildergarlic-codyssey> git config --global buildergarlic@gmail.com
error: invalid key: buildergarlic@gmail.com
PS D:\buildergarlic-codyssey> 

#git user setting 트러블슈팅(Troubleshooting)
PS D:\buildergarlic-codyssey> git config --global user.email "buildergarlic@gmail.com"
PS D:\buildergarlic-codyssey> git config --global user.email "buildergarlic@gmail.com"
PS D:\buildergarlic-codyssey> 
