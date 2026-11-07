# Windows 11 · WSL2 · Docker Workstation Mission

Windows 11의 WSL2 Ubuntu에 bash 명령으로 Docker Engine을 직접 설치하고, Linux 파일 조작·권한 변경부터 Docker 이미지 빌드, 포트 매핑, 마운트, 볼륨 영속성, Git 연동까지 검증한 기록입니다.

> 검증 일자: 2026-11-04 (KST) · Ubuntu bash Docker Engine 설치(6절)·보너스 과제·재현성 검증: 2026-11-07 (KST)
> 아래 “실제 실행 로그”에는 터미널에서 확인한 출력만 기록했습니다. 설치·장애 대응 명령은 “재현 절차”로 구분했습니다.
> **평가자는 [13절 재현 가이드](#13-재현-가이드-평가자용)의 명령을 위에서부터 그대로 실행하면 7·8·12절 결과를 직접 확인할 수 있습니다.**

## 1. 평가 항목별 증거

| 평가 | 증거 위치 |
|---:|---|
| 1 | 4절: <code>mkdir</code>, <code>touch</code>, <code>cp</code>, <code>mv</code>, <code>rm</code> 실행 전후 목록과 시각 |
| 2 | 5절: <code>chmod 755/700</code> 전후 <code>ls -ld</code> 출력 |
| 3 | 6절: Ubuntu bash에서 Docker Engine 설치 로그, Client/Server 버전, <code>docker info</code> Server 값, 소켓·docker 그룹 확인 |
| 4 | 6절: <code>docker run hello-world</code>의 <code>Hello from Docker!</code> 출력 |
| 5 | 6절: 필터 없는 <code>docker images</code>, <code>docker ps -a</code> 출력 |
| 6 | 7절: 저장소의 실제 [Dockerfile](./Dockerfile), 웹 소스, 성공 빌드 로그 |
| 7 | 7절: <code>localhost:8080</code>의 HTTP 200 응답과 브라우저 화면 |
| 8 | 8절: 볼륨 기록 → 컨테이너 삭제 → 새 컨테이너에서 파일 복구 로그 |
| 9 | 10절: Git 사용자 설정, 원격 주소, 로컬/원격 추적 상태 |
| 10 | 3절: 디렉터리 설계 기준과 각 파일·폴더 역할 |
| 11 | 7·8절: 호스트:컨테이너 포트/경로 매핑 명세와 명령 순서 |
| 12 | 6절: 이미지(저장 템플릿)와 컨테이너(실행 인스턴스)의 차이 |
| 13 | 6절: 네트워크 네임스페이스와 포트 포워딩의 필요성 |
| 14 | 4절: 절대경로·상대경로 사용 기준과 예시 |
| 15 | 5절: rwx와 숫자 0~7 전체 매핑 |
| 16 | 9절: <code>ss</code>/<code>lsof</code>/Docker 조회 및 안전한 포트 해제 |
| 17 | 8절: 바인드 마운트와 Docker 볼륨 장단점·사용 사례 비교 |
| 18 | 10절: 실제 Git 오류, 조치 순서, 조치 후 원격 추적 상태 |
| 보너스 1~4 | 12절: Compose 단일·멀티 컨테이너, 운영 명령어 루틴, 환경 변수 주입 실제 로그 |
| 보너스 5 | 12-5절: GitHub SSH 키 설정 절차와 통과 기준 |
| 재현성 | 13절: 처음부터 따라 하는 절차, 통과 기준, 작성자 PC 종속 항목의 대체 방법, 클린 clone 재현 로그 |

## 2. 실행 환경

| 구분 | 작성자 PC (4·5·8절 로그, 10절 Git 로그, 화면 캡처, 2026-11-04) | 클라우드 Linux 검증 환경 (6·7절, 10절 Case 3, 12·13절 로그, 2026-11-07) |
|---|---|---|
| Host OS | Windows 11 | 클라우드 Linux 컨테이너 |
| Linux | WSL2 · Ubuntu 22.04.5 LTS | Ubuntu 24.04.5 LTS |
| Kernel | 6.18.54.1-microsoft-standard-WSL2 | 6.18.44 |
| Shell | GNU bash 5.1.16 | GNU bash 5.2.21 |
| Docker Engine | 29.9.2, linux/amd64 | 29.9.3 (6·7절, apt <code>docker-ce</code>) · 29.9.2 (12·13절) |
| Docker Compose | - | v5.7.0 (<code>docker-compose-plugin</code>) |
| Git | 2.34.1 (WSL2 Ubuntu) | 2.43.0 |

Docker는 Windows 프로그램으로 설치하지 않습니다. Windows에서는 WSL2와 Ubuntu만 설치하고, Docker Engine은 **Ubuntu 터미널(bash)** 안에서 apt로 설치합니다(6-2절).

최초 설치 재현 순서:

~~~powershell
# 1) 관리자 PowerShell: WSL2와 Ubuntu 22.04만 설치
wsl --install -d Ubuntu-22.04
wsl -l -v          # Ubuntu-22.04의 VERSION이 2인지 확인
wsl --update       # systemd를 지원하는 최신 WSL로 갱신
~~~

2) 이후는 PowerShell을 닫고 **Ubuntu 터미널(bash)**에서 6-2절 0~6단계로 Docker Engine을 설치합니다.

## 3. 디렉터리 구조와 설계 기준

~~~text
buildergarlic-codyssey/
├── .dockerignore
├── .gitignore
├── Dockerfile
├── README.md
├── app/
│   └── index.html
├── compose/                      # 12절 보너스 과제
│   ├── single/
│   │   └── docker-compose.yml    # 단일 서비스
│   ├── multi/
│   │   └── docker-compose.yml    # web + checker 멀티 컨테이너
│   └── env/
│       ├── .env.example          # 환경 변수 예시 (복사해서 .env로 사용)
│       ├── docker-compose.yml    # 환경 변수로 포트/모드 변경
│       └── nginx/
│           └── default.conf.template
└── screenshots/
    ├── container-webserver.png
    ├── vscode-github.png
    └── Websever-NginX-Container.png
~~~

| 경로 | 역할 |
|---|---|
| [Dockerfile](./Dockerfile) | Nginx 기반 커스텀 이미지 빌드 명세 |
| [.dockerignore](./.dockerignore) | Git 문서·스크린샷·Compose 설정·<code>.env</code> 등 불필요한 빌드 컨텍스트 제외 |
| [.gitignore](./.gitignore) | PC마다 다른 실제 <code>.env</code> 파일을 커밋에서 제외 |
| [app/](./app) | 컨테이너가 서비스할 애플리케이션 소스 |
| [app/index.html](./app/index.html) | Nginx 정적 시작 페이지 |
| [compose/single/](./compose/single/docker-compose.yml) | 보너스 1: 7절 <code>docker run</code>을 Compose 파일로 옮긴 단일 서비스 |
| [compose/multi/](./compose/multi/docker-compose.yml) | 보너스 2·3: 웹 서버 + 보조 서비스(checker) 멀티 컨테이너 |
| [compose/env/](./compose/env/docker-compose.yml) | 보너스 4: 환경 변수로 포트·모드 변경, Nginx 설정 템플릿과 <code>.env.example</code> |
| [screenshots/](./screenshots) | 브라우저, VS Code 검증 화면 |
| [README.md](./README.md) | 재현 절차, 실제 출력, 개념과 트러블슈팅 기록 |

실행 자산([Dockerfile](./Dockerfile), [app/](./app))과 문서·증거([README.md](./README.md), [screenshots/](./screenshots))를 분리했습니다. 저장소 루트를 빌드 컨텍스트로 사용하므로 <code>docker build .</code>의 <code>COPY ./app ...</code>가 같은 구조로 동작합니다. 권한 실습용 <code>test_dir/</code>는 임시 디렉터리라 제출 구조에서 제외했습니다.

## 4. 경로 기준과 파일·폴더 조작

### 절대경로와 상대경로

- 절대경로는 현재 디렉터리와 관계없이 같은 대상을 가리킵니다. 작업 위치 검증이나 바인드 마운트 원본처럼 경로 오류가 치명적인 곳에 사용합니다. 예: <code>/home/buildergarlic/workstation-mission/app</code>
- 상대경로는 현재 <code>pwd</code>를 기준으로 해석됩니다. 프로젝트 루트로 이동한 뒤 내부 파일을 다룰 때 사용합니다. 예: <code>./app</code>, <code>app/index.html</code>, <code>docker build .</code>
- “WSL2 홈을 사용한다”는 프로젝트 저장 위치 기준입니다. 모든 명령 인자까지 절대경로로 써야 한다는 뜻은 아닙니다.

Linux 권한과 빠른 바인드 마운트 I/O 검증을 위해 원본 실습은 Windows 마운트 영역인 <code>/mnt/c</code>가 아니라 WSL2 네이티브 경로인 <code>/home/buildergarlic/workstation-mission</code>에서 수행했습니다.

### 파일 생성·복사·이동·삭제 실제 로그

~~~console
[2026-11-04 20:59~21:03 KST, WSL2 Bash]

$ mkdir -p ~/workstation-mission
$ cd ~/workstation-mission
$ mkdir test_dir
$ touch empty_file.txt
$ echo "Hello Windows 11 WSL2 Workstation" > sample.txt
$ ls -la
total 16
drwxr-xr-x 3 buildergarlic buildergarlic 4096 Nov  4 21:00 .
drwxr-x--- 6 buildergarlic buildergarlic 4096 Nov  4 20:54 ..
-rw-r--r-- 1 buildergarlic buildergarlic    0 Nov  4 20:59 empty_file.txt
-rw-r--r-- 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 20:59 test_dir

$ cp sample.txt sample_copy.txt
$ mv sample_copy.txt test_dir/moved_sample.txt
$ ls -l test_dir/
total 4
-rw-r--r-- 1 buildergarlic buildergarlic 34 Nov  4 21:03 moved_sample.txt

$ rm empty_file.txt
$ ls -la
total 16
drwxr-xr-x 3 buildergarlic buildergarlic 4096 Nov  4 21:03 .
drwxr-x--- 6 buildergarlic buildergarlic 4096 Nov  4 20:54 ..
-rw-r--r-- 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 21:03 test_dir
~~~

마지막 목록에서 <code>empty_file.txt</code>는 사라졌고, 이동된 파일은 <code>test_dir/moved_sample.txt</code>에 존재하므로 생성·이동·삭제가 모두 검증됩니다.

## 5. Linux 권한 변경

각 8진수 자리는 차례로 소유자(User), 그룹(Group), 기타 사용자(Others)의 권한입니다. 한 자리 값은 <code>r=4</code>, <code>w=2</code>, <code>x=1</code>의 합입니다.

| 숫자 | 기호 | 허용 권한 |
|---:|:---:|---|
| 0 | <code>---</code> | 없음 |
| 1 | <code>--x</code> | 실행 |
| 2 | <code>-w-</code> | 쓰기 |
| 3 | <code>-wx</code> | 쓰기 + 실행 |
| 4 | <code>r--</code> | 읽기 |
| 5 | <code>r-x</code> | 읽기 + 실행 |
| 6 | <code>rw-</code> | 읽기 + 쓰기 |
| 7 | <code>rwx</code> | 읽기 + 쓰기 + 실행 |

예를 들어 755는 소유자 <code>rwx</code>, 그룹 <code>r-x</code>, 기타 사용자 <code>r-x</code>이고, 700은 소유자만 모든 권한을 가집니다. 디렉터리의 <code>x</code>는 그 안으로 진입·탐색할 권한입니다.

### 변경 전·후 실제 로그

~~~console
[2026-11-04 21:03 KST, /home/buildergarlic/workstation-mission]

$ ls -ld test_dir sample.txt
-rw-r--r-- 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 21:03 test_dir

$ chmod 755 sample.txt
$ chmod 700 test_dir
$ ls -ld test_dir sample.txt
-rwxr-xr-x 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwx------ 2 buildergarlic buildergarlic 4096 Nov  4 21:03 test_dir
~~~

파일은 644 → 755, 디렉터리는 755 → 700으로 바뀌었습니다. <code>/mnt/c</code>의 NTFS/DrvFs는 설정에 따라 POSIX 권한 변경을 그대로 보존하지 않을 수 있으므로 이 검증은 WSL2의 Linux 파일 시스템에서 수행했습니다.

## 6. Ubuntu bash에서 Docker Engine 설치, 이미지와 컨테이너

### 6-1. 설치 구성

Docker는 Windows 프로그램이 아니라 WSL2 Ubuntu 안에 Linux용 Docker Engine으로 설치합니다. 아래 명령은 모두 **Ubuntu 터미널(bash)**에서 실행합니다. Ubuntu 기본 저장소의 <code>docker.io</code> 대신 Docker 공식 apt 저장소를 쓰면 최신 Engine과 Buildx·Compose 플러그인을 한 저장소에서 같은 버전 체계로 받을 수 있습니다.

| 패키지 | 설치되는 것 | 역할 |
|---|---|---|
| <code>docker-ce</code> | <code>dockerd</code> | Docker Server(데몬). 이미지·컨테이너·네트워크·볼륨 관리 |
| <code>docker-ce-cli</code> | <code>docker</code> | Docker Client. <code>/var/run/docker.sock</code>으로 데몬에 요청 |
| <code>containerd.io</code> | <code>containerd</code>, <code>runc</code> | 실제 컨테이너 프로세스를 만드는 런타임 |
| <code>docker-buildx-plugin</code> | <code>docker buildx</code> | <code>docker build</code>의 BuildKit 빌더 (7절) |
| <code>docker-compose-plugin</code> | <code>docker compose</code> | Compose v2 (12절) |

### 6-2. 설치 절차 (재현 절차)

**0단계 (WSL2 전용): systemd 켜기.** <code>systemctl</code>로 Docker 서비스를 시작·자동 시작하려면 Ubuntu의 PID 1이 <code>systemd</code>여야 합니다.

~~~bash
ps -p 1 -o comm=          # systemd 가 출력되면 0단계는 건너뜁니다.
cat /etc/wsl.conf          # 기존 설정 확인
sudo nano /etc/wsl.conf    # 기존 내용은 두고 아래 두 줄을 추가한 뒤 저장
~~~

~~~ini
[boot]
systemd=true
~~~

PowerShell에서 <code>wsl --shutdown</code>을 실행한 뒤 Ubuntu 터미널을 다시 열고 <code>ps -p 1 -o comm=</code>가 <code>systemd</code>인지 확인합니다. WSL이 오래된 버전이면 먼저 <code>wsl --update</code>를 실행합니다.

**1~6단계: Docker Engine 설치와 확인.**

~~~bash
# 1) 충돌할 수 있는 비공식 패키지 제거 (설치되어 있지 않으면 "is not installed" 출력)
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

# 2) Docker 공식 apt 저장소 등록 (GPG 키 + 저장소 주소)
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
cat /etc/apt/sources.list.d/docker.list
sudo apt-get update

# 3) Docker Engine, CLI, containerd, Buildx, Compose 설치
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 4) 데몬 시작 + WSL(부팅) 시작 시 자동 시작
sudo systemctl enable --now docker
systemctl is-active docker
#    systemd를 켤 수 없는 환경이면 Ubuntu를 열 때마다: sudo service docker start

# 5) sudo 없이 docker 실행: 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER
#    그룹은 새 로그인부터 적용됩니다. Ubuntu 터미널을 모두 닫고 PowerShell에서
#    wsl --terminate Ubuntu-22.04 실행 후 다시 엽니다. (지금 셸에서만 바로 쓰려면 newgrp docker)
id -nG

# 6) 설치 확인
docker version
docker info --format 'ServerVersion={{.ServerVersion}}; OperatingSystem={{.OperatingSystem}}'
docker compose version
docker run hello-world
~~~

| 단계 | 하는 일 | 필요한 이유 |
|---|---|---|
| 0 | WSL2에서 systemd 사용 | <code>docker.service</code>를 <code>systemctl</code>로 관리하고 WSL을 열 때 자동으로 데몬을 띄우기 위해 |
| 1 | 비공식 패키지 제거 | Ubuntu 저장소의 <code>docker.io</code>·<code>containerd</code>·<code>runc</code>는 공식 패키지와 같은 파일을 설치해 충돌합니다. |
| 2 | GPG 키·저장소 등록 | <code>signed-by</code>로 지정한 Docker 키로 서명된 패키지만 받습니다. 코드네임은 <code>/etc/os-release</code>에서 자동으로 채워집니다(22.04는 <code>jammy</code>, 24.04는 <code>noble</code>). |
| 3 | 패키지 설치 | 6-1의 다섯 패키지. systemd 환경에서는 설치가 끝나면 <code>docker.service</code>가 바로 시작됩니다. |
| 4 | 서비스 시작·자동 시작 | <code>dockerd</code>가 <code>/var/run/docker.sock</code>을 열어야 CLI가 연결됩니다. |
| 5 | docker 그룹 추가 | 소켓 권한이 <code>srw-rw---- root docker</code>라서 root와 docker 그룹만 접근할 수 있습니다. |
| 6 | 확인 | Client와 Server 구간이 모두 출력되어야 데몬 연결이 정상입니다. |

> 보안 주의: docker 그룹 사용자는 컨테이너에 호스트의 <code>/</code>를 마운트할 수 있어 사실상 root 권한을 가집니다. 공용 실습 PC에서는 실습 후 <code>sudo gpasswd -d $USER docker</code>로 그룹에서 제거합니다.

통과 기준:

| 확인 명령 | 기대 결과 |
|---|---|
| <code>ps -p 1 -o comm=</code> (WSL2) | <code>systemd</code> |
| <code>systemctl is-active docker</code> | <code>active</code> |
| <code>cat /etc/apt/sources.list.d/docker.list</code> | <code>https://download.docker.com/linux/ubuntu jammy stable</code> (24.04는 <code>noble</code>) |
| <code>ls -l /var/run/docker.sock</code> | <code>srw-rw---- 1 root docker …</code> |
| <code>id -nG</code> | 출력에 <code>docker</code> 포함 |
| <code>docker version</code> | Client와 Server 모두 <code>Docker Engine - Community</code> |
| <code>docker info --format '{{.OperatingSystem}}'</code> | Ubuntu 이름 (WSL2에서는 <code>Ubuntu 22.04.5 LTS</code>) |
| <code>docker compose version</code> | <code>Docker Compose version v2</code> 이상 (검증 환경 v5.7.0) |
| <code>docker run hello-world</code> | <code>Hello from Docker!</code> |

연결이 안 되면 [10절 Case 3](#case-3-ubuntu-bash에서-docker-데몬-연결-실패)의 순서로 확인합니다.

### 6-3. 설치 실제 로그

2026-11-07 클라우드 Linux 검증 환경(Ubuntu 24.04)에서 1~3단계를 위 명령 그대로 실행한 출력입니다. 이 환경에는 Docker 29.9.2와 공식 저장소가 이미 있어서 apt가 29.9.3으로 **업그레이드**했습니다. 처음 설치하는 PC에서는 같은 자리에 <code>newly installed</code>로 표시됩니다. 반복되는 apt 진행 표시는 <code>…</code>로 줄였습니다.

~~~console
[2026-11-07 18:37 KST, 클라우드 Linux 검증 환경, root]

$ . /etc/os-release && echo "$PRETTY_NAME ($VERSION_CODENAME)"
Ubuntu 24.04.5 LTS (noble)

$ for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
Reading package lists...
Building dependency tree...
Reading state information...
Package 'docker.io' is not installed, so not removed
0 upgraded, 0 newly installed, 0 to remove and 16 not upgraded.
   … docker-doc, docker-compose, docker-compose-v2, podman-docker, containerd, runc도 같은 형식으로 "is not installed, so not removed" …

$ sudo apt-get update
Hit:1 http://security.ubuntu.com/ubuntu noble-security InRelease
Hit:2 https://download.docker.com/linux/ubuntu noble InRelease
Hit:3 http://archive.ubuntu.com/ubuntu noble InRelease
Hit:4 http://archive.ubuntu.com/ubuntu noble-updates InRelease
Hit:5 http://archive.ubuntu.com/ubuntu noble-backports InRelease
Reading package lists...

$ sudo apt-get install -y ca-certificates curl
Reading package lists...
Building dependency tree...
Reading state information...
curl is already the newest version (8.5.0-2ubuntu10.16).
The following packages will be upgraded:
  ca-certificates
1 upgraded, 0 newly installed, 0 to remove and 15 not upgraded.
   … 다운로드·압축 해제·인증서 갱신 출력 생략 …

$ sudo install -m 0755 -d /etc/apt/keyrings

$ sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

$ sudo chmod a+r /etc/apt/keyrings/docker.asc

$ echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

$ cat /etc/apt/sources.list.d/docker.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable

$ sudo apt-get update
Hit:1 https://download.docker.com/linux/ubuntu noble InRelease
Hit:2 http://archive.ubuntu.com/ubuntu noble InRelease
Hit:3 http://security.ubuntu.com/ubuntu noble-security InRelease
Hit:4 http://archive.ubuntu.com/ubuntu noble-updates InRelease
Hit:5 http://archive.ubuntu.com/ubuntu noble-backports InRelease
Reading package lists...

$ sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
Reading package lists...
Building dependency tree...
Reading state information...
containerd.io is already the newest version (2.4.2-3~ubuntu.24.04~noble).
docker-buildx-plugin is already the newest version (0.38.1-1~ubuntu.24.04~noble).
Suggested packages:
  cgroupfs-mount | cgroup-lite docker-model-plugin
Recommended packages:
  apparmor docker-ce-rootless-extras pigz
The following packages will be upgraded:
  docker-ce docker-ce-cli docker-compose-plugin
3 upgraded, 0 newly installed, 0 to remove and 12 not upgraded.
Need to get 50.5 MB of archives.
After this operation, 1473 kB of additional disk space will be used.
Get:1 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce-cli amd64 5:29.9.3-1~ubuntu.24.04~noble [17.6 MB]
Get:2 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce amd64 5:29.9.3-1~ubuntu.24.04~noble [24.6 MB]
Get:3 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-compose-plugin amd64 5.7.0-1~ubuntu.24.04~noble [8299 kB]
Fetched 50.5 MB in 1s (97.4 MB/s)
   … debconf 안내, 패키지 데이터베이스 읽기 진행 표시, "Preparing to unpack" 줄 생략 …
Unpacking docker-ce-cli (5:29.9.3-1~ubuntu.24.04~noble) over (5:29.9.2-1~ubuntu.24.04~noble) ...
Unpacking docker-ce (5:29.9.3-1~ubuntu.24.04~noble) over (5:29.9.2-1~ubuntu.24.04~noble) ...
Unpacking docker-compose-plugin (5.7.0-1~ubuntu.24.04~noble) over (5.6.1-1~ubuntu.24.04~noble) ...
Setting up docker-compose-plugin (5.7.0-1~ubuntu.24.04~noble) ...
Setting up docker-ce-cli (5:29.9.3-1~ubuntu.24.04~noble) ...
Setting up docker-ce (5:29.9.3-1~ubuntu.24.04~noble) ...
invoke-rc.d: could not determine current runlevel
invoke-rc.d: policy-rc.d denied execution of restart.

$ dpkg -l docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin | tail -n 5
ii  containerd.io         2.4.2-3~ubuntu.24.04~noble    amd64        An open and reliable container runtime
ii  docker-buildx-plugin  0.38.1-1~ubuntu.24.04~noble   amd64        Docker Buildx plugin extends build capabilities with BuildKit.
ii  docker-ce             5:29.9.3-1~ubuntu.24.04~noble amd64        Docker: the open-source application container engine
ii  docker-ce-cli         5:29.9.3-1~ubuntu.24.04~noble amd64        Docker CLI: the open-source application container engine
ii  docker-compose-plugin 5.7.0-1~ubuntu.24.04~noble    amd64        Docker Compose (V2) plugin for the Docker CLI.
~~~

- 저장소 파일에 <code>noble</code>이 자동으로 들어갔고, 패키지 5개가 모두 <code>ii</code>(설치 완료) 상태입니다.
- 마지막 두 줄의 <code>invoke-rc.d … denied</code>는 이 검증 환경이 systemd 없는 컨테이너라 설치 후 자동 재시작이 막혔다는 뜻입니다. systemd를 켠 WSL2에서는 설치가 끝나면 <code>docker.service</code>가 자동으로 시작됩니다. 이 환경에서 데몬을 띄운 과정은 10절 Case 3에 기록했습니다.

### 6-4. Docker Client와 Server(데몬) 실제 확인

~~~console
[2026-11-07 18:38 KST, 클라우드 Linux 검증 환경, 데몬 시작 직후, 시각은 UTC]

$ ls -l /var/run/docker.sock
srw-rw---- 1 root docker 0 Nov  7 09:38 /var/run/docker.sock

$ docker info --format "ServerVersion={{.ServerVersion}}; OSType={{.OSType}}; OperatingSystem={{.OperatingSystem}}; Containers={{.Containers}}; Images={{.Images}}"
ServerVersion=29.9.3; OSType=linux; OperatingSystem=Ubuntu 24.04.5 LTS; Containers=0; Images=0
~~~

~~~console
[2026-11-07 18:39 KST, 클라우드 Linux 검증 환경, docker 그룹에 추가한 일반 사용자]

$ docker version
Client: Docker Engine - Community
 Version:           29.9.3
 API version:       1.56
 Go version:        go1.26.10
 Git commit:        5457199
 Built:             Tue Nov  3 21:41:31 2026
 OS/Arch:           linux/amd64
 Context:           default

Server: Docker Engine - Community
 Engine:
  Version:          29.9.3
  API version:      1.56 (minimum version 1.40)
  Go version:       go1.26.10
  Git commit:       70efc0e
  Built:            Tue Nov  3 21:41:31 2026
  OS/Arch:          linux/amd64
  Experimental:     false
 containerd:
  Version:          v2.4.2
  GitCommit:        b7a25261e029d68978bbf290df0a62fc819b3c51
 runc:
  Version:          1.5.2
  GitCommit:        v1.5.2-0-g29dd3dc2
 docker-init:
  Version:          0.19.0
  GitCommit:        de40ad0

$ docker compose version
Docker Compose version v5.7.0
~~~

- Server 구간이 반환되었다는 것은 CLI가 <code>/var/run/docker.sock</code>을 통해 데몬에 질의를 완료했다는 뜻입니다.
- Client·Server가 모두 <code>Docker Engine - Community</code>, <code>OperatingSystem</code>이 Ubuntu이고 <code>Context</code>가 <code>default</code>이므로, Ubuntu 안에 apt로 설치한 <code>dockerd</code>에 직접 연결된 상태입니다.
- 소켓의 그룹이 <code>docker</code>라서 docker 그룹 사용자는 sudo 없이 접근할 수 있습니다(6-5).

### 6-5. sudo 없이 docker 실행 (docker 그룹) 실제 로그

~~~console
[2026-11-07 18:38 KST, 클라우드 Linux 검증 환경]

# 일반 사용자 mission: 그룹 추가 전
$ id -nG
mission

$ docker ps
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock

# 관리자 터미널
$ sudo usermod -aG docker mission

# mission으로 다시 로그인한 뒤
$ id -nG
mission docker

$ docker ps
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
~~~

그룹을 추가해도 이미 열려 있던 셸에는 반영되지 않으므로, 다시 로그인(WSL2에서는 <code>wsl --terminate &lt;배포판&gt;</code> 후 재실행)해야 <code>id -nG</code>에 <code>docker</code>가 보입니다.

### 6-6. hello-world 실제 출력

~~~console
[2026-11-07 18:40 KST, 클라우드 Linux 검증 환경, 일반 사용자]

$ docker run hello-world

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.
   … 안내 문구(docker run -it ubuntu bash, Docker Hub 링크) 생략 …
~~~

직전에 이미지를 받아 두어서 <code>Unable to find image … Pulling</code> 줄 없이 바로 실행되었습니다. 처음 받을 때는 Docker Hub에서 <code>429 Too Many Requests</code>(익명 다운로드 횟수 제한)가 한 번 났고, 잠시 후 다시 받아 해결했습니다. 13-3절 “네트워크 제한” 참고.

### 6-7. 이미지와 전체 컨테이너 목록

~~~console
[2026-11-07 18:40 KST, 클라우드 Linux 검증 환경, 일반 사용자]

$ docker run -dit --name my-ubuntu ubuntu:22.04 bash
8d65ee1e889be37de9a1890d38a0587cd334a78a3d3234f05ea26f4a85527f34

$ docker stop my-ubuntu
my-ubuntu

   … 중간의 docker ps, 7절 curl·healthcheck 확인 생략 …

$ docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
REPOSITORY     TAG       IMAGE ID       SIZE
custom-nginx   1.0       9d1b6be8f166   93.7MB
ubuntu         22.04     076e7bf82319   119MB
hello-world    latest    c567b231f656   25.9kB

$ docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}"
CONTAINER ID   IMAGE              STATUS                                PORTS                  NAMES
8d65ee1e889b   ubuntu:22.04       Exited (137) Less than a second ago                          my-ubuntu
c4c4b40d4ddd   hello-world        Exited (0) 10 seconds ago                                    elastic_curie
42b35b6a3c76   custom-nginx:1.0   Up About a minute (healthy)           0.0.0.0:8080->80/tcp   web-server
~~~

<code>custom-nginx:1.0</code>과 실행 중인 <code>web-server</code>는 7절에서 만든 것입니다. <code>docker ps -a</code>에는 종료된 컨테이너(<code>Exited</code>)까지 모두 표시됩니다. <code>Exited (137)</code>은 <code>bash</code>가 SIGTERM에 응답하지 않아 10초 뒤 SIGKILL(128+9)로 종료되었다는 뜻입니다.

### 6-8. 이미지와 컨테이너의 역할

Docker 이미지는 [Dockerfile](./Dockerfile)과 소스를 빌드한 읽기 전용 실행 템플릿, 즉 저장 결과입니다. 컨테이너는 그 이미지로 만든 실행 인스턴스입니다.

- <code>docker build -t custom-nginx:1.0 .</code>: 재사용할 이미지를 저장합니다.
- <code>docker run custom-nginx:1.0</code>: 이미지로 새 컨테이너를 생성하고 실행합니다.
- 컨테이너의 쓰기 계층을 수정해도 원본 이미지는 바뀌지 않습니다. 변경을 이미지에 포함하려면 다시 빌드해야 합니다.
- 컨테이너를 삭제하면 쓰기 계층도 사라집니다. 보존할 데이터는 바인드 마운트나 Docker 볼륨에 둡니다.

### 6-9. 네트워크 네임스페이스와 포트 포워딩

컨테이너는 호스트와 분리된 네트워크 네임스페이스(IP, 인터페이스, 포트 공간)를 가집니다. 따라서 컨테이너 내부 Nginx가 TCP 80에서 대기해도 호스트에서 그 포트에 바로 접속할 수 없습니다.

<code>-p 8080:80</code>은 호스트 TCP 8080 요청을 컨테이너 TCP 80으로 전달하므로 호스트에서는 <code>http://localhost:8080</code>으로 접속합니다. [Dockerfile](./Dockerfile)의 <code>EXPOSE 80</code>은 사용할 포트를 문서화할 뿐 실제로 호스트에 공개하지 않으며, 공개에는 <code>-p</code>가 필요합니다.

WSL2에서는 이 “호스트”가 Ubuntu입니다. WSL2는 Ubuntu의 <code>localhost</code> 포트를 Windows로 전달하므로 Windows 브라우저에서도 <code>http://localhost:8080</code>으로 접속됩니다.

## 7. 커스텀 이미지 빌드와 포트 매핑

### 실제 제출 파일

[Dockerfile](./Dockerfile)의 내용:

~~~dockerfile
FROM nginx:alpine

LABEL maintainer="buildergarlic"

COPY ./app /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -qO- http://localhost/ || exit 1
~~~

서비스할 HTML은 [app/index.html](./app/index.html)에 실제 파일로 제출했습니다.

### 실제 빌드 로그

~~~console
[2026-11-07 18:39 KST, 클라우드 Linux 검증 환경, 일반 사용자, ~/buildergarlic-codyssey]

$ docker build -t custom-nginx:1.0 .
#0 building with "default" instance using docker driver

#1 [internal] load build definition from Dockerfile
#1 transferring dockerfile: 223B done
#1 DONE 0.0s

#2 [internal] load metadata for docker.io/library/nginx:alpine
#2 DONE 1.1s

#3 [internal] load .dockerignore
#3 transferring context: 91B done
#3 DONE 0.0s

#4 [internal] load build context
#4 transferring context: 350B done
#4 DONE 0.0s

#5 [1/2] FROM docker.io/library/nginx:alpine@sha256:713fc2ebfd92e8217db451477182ee91944b123d2b1ee9fd5a8c6e91ca6c3a11
#5 resolve docker.io/library/nginx:alpine@sha256:713fc2ebfd92e8217db451477182ee91944b123d2b1ee9fd5a8c6e91ca6c3a11 0.0s done
#5 … 레이어 다운로드·압축 해제 진행 표시 생략 …
#5 DONE 1.3s

#6 [2/2] COPY ./app /usr/share/nginx/html
#6 DONE 0.1s

#7 exporting to image
#7 exporting layers 0.0s done
#7 exporting manifest sha256:12ceadb54ed146c1313a9b026d26eeee3e1c97c36e6f4fd49c5f194fd6edf9ad done
#7 exporting config sha256:b0d84f6c4d1f9e66f9d620c69035c5999db8f8f500dd1b71d0c332ddc7b49f3e done
#7 exporting attestation manifest sha256:4b56eefe65bef8e9077db5a42128f4489023aad4114f115632c8dc283ad80c28 done
#7 exporting manifest list sha256:9d1b6be8f166145de069168e5c5cf3fb4589fd6b1641e5bee517f417fc42c350 done
#7 naming to docker.io/library/custom-nginx:1.0 done
#7 unpacking to docker.io/library/custom-nginx:1.0
#7 unpacking to docker.io/library/custom-nginx:1.0 0.5s done
#7 DONE 0.6s
~~~

<code>#0 building with "default" instance</code>는 6절에서 설치한 Ubuntu의 기본 Docker 데몬(<code>docker-buildx-plugin</code>의 BuildKit)으로 빌드했다는 뜻입니다. <code>#3</code>의 <code>.dockerignore</code>가 적용되어 빌드 컨텍스트는 350B만 전송되었습니다.

### 매핑 명세와 재현 순서

Docker의 매핑 표기는 <code>호스트:컨테이너</code> 순서입니다.

| 목적 | 실행 옵션 | 호스트 측 | 컨테이너 측 |
|---|---|---|---|
| 기본 웹 서버 | <code>-p 8080:80</code> | TCP 8080 | Nginx TCP 80 |
| 바인드 마운트 웹 서버 | <code>-p 8081:80</code> | TCP 8081 | Nginx TCP 80 |
| 웹 소스 공유 | <code>$(pwd)/app:/usr/share/nginx/html</code> | 프로젝트 app 디렉터리 | Nginx 문서 루트 |
| 영속 데이터 | <code>mission-vol:/data</code> | Docker 관리 볼륨 | 컨테이너 /data |

~~~bash
cd ~/buildergarlic-codyssey   # git clone한 저장소 루트 (작성자 실습 당시 경로는 ~/workstation-mission, 13-3절 참고)
docker build -t custom-nginx:1.0 .
docker run -d --name web-server -p 8080:80 custom-nginx:1.0
curl -i http://localhost:8080
docker inspect --format '{{.State.Health.Status}}' web-server
docker stop web-server
docker rm web-server
~~~

### 호스트 포트 접속 실제 로그

~~~console
[2026-11-07 18:39~18:40 KST, 클라우드 Linux 검증 환경, 일반 사용자, ~/buildergarlic-codyssey]

$ docker run -d --name web-server -p 8080:80 custom-nginx:1.0
42b35b6a3c76056348e759c66b845adce72194f19e4c5e437a119f2640ecf471

$ sleep 35

$ docker inspect --format "Health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" web-server
Health=healthy

   … 6절 hello-world·목록 확인 생략 …

$ curl -sS -i http://localhost:8080
HTTP/1.1 200 OK
Server: nginx/1.31.8
Date: Sat, 07 Nov 2026 09:40:25 GMT
Content-Type: text/html
Content-Length: 280
Last-Modified: Sat, 07 Nov 2026 09:38:44 GMT
Connection: keep-alive
ETag: "6aeef1a4-118"
Accept-Ranges: bytes

<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Workstation Mission</title>
</head>
<body>
  <h1>Custom Nginx Container on Windows 11 (WSL2)</h1>
  <p>Version 1.0</p>
</body>
</html>
~~~

HTTP 200과 HTML 본문, 컨테이너 healthy 상태를 모두 확인했습니다. Dockerfile의 <code>HEALTHCHECK</code> 간격이 30초라 첫 판정까지 35초를 기다렸습니다. WSL2에서는 같은 컨테이너를 Windows 브라우저의 <code>http://localhost:8080</code>으로도 열 수 있습니다(6-9).

![localhost 8080 Nginx 응답](./screenshots/Websever-NginX-Container.png)

## 8. 바인드 마운트와 볼륨 영속성

### 두 방식의 차이

| 방식 | 장점 | 주의점과 적합 사례 |
|---|---|---|
| 바인드 마운트 | 지정한 호스트 파일을 컨테이너와 직접 공유해 수정 결과가 즉시 반영됩니다. | 호스트 경로·권한에 의존합니다. 개발 중인 소스·설정 공유에 적합합니다. |
| Docker 볼륨 | Docker가 저장 위치를 관리하며 컨테이너를 삭제해도 <code>docker volume rm</code> 전까지 데이터가 남습니다. | 호스트에서 직접 편집하기는 덜 편하지만 DB·애플리케이션 상태 보존에 적합합니다. |

### 바인드 마운트 즉시 반영 실제 로그

~~~console
[2026-11-04 KST, WSL2 Bash]

$ docker run -d --name bind-web -p 8081:80 \
    -v "$(pwd)/app:/usr/share/nginx/html" custom-nginx:1.0
ebd5ee3377b74a813864dd32ea29f8c11a4681c45e84cc7a1bafaa031bb333f3

$ curl http://localhost:8081
<!DOCTYPE html>
<html>
<body>
  <h1>Custom Nginx Container on Windows 11 (WSL2)</h1>
  <p>Version 1.0</p>
</body>
</html>

$ sed -i 's/Version 1.0/Version 2.0 (Bind Mounted on WSL2)/g' app/index.html
$ curl http://localhost:8081
<!DOCTYPE html>
<html>
<body>
  <h1>Custom Nginx Container on Windows 11 (WSL2)</h1>
  <p>Version 2.0 (Bind Mounted on WSL2)</p>
</body>
</html>

$ docker stop bind-web
bind-web
$ docker rm bind-web
bind-web
~~~

이미지를 다시 빌드하지 않았는데도 호스트 파일의 1.0 → 2.0 변경이 컨테이너 응답에 즉시 반영되었습니다.

### 볼륨의 컨테이너 삭제 전·후 실제 로그

~~~console
[2026-11-04 KST, WSL2 Bash]

$ docker volume create mission-vol
mission-vol

$ docker volume ls | grep mission-vol
local     mission-vol

$ docker run --name vol-writer -v mission-vol:/data alpine \
    sh -c "echo 'Persistent Data Test 123' > /data/record.txt && cat /data/record.txt"
Persistent Data Test 123

$ docker rm vol-writer
vol-writer

$ docker run --rm --name vol-reader -v mission-vol:/data \
    alpine cat /data/record.txt
Persistent Data Test 123
~~~

<code>vol-writer</code>를 삭제한 뒤 새 <code>vol-reader</code>에서 같은 파일을 읽었으므로 데이터가 컨테이너 계층이 아니라 볼륨에 보존되었음을 확인했습니다.

## 9. 포트 충돌 진단과 해제

<code>Bind for 0.0.0.0:8080 failed: port is already allocated</code>가 발생하면 다음 순서로 처리합니다.

1. Ubuntu bash에서 리스닝 소켓과 PID를 확인합니다.

~~~bash
ss -ltnp | grep ':8080 '
sudo lsof -nP -iTCP:8080 -sTCP:LISTEN
~~~

2. Docker 컨테이너가 포트를 게시했는지 먼저 확인합니다.

~~~bash
docker ps --filter "publish=8080" \
  --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}"
~~~

3. Docker 컨테이너가 점유했다면 확인한 컨테이너만 정상 종료합니다.

~~~bash
docker stop <확인한_컨테이너_이름>
docker rm <확인한_컨테이너_이름>
~~~

4. 일반 프로세스라면 1단계의 PID와 명령행을 다시 확인한 후 정상 종료 신호를 보냅니다. 무관한 PID를 종료하지 않습니다.

~~~bash
ps -fp <확인한_PID>
kill -TERM <확인한_PID>
ss -ltnp | grep ':8080 ' || echo "8080 port is free"
~~~

5. 해당 서비스를 중지할 수 없으면 충돌하지 않는 호스트 포트를 선택합니다. 컨테이너 내부 포트 80은 그대로 둘 수 있습니다.

~~~bash
docker run -d --name web-server-alt -p 8082:80 custom-nginx:1.0
curl -i http://localhost:8082
~~~

Windows 프로세스가 점유한 경우 PowerShell에서 <code>Get-NetTCPConnection -LocalPort 8080 -State Listen</code>과 <code>Get-Process -Id &lt;PID&gt;</code>로 소유자를 확인한 뒤 해당 애플리케이션을 정상 종료합니다.

## 10. Git 설정·원격 상태·트러블슈팅

### 사용자 설정 실제 로그

~~~console
$ git config --global user.name "buildergarlic"
$ git config --global user.email "nobody@nobody.com"
$ git config --global init.defaultBranch main
$ git config --list
user.name=buildergarlic
user.email=nobody@nobody.com
init.defaultbranch=main
core.repositoryformatversion=0
core.filemode=true
core.bare=false
core.logallrefupdates=true
~~~

### 원격 주소와 추적 상태 실제 로그

~~~console
[2026-11-04 22:41 KST, PowerShell]

PS> git remote -v
origin  https://github.com/buildergarlic/buildergarlic-codyssey.git (fetch)
origin  https://github.com/buildergarlic/buildergarlic-codyssey.git (push)

PS> git branch -vv
* main 8d572c6 [origin/main] 실행 완료 커밋

PS> git log -1 --date=iso --pretty=format:"%h %ad %s"
8d572c6 2026-11-04 22:28:40 +0900 실행 완료 커밋
~~~

캡처 시점에 로컬 <code>main</code>이 <code>origin/main</code>을 추적하고 동일 커밋을 가리켰습니다.

![VS Code와 GitHub 연동](./screenshots/vscode-github.png)

### Case 1: 잘못된 git config 키

실제 오류:

~~~console
PS> git config --global buildergarlic
error: key does not contain a section: buildergarlic

PS> git config --global nobody@nobody.com
error: invalid key: nobody@nobody.com
~~~

Git 설정 키는 <code>section.key</code> 형식이어야 하는데 값만 키 위치에 넣은 것이 원인입니다.

~~~powershell
git config --global user.name "buildergarlic"
git config --global user.email "nobody@nobody.com"
git config --global --get user.name
git config --global --get user.email
~~~

### Case 2: 원격 push 거부

실제 오류:

~~~console
PS> git push -u origin main
remote: fatal error in commit_refs
To https://github.com/buildergarlic/buildergarlic-codyssey.git
 ! [remote rejected] main -> main (failure)
error: failed to push some refs to 'https://github.com/buildergarlic/buildergarlic-codyssey.git'
~~~

조치 순서:

~~~powershell
# 1. 대상 원격 주소 확인·교정
git remote -v
git remote set-url origin https://github.com/buildergarlic/buildergarlic-codyssey.git

# 2. 로컬 객체 검증 및 일반 정리
git fsck --full
git gc

# 3. 원격 상태를 받은 뒤 차이 확인
git fetch origin
git log --oneline --graph --decorate --all -n 15

# 4. 일반 push 우선 시도
git push -u origin main

# 원격 이력을 의도적으로 대체해야 하고 차이를 검토한 경우에만
git push -u origin main --force-with-lease
~~~

<code>--force-with-lease</code>는 확인하지 않은 새 원격 커밋이 있으면 덮어쓰기를 거부하므로 <code>--force</code>보다 안전하지만, 원격 이력을 바꿀 수 있어 마지막 수단으로만 사용합니다. 조치 후의 원격 주소와 추적 상태는 위 실제 로그에 기록했습니다.

### Case 3: Ubuntu bash에서 Docker 데몬 연결 실패

6-2절 3단계(패키지 설치) 직후, 데몬을 시작하기 전에 발생한 실제 오류와 확인 순서입니다.

~~~console
[2026-11-07 18:38 KST, 클라우드 Linux 검증 환경, root]

$ docker --version
Docker version 29.9.3, build 5457199

$ docker info
Client: Docker Engine - Community
 Version:    29.9.3
 Context:    default
 Debug Mode: false
 Plugins:
  buildx: Docker Buildx (Docker Inc.)
    Version:  v0.38.1
    Path:     /usr/libexec/docker/cli-plugins/docker-buildx
  compose: Docker Compose (Docker Inc.)
    Version:  v5.7.0
    Path:     /usr/libexec/docker/cli-plugins/docker-compose

Server:
failed to connect to the docker API at unix:///var/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /var/run/docker.sock: connect: no such file or directory

$ ls -l /var/run/docker.sock
ls: cannot access '/var/run/docker.sock': No such file or directory

$ ps -p 1 -o comm=
process_api

$ sudo service docker status
 * Docker is not running

$ sudo service docker start
/etc/init.d/docker: 62: ulimit: error setting limit (Operation not permitted)

$ sleep 3; sudo service docker status
 * Docker is not running
~~~

원인 분석:

1. <code>docker --version</code>과 <code>docker info</code>의 Client 구간은 정상이므로 CLI는 설치되었습니다. Server 구간만 실패하고 <code>/var/run/docker.sock</code>이 없으므로 **데몬(<code>dockerd</code>)이 실행되지 않은 상태**입니다. 이전 버전의 Docker는 같은 상황에서 <code>Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?</code>을 출력합니다.
2. PID 1이 <code>systemd</code>가 아니므로 <code>systemctl</code>로 서비스를 시작할 수 없습니다. WSL2에서 6-2절 0단계를 하지 않았을 때와 같은 상태입니다.
3. 이 검증 환경은 컨테이너 샌드박스라서 init 스크립트(<code>service docker start</code>)의 <code>ulimit</code> 설정까지 막혀 실패했습니다. WSL2와 일반 Ubuntu에서는 생기지 않는 제약입니다.

조치:

| 환경 | 조치 |
|---|---|
| WSL2 + systemd (권장) | <code>sudo systemctl enable --now docker</code> 후 <code>systemctl is-active docker</code>가 <code>active</code>인지 확인 |
| WSL2, systemd를 켤 수 없음 | Ubuntu 터미널을 열 때마다 <code>sudo service docker start</code> |
| 이 검증 환경(컨테이너) | init 스크립트를 쓸 수 없어 root로 <code>dockerd</code>를 직접 백그라운드 실행 (검증 환경 전용 대체) |

조치 후 6-4절처럼 <code>/var/run/docker.sock</code>이 <code>srw-rw---- 1 root docker</code>로 생기고 <code>docker info</code>가 <code>ServerVersion=29.9.3; OSType=linux; OperatingSystem=Ubuntu 24.04.5 LTS</code>를 반환했습니다. 6-4절 출력이 해결 후 증거입니다.

같은 계열의 다른 오류:

| 증상 | 원인 | 확인·조치 |
|---|---|---|
| <code>permission denied while trying to connect to the docker API at unix:///var/run/docker.sock</code> | 현재 사용자가 docker 그룹이 아님 | <code>id -nG</code> 확인 → <code>sudo usermod -aG docker $USER</code> 후 다시 로그인 (6-5절 실제 로그) |
| 소켓은 있는데 다른 주소로 연결을 시도함 | <code>DOCKER_HOST</code> 변수나 다른 컨텍스트가 지정됨 | <code>echo $DOCKER_HOST</code>, <code>docker context ls</code> → <code>unset DOCKER_HOST</code>, <code>docker context use default</code> |
| <code>systemctl start docker</code> 자체가 실패 | 데몬 설정·저장소 오류 등 | <code>sudo journalctl -u docker --no-pager -n 50</code>으로 원인 확인 |

### Case 4: /mnt/c에서 chmod가 반영되지 않음

Windows NTFS를 WSL에 연결한 <code>/mnt/c</code>에서는 마운트 설정에 따라 Linux POSIX 권한 메타데이터가 보존되지 않을 수 있습니다. <code>df -T .</code>와 <code>mount | grep '/mnt/c'</code>로 파일 시스템을 확인하고, 권한 실습은 <code>/home/&lt;사용자&gt;</code> 아래로 옮겨 재수행합니다. 5절의 644 → 755, 755 → 700 출력이 해결 후 증거입니다.

## 11. 화면 증거

![VS Code에서 확인한 Dockerfile과 app 디렉터리](./screenshots/container-webserver.png)

화면 캡처는 보조 증거이며, 재현 가능한 명령과 텍스트 출력은 본문에 함께 기록했습니다.

## 12. 보너스 과제 (선택)

> **실행 환경 안내**: 4·5·8절과 10절 Git 로그는 작성자 Windows 11 PC(WSL2 Ubuntu 22.04)에서, 6·7절과 이 절의 로그는 2026-11-07 클라우드 Linux 검증 환경(Ubuntu 24.04.5 LTS, Docker Compose v5.7.0. Docker Engine은 이 절 29.9.2, 6·7절 29.9.3)에서 실제로 실행한 출력입니다. 두 환경 모두 같은 <code>nginx/1.31.8</code>이 응답했습니다. Compose 파일은 상대경로만 쓰므로 6절대로 WSL2 Ubuntu에 설치한 Docker Engine에서도 같은 명령으로 실행됩니다.
> 실행마다 바뀌는 값(컨테이너 ID, 내부 IP, 시각, 이미지 digest)은 비교 대상이 아닙니다. 컨테이너 안의 시각은 UTC입니다.

| 과제 | 사용 파일 | 호스트 포트 | 핵심 확인 |
|---|---|---|---|
| 12-1 Compose 기초 | [compose/single/docker-compose.yml](./compose/single/docker-compose.yml) | 8090 | 명령 한 줄로 빌드·실행, HTTP 200, healthy |
| 12-2 멀티 컨테이너 | [compose/multi/docker-compose.yml](./compose/multi/docker-compose.yml) | 8091 | checker가 서비스 이름 <code>web</code>으로 통신 |
| 12-3 운영 명령어 | 12-2와 같은 파일 | 8091 | up·ps·logs·down과 장애 감지 루틴 |
| 12-4 환경 변수 | [compose/env/](./compose/env/docker-compose.yml) | 8092 → 9090 | 코드 수정 없이 포트·모드 변경 |
| 12-5 SSH 키 | GitHub 계정 설정 | - | <code>ssh -T</code> 인증, SSH 원격으로 push |

호스트 포트는 7~9절에서 쓰는 8080·8081·8082와 겹치지 않게 골랐습니다.

### 12-1. Docker Compose 기초: 단일 서비스

<code>docker-compose.yml</code>의 기본 구조:

| 최상위 키 | 의미 |
|---|---|
| <code>name</code> | 프로젝트 이름. 컨테이너·네트워크 이름 앞에 붙습니다(예: <code>mission-single-web-1</code>). 고정해 두면 저장소를 어떤 폴더 이름으로 clone해도 이름이 같습니다. |
| <code>services</code> | 실행할 컨테이너 목록. 키 이름(<code>web</code>)이 서비스 이름입니다. |
| <code>networks</code>, <code>volumes</code> | 선택 항목. 사용자 정의 네트워크·볼륨을 선언합니다. |

예전 문서의 <code>version:</code> 키는 Compose v2부터 쓰지 않으므로 넣지 않았습니다.

7절의 <code>docker</code> 명령과 Compose 키의 대응:

| 7절 명령 | Compose |
|---|---|
| <code>docker build -t custom-nginx:1.0 .</code> | <code>build.context: ../..</code> + <code>image: custom-nginx:1.0</code> |
| <code>--name web-server</code> | 서비스 이름 <code>web</code> → 컨테이너 <code>mission-single-web-1</code> |
| <code>-p 8080:80</code> | <code>ports: ["8090:80"]</code> |
| <code>-d</code> | <code>docker compose up -d</code> |
| <code>docker stop</code> + <code>docker rm</code> | <code>docker compose down</code> (기본 네트워크까지 삭제) |

[compose/single/docker-compose.yml](./compose/single/docker-compose.yml)의 내용:

~~~yaml
# 보너스 1. Docker Compose 기초 - 단일 서비스
#
# 7절의 아래 명령을 "문서화된 실행 설정"으로 옮긴 파일입니다.
#   docker build -t custom-nginx:1.0 .
#   docker run -d --name web-server -p 8080:80 custom-nginx:1.0
#
# 실행 위치: 이 파일이 있는 compose/single/
#   docker compose up -d --build

# 프로젝트 이름을 고정해 폴더 이름과 관계없이 컨테이너·네트워크 이름이 같게 만듭니다.
name: mission-single

services:
  web:                      # 서비스 이름 (docker run --name 역할)
    build:
      context: ../..        # 저장소 루트 (docker build . 의 '.')
      dockerfile: Dockerfile
    image: custom-nginx:1.0 # 빌드 결과 태그 (docker build -t)
    ports:
      - "8090:80"           # 호스트:컨테이너 (docker run -p). 7절 8080과 겹치지 않게 8090 사용
~~~

재현 명령:

~~~bash
cd ~/buildergarlic-codyssey/compose/single
docker compose config
docker compose up -d --build
docker compose ps
curl -sS -i http://localhost:8090
sleep 35
docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
docker compose down
docker compose ps -a
~~~

실제 실행 로그:

~~~console
[2026-11-07 18:21 KST, 클라우드 Linux 검증 환경]

$ cd ~/buildergarlic-codyssey/compose/single

$ docker compose config
name: mission-single
services:
  web:
    image: custom-nginx:1.0
    networks:
      default: null
    build:
      context: /root/buildergarlic-codyssey
      dockerfile: Dockerfile
    ports:
      - mode: ingress
        target: 80
        published: "8090"
        protocol: tcp
networks:
  default:
    name: mission-single_default

$ docker compose up -d --build
 Image custom-nginx:1.0 Building
   … BuildKit 빌드 단계 출력 생략 (13-5절 docker build 로그와 같은 단계) …
 Image custom-nginx:1.0 Built
 Network mission-single_default Creating
 Network mission-single_default Creating
 Network mission-single_default Created
 Network mission-single_default Created
 Container mission-single-web-1 Creating
 Container mission-single-web-1 Created
 Container mission-single-web-1 Starting
 Container mission-single-web-1 Started

$ docker compose ps
NAME                   IMAGE              COMMAND                  SERVICE   CREATED                  STATUS                                     PORTS
mission-single-web-1   custom-nginx:1.0   "/docker-entrypoint.…"   web       Less than a second ago   Up Less than a second (health: starting)   0.0.0.0:8090->80/tcp

$ curl -sS -i http://localhost:8090
HTTP/1.1 200 OK
Server: nginx/1.31.8
Date: Sat, 07 Nov 2026 09:21:37 GMT
Content-Type: text/html
Content-Length: 280
Last-Modified: Sat, 07 Nov 2026 09:21:27 GMT
Connection: keep-alive
ETag: "6aeeed97-118"
Accept-Ranges: bytes

<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Workstation Mission</title>
</head>
<body>
  <h1>Custom Nginx Container on Windows 11 (WSL2)</h1>
  <p>Version 1.0</p>
</body>
</html>

$ sleep 35

$ docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
NAME                   STATUS                    PORTS
mission-single-web-1   Up 35 seconds (healthy)   0.0.0.0:8090->80/tcp

$ docker compose down
 Container mission-single-web-1 Stopping
 Container mission-single-web-1 Stopped
 Container mission-single-web-1 Removing
 Container mission-single-web-1 Removed
 Network mission-single_default Removing
 Network mission-single_default Removed

$ docker compose ps -a
NAME      IMAGE     COMMAND   SERVICE   CREATED   STATUS    PORTS
~~~

<code>docker compose config</code>에서 <code>context: ../..</code>가 실행한 PC의 절대경로로 바뀌었고, 같은 이미지가 HTTP 200과 <code>(healthy)</code>로 응답한 뒤 <code>down</code>으로 컨테이너와 네트워크가 모두 정리되었습니다.

**배움 포인트: 실행 명령이 “문서화된 실행 설정”으로 바뀌는 이유**

- <code>docker run</code>의 옵션은 실행한 사람의 셸 기록에만 남습니다. 다음 사람은 포트·이름·빌드 경로를 다시 기억해서 입력해야 하고, 옵션 하나만 빠져도 결과가 달라집니다.
- Compose 파일은 그 옵션을 저장소에 커밋되는 텍스트로 만듭니다. 리뷰하고, 변경 이력을 남기고, 누구나 <code>docker compose up</code> 한 줄로 같은 설정을 실행할 수 있습니다.
- <code>docker compose config</code>로 변수와 상대경로가 해석된 최종 설정을 실행 전에 확인할 수 있습니다.

### 12-2. Docker Compose 멀티 컨테이너

~~~text
[호스트] --(8091:80)--> [web: custom-nginx:1.0, 컨테이너 포트 80]
                                  ▲
                                  │  wget http://web/  (5초마다, 서비스 이름으로 접속)
                                  │
                         [checker: alpine:3.22]

※ web과 checker는 모두 mission-multi_mission-net 네트워크에 연결됨
~~~

- <code>web</code>: 7절과 같은 커스텀 Nginx 이미지
- <code>checker</code>: 보조 서비스. 같은 네트워크에서 서비스 이름 <code>web</code>으로 5초마다 접속해 OK/FAIL을 로그로 남깁니다.
- <code>depends_on.condition: service_healthy</code>로 web이 healthy가 된 다음에 checker가 시작됩니다.

[compose/multi/docker-compose.yml](./compose/multi/docker-compose.yml)의 내용:

~~~yaml
# 보너스 2·3. Docker Compose 멀티 컨테이너 + 운영 명령어
#
# web     : 7절의 커스텀 Nginx 이미지 (호스트 8091 → 컨테이너 80)
# checker : 보조 서비스. 같은 네트워크에서 서비스 이름 "web"으로 5초마다 접속해 결과를 로그로 남김
#
# 실행 위치: 이 파일이 있는 compose/multi/
#   docker compose up -d --build

name: mission-multi

services:
  web:
    build:
      context: ../..
      dockerfile: Dockerfile
    image: custom-nginx:1.0
    ports:
      - "8091:80"
    networks:
      - mission-net
    # Dockerfile의 HEALTHCHECK(30초 간격)를 Compose에서 덮어써 빠르게 healthy 판정을 받습니다.
    # localhost가 IPv6(::1)로 해석되는 환경 차이를 피하려고 127.0.0.1을 명시합니다.
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1/ > /dev/null || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 5s

  checker:
    image: alpine:3.22
    depends_on:
      web:
        condition: service_healthy   # web이 healthy가 된 뒤에 시작
    networks:
      - mission-net
    # $$ 는 Compose 변수 치환을 막고 컨테이너 셸에 $ 를 그대로 넘기는 표기입니다.
    command:
      - sh
      - -c
      - |
        while true; do
          if wget -qO- http://web/ | grep -q "Custom Nginx"; then
            echo "$$(date '+%F %T') checker -> http://web/ : OK"
          else
            echo "$$(date '+%F %T') checker -> http://web/ : FAIL"
          fi
          sleep 5
        done

networks:
  mission-net: {}   # 실제 이름: mission-multi_mission-net
~~~

재현 명령:

~~~bash
cd ~/buildergarlic-codyssey/compose/multi
docker compose up -d --build
sleep 10
docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}'
docker compose logs --tail 3 checker
docker network inspect mission-multi_mission-net --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'
docker compose exec checker nslookup web
docker compose exec checker wget -qO- http://web/
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8091
curl -sS http://web/
~~~

실제 실행 로그:

~~~console
[2026-11-07 18:22 KST, 클라우드 Linux 검증 환경]

$ cd ~/buildergarlic-codyssey/compose/multi

$ docker compose up -d --build
 Image alpine:3.22 Pulling
 710f3da1112f Pulling fs layer 0B
 41efde5237a6 Download complete 0B
 f270d3a86df5 Download complete 0B
 710f3da1112f Downloading 2.097MB
 710f3da1112f Download complete 0B
 710f3da1112f Pull complete 0B
 Image alpine:3.22 Pulled
 Image custom-nginx:1.0 Building
   … BuildKit 빌드 단계 출력 생략 (13-5절 docker build 로그와 같은 단계) …
 Image custom-nginx:1.0 Built
 Network mission-multi_mission-net Creating
 Network mission-multi_mission-net Creating
 Network mission-multi_mission-net Created
 Network mission-multi_mission-net Created
 Container mission-multi-web-1 Creating
 Container mission-multi-web-1 Created
 Container mission-multi-checker-1 Creating
 Container mission-multi-checker-1 Created
 Container mission-multi-web-1 Starting
 Container mission-multi-web-1 Started
 Container mission-multi-web-1 Waiting
 Container mission-multi-web-1 Healthy
 Container mission-multi-checker-1 Starting
 Container mission-multi-checker-1 Started

$ sleep 10

$ docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}'
NAME                      SERVICE   STATUS                    PORTS
mission-multi-checker-1   checker   Up 10 seconds
mission-multi-web-1       web       Up 15 seconds (healthy)   0.0.0.0:8091->80/tcp

$ docker compose logs --tail 3 checker
checker-1  | 2026-11-07 09:22:20 checker -> http://web/ : OK
checker-1  | 2026-11-07 09:22:25 checker -> http://web/ : OK
checker-1  | 2026-11-07 09:22:30 checker -> http://web/ : OK

$ docker network inspect mission-multi_mission-net --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'
mission-multi-web-1 172.18.0.2/16
mission-multi-checker-1 172.18.0.3/16

$ docker compose exec checker nslookup web
Server:		127.0.0.11
Address:	127.0.0.11:53

Non-authoritative answer:
Name:	web
Address: 172.18.0.2

Non-authoritative answer:

$ docker compose exec checker wget -qO- http://web/
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Workstation Mission</title>
</head>
<body>
  <h1>Custom Nginx Container on Windows 11 (WSL2)</h1>
  <p>Version 1.0</p>
</body>
</html>

$ curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8091
HTTP 200

$ curl -sS http://web/
curl: (6) Could not resolve host: web
~~~

확인 결과:

- <code>up</code> 로그의 <code>web-1 Waiting → Healthy → checker-1 Starting</code> 순서로 시작 순서가 지켜졌습니다.
- checker 안에서 <code>nslookup web</code>을 실행하자 Docker 내장 DNS(<code>127.0.0.11</code>)가 web의 IP(<code>docker network inspect</code> 결과와 같은 <code>172.18.0.2</code>)를 돌려주었고, <code>wget http://web/</code>으로 HTML을 받았습니다. 두 번째 빈 <code>Non-authoritative answer</code>는 IPv6(AAAA) 주소가 없다는 뜻입니다.
- 호스트에서는 포트 매핑(8091)으로만 접속되고, 서비스 이름 <code>web</code>은 해석되지 않았습니다(<code>Could not resolve host: web</code>).

**배움 포인트: 네트워크와 서비스 디스커버리**

- Compose는 프로젝트마다 전용 네트워크(<code>mission-multi_mission-net</code>)를 만들고, 그 안의 컨테이너는 서비스 이름으로 서로를 찾습니다. 컨테이너 IP는 다시 만들 때마다 바뀔 수 있지만 이름은 그대로라서 설정에 IP를 적을 필요가 없습니다.
- 컨테이너끼리는 컨테이너 포트(<code>web:80</code>)로 통신합니다. 호스트 포트 8091은 네트워크 바깥(호스트)에서 들어오기 위한 입구입니다.
- 서비스 이름은 그 네트워크 안에서만 통합니다. 6절의 네트워크 네임스페이스 설명과 같은 원리입니다.

### 12-3. Compose 운영 명령어

| 명령 | 용도 | 볼 것 |
|---|---|---|
| <code>docker compose up -d [--build]</code> | 생성·시작. 설정이 바뀐 서비스는 다시 만듭니다. | <code>Started</code>, <code>Recreated</code> |
| <code>docker compose ps [-a]</code> | 상태 조회 (<code>-a</code>: 종료된 컨테이너 포함) | <code>STATE</code>, <code>(healthy)</code>, <code>PORTS</code> |
| <code>docker compose logs [--tail N] [-f] [서비스]</code> | 로그 조회 | 에러, FAIL, 요청 기록 |
| <code>docker compose stop</code> / <code>start [서비스]</code> | 컨테이너를 지우지 않고 중지·재시작 | <code>exited</code> ↔ <code>running</code> |
| <code>docker compose down</code> | 중지 + 컨테이너·네트워크 삭제 | <code>ps -a</code>가 빈 목록 |

**상태 확인 루틴**

1. <code>ps</code>: 모든 서비스가 <code>running</code>이고, healthcheck가 있는 서비스는 <code>(healthy)</code>인가?
2. <code>logs --tail</code>: 최근 로그에 에러나 FAIL이 없는가?
3. 이상이 있으면 해당 서비스만 조치(<code>stop</code>/<code>start</code>/<code>up -d</code>)한 뒤 1~2번을 다시 확인한다.
4. 작업이 끝나면 <code>down</code>으로 정리한다.
5. <code>ps -a</code>와 <code>docker network ls</code>로 남은 리소스가 없는지 확인한다.

12-2의 컨테이너가 실행 중인 상태에서 이어서 실행합니다.

~~~bash
cd ~/buildergarlic-codyssey/compose/multi
# 1) 상태와 최근 로그 확인
docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
docker compose logs --tail 3 web
# 2) 장애 상황 재현: web만 중지
docker compose stop web
sleep 11
docker compose ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
docker compose logs --tail 2 checker
# 3) 복구 후 재확인
docker compose start web
sleep 11
docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
docker compose logs --tail 2 checker
# 4) 종료와 잔여 리소스 확인
docker compose down
docker compose ps -a
docker network ls --filter name=mission-multi
~~~

실제 실행 로그:

~~~console
[2026-11-07 18:22 KST, 클라우드 Linux 검증 환경]

$ cd ~/buildergarlic-codyssey/compose/multi

# 1) 상태와 최근 로그 확인
$ docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
SERVICE   STATE     STATUS
checker   running   Up 10 seconds
web       running   Up 15 seconds (healthy)

$ docker compose logs --tail 3 web
web-1  | 172.18.0.3 - - [07/Nov/2026:09:22:30 +0000] "GET / HTTP/1.1" 200 280 "-" "Wget" "-"
web-1  | 172.18.0.3 - - [07/Nov/2026:09:22:30 +0000] "GET / HTTP/1.1" 200 280 "-" "Wget" "-"
web-1  | 172.18.0.1 - - [07/Nov/2026:09:22:30 +0000] "GET / HTTP/1.1" 200 280 "-" "curl/8.5.0" "-"

# 2) 장애 상황 재현: web만 중지
$ docker compose stop web
 Container mission-multi-web-1 Stopping
 Container mission-multi-web-1 Stopped

$ sleep 11

$ docker compose ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
SERVICE   STATE     STATUS
checker   running   Up 21 seconds
web       exited    Exited (0) 11 seconds ago

$ docker compose logs --tail 2 checker
checker-1  | wget: bad address 'web'
checker-1  | 2026-11-07 09:22:40 checker -> http://web/ : FAIL

# 3) 복구 후 재확인
$ docker compose start web
 Container mission-multi-web-1 Starting
 Container mission-multi-web-1 Started

$ sleep 11

$ docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
SERVICE   STATE     STATUS
checker   running   Up 33 seconds
web       running   Up 11 seconds (healthy)

$ docker compose logs --tail 2 checker
checker-1  | 2026-11-07 09:22:45 checker -> http://web/ : OK
checker-1  | 2026-11-07 09:22:50 checker -> http://web/ : OK

# 4) 종료와 잔여 리소스 확인
$ docker compose down
 Container mission-multi-checker-1 Stopping
 Container mission-multi-checker-1 Stopped
 Container mission-multi-checker-1 Removing
 Container mission-multi-checker-1 Removed
 Container mission-multi-web-1 Stopping
 Container mission-multi-web-1 Stopped
 Container mission-multi-web-1 Removing
 Container mission-multi-web-1 Removed
 Network mission-multi_mission-net Removing
 Network mission-multi_mission-net Removed

$ docker compose ps -a
NAME      IMAGE     COMMAND   SERVICE   CREATED   STATUS    PORTS

$ docker network ls --filter name=mission-multi
NETWORK ID   NAME      DRIVER    SCOPE
~~~

web을 멈추자 <code>ps -a</code>에 <code>exited</code>가 보이고 checker 로그에 <code>bad address 'web'</code>과 FAIL이 남았습니다. web을 다시 시작하자 <code>(healthy)</code>와 OK로 돌아왔고, <code>down</code> 후에는 컨테이너와 네트워크가 모두 사라졌습니다.

**배움 포인트: 운영 관점의 “상태 확인 루틴”**

- <code>ps</code>는 “살아 있는가”, <code>logs</code>는 “제대로 일하는가”를 알려줍니다. 컨테이너가 <code>running</code>이어도 로그에는 FAIL이 쌓일 수 있으므로 둘을 함께 봅니다.
- 문제가 생긴 서비스만 골라 조치하고, 같은 루틴으로 복구를 확인합니다.
- 마지막에 <code>down</code>과 잔여 리소스 확인까지 해야 다음 실습에서 포트 충돌(9절)이 생기지 않습니다.

### 12-4. 환경 변수 활용

이미지와 HTML은 그대로 두고, 아래 세 값만 바꿔 서버 동작을 바꿉니다.

| 변수 | 기본값 | <code>.env.example</code> 값 | 쓰이는 곳 |
|---|---|---|---|
| <code>WEB_PORT</code> | 8092 | 9090 | <code>ports</code>의 호스트 쪽 |
| <code>NGINX_PORT</code> | 80 | 8088 | <code>ports</code>의 컨테이너 쪽, Nginx <code>listen</code>, healthcheck |
| <code>APP_MODE</code> | development | production | 응답 헤더 <code>X-App-Mode</code>, <code>/mode</code> 응답 |

값의 우선순위: **셸 환경 변수 > <code>compose/env/.env</code> 파일 > Compose 파일의 <code>${변수:-기본값}</code>**

[compose/env/docker-compose.yml](./compose/env/docker-compose.yml):

~~~yaml
# 보너스 4. 환경 변수로 포트/모드 바꾸기 (설정과 코드의 분리)
#
# 이미지와 HTML(코드)은 그대로 두고, 아래 3개 값만 바꿔 서버 동작을 바꿉니다.
#   WEB_PORT   : 호스트 포트          (기본 8092)
#   NGINX_PORT : 컨테이너 Nginx 포트  (기본 80)
#   APP_MODE   : 실행 모드 표시값      (기본 development)
#
# 값의 우선순위: 셸 환경 변수 > 이 폴더의 .env 파일 > 아래 ${변수:-기본값}
#
# 실행 위치: 이 파일이 있는 compose/env/
#   docker compose up -d --build                 # 기본값으로 실행
#   cp .env.example .env && docker compose up -d # .env 값으로 다시 실행

name: mission-env

services:
  web:
    build:
      context: ../..
      dockerfile: Dockerfile
    image: custom-nginx:1.0
    environment:
      NGINX_PORT: ${NGINX_PORT:-80}
      APP_MODE: ${APP_MODE:-development}
    ports:
      - "${WEB_PORT:-8092}:${NGINX_PORT:-80}"
    volumes:
      # nginx 공식 이미지는 시작할 때 /etc/nginx/templates/*.template 안의 ${변수}를
      # 환경 변수 값으로 바꿔 /etc/nginx/conf.d/ 에 설정 파일을 만듭니다.
      - ./nginx/default.conf.template:/etc/nginx/templates/default.conf.template:ro
    # Dockerfile의 HEALTHCHECK는 80 포트 고정이므로, 바뀐 포트를 검사하도록 덮어씁니다.
    # $$NGINX_PORT 는 Compose가 아니라 컨테이너 셸이 해석합니다.
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:$${NGINX_PORT}/ > /dev/null || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 5s
~~~

[compose/env/.env.example](./compose/env/.env.example):

~~~ini
# 사용법: cp .env.example .env  (.env 는 .gitignore로 커밋에서 제외)
# 값을 바꾼 뒤 docker compose up -d 를 다시 실행하면 컨테이너가 새 설정으로 재생성됩니다.
WEB_PORT=9090
NGINX_PORT=8088
APP_MODE=production
~~~

[compose/env/nginx/default.conf.template](./compose/env/nginx/default.conf.template): nginx 공식 이미지는 시작할 때 <code>/etc/nginx/templates/*.template</code>의 <code>${변수}</code>를 환경 변수 값으로 바꿔 <code>/etc/nginx/conf.d/</code>에 설정 파일을 만듭니다.

~~~nginx
# 보너스 4용 Nginx 설정 템플릿
# ${NGINX_PORT}, ${APP_MODE}는 컨테이너 시작 시 환경 변수 값으로 치환됩니다.
server {
    listen       ${NGINX_PORT};
    server_name  localhost;

    # 모든 응답에 현재 모드를 헤더로 표시
    add_header X-App-Mode "${APP_MODE}" always;

    location / {
        root   /usr/share/nginx/html;
        index  index.html;
    }

    # 현재 적용된 설정값을 확인하는 엔드포인트
    location = /mode {
        default_type text/plain;
        return 200 "mode=${APP_MODE} listen=${NGINX_PORT}\n";
    }
}
~~~

재현 명령:

~~~bash
cd ~/buildergarlic-codyssey/compose/env
# (1) 기본값으로 실행 (.env 없음)
ls -A
docker compose up -d --build
sleep 10
docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
curl -sS -i http://localhost:8092/mode
docker compose logs web | grep envsubst
# (2) 코드는 그대로 두고 .env 값만 바꿔 재실행
cp .env.example .env
grep -v '^#' .env
docker compose up -d
sleep 10
docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
curl -sS -i http://localhost:9090/mode
curl -sS -D - -o /dev/null http://localhost:9090/ | grep -E 'HTTP/|X-App-Mode'
docker compose exec web sh -c 'printenv NGINX_PORT APP_MODE; grep -E "listen|X-App-Mode" /etc/nginx/conf.d/default.conf'
curl -sS http://localhost:8092/mode
# (3) 우선순위 확인: 셸 환경 변수 > .env
APP_MODE=staging docker compose config | grep APP_MODE
docker compose down
rm .env
~~~

실제 실행 로그:

~~~console
[2026-11-07 18:23 KST, 클라우드 Linux 검증 환경]

$ cd ~/buildergarlic-codyssey/compose/env

# (1) 기본값으로 실행 (.env 없음)
$ ls -A
.env.example
docker-compose.yml
nginx

$ docker compose up -d --build
 Image custom-nginx:1.0 Building
   … BuildKit 빌드 단계 출력 생략 (13-5절 docker build 로그와 같은 단계) …
 Image custom-nginx:1.0 Built
 Network mission-env_default Creating
 Network mission-env_default Creating
 Network mission-env_default Created
 Network mission-env_default Created
 Container mission-env-web-1 Creating
 Container mission-env-web-1 Created
 Container mission-env-web-1 Starting
 Container mission-env-web-1 Started

$ sleep 10

$ docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
SERVICE   STATUS                    PORTS
web       Up 10 seconds (healthy)   0.0.0.0:8092->80/tcp

$ curl -sS -i http://localhost:8092/mode
HTTP/1.1 200 OK
Server: nginx/1.31.8
Date: Sat, 07 Nov 2026 09:23:15 GMT
Content-Type: text/plain
Content-Length: 27
Connection: keep-alive
X-App-Mode: development

mode=development listen=80

$ docker compose logs web | grep envsubst
web-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
web-1  | 20-envsubst-on-templates.sh: Running envsubst on /etc/nginx/templates/default.conf.template to /etc/nginx/conf.d/default.conf

# (2) 코드는 그대로 두고 .env 값만 바꿔 재실행
$ cp .env.example .env

$ grep -v '^#' .env
WEB_PORT=9090
NGINX_PORT=8088
APP_MODE=production

$ docker compose up -d
 Container mission-env-web-1 Recreate
 Container mission-env-web-1 Recreated
 Container mission-env-web-1 Starting
 Container mission-env-web-1 Started

$ sleep 10

$ docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
SERVICE   STATUS                    PORTS
web       Up 10 seconds (healthy)   80/tcp, 0.0.0.0:9090->8088/tcp

$ curl -sS -i http://localhost:9090/mode
HTTP/1.1 200 OK
Server: nginx/1.31.8
Date: Sat, 07 Nov 2026 09:23:25 GMT
Content-Type: text/plain
Content-Length: 28
Connection: keep-alive
X-App-Mode: production

mode=production listen=8088

$ curl -sS -D - -o /dev/null http://localhost:9090/ | grep -E 'HTTP/|X-App-Mode'
HTTP/1.1 200 OK
X-App-Mode: production

$ docker compose exec web sh -c 'printenv NGINX_PORT APP_MODE; grep -E "listen|X-App-Mode" /etc/nginx/conf.d/default.conf'
8088
production
    listen       8088;
    add_header X-App-Mode "production" always;
        return 200 "mode=production listen=8088\n";

$ curl -sS http://localhost:8092/mode
curl: (7) Failed to connect to localhost port 8092 after 0 ms: Couldn't connect to server

# (3) 우선순위 확인: 셸 환경 변수 > .env
$ APP_MODE=staging docker compose config | grep APP_MODE
      APP_MODE: staging

$ docker compose down
 Container mission-env-web-1 Stopping
 Container mission-env-web-1 Stopped
 Container mission-env-web-1 Removing
 Container mission-env-web-1 Removed
 Network mission-env_default Removing
 Network mission-env_default Removed

$ rm .env
~~~

확인 결과:

- 기본값에서는 <code>8092→80</code>, <code>mode=development</code>였고, <code>.env</code>만 바꾼 뒤에는 컨테이너가 <code>Recreate</code>되며 <code>9090→8088</code>, <code>mode=production</code>으로 바뀌었습니다. 이전 포트 8092는 더 이상 열려 있지 않습니다.
- 컨테이너 안의 실제 Nginx 설정에 <code>listen 8088;</code>과 <code>production</code>이 들어간 것을 확인했습니다.
- <code>APP_MODE=staging</code>처럼 셸에서 준 값이 <code>.env</code>의 <code>production</code>보다 우선했습니다.
- <code>PORTS</code>에 남은 <code>80/tcp</code>는 Dockerfile <code>EXPOSE 80</code>의 기록일 뿐이며, 실제 공개는 <code>9090->8088</code>입니다(6절 설명과 같은 맥락).

**배움 포인트: 설정과 코드의 분리**

- 같은 이미지(<code>custom-nginx:1.0</code>)를 다시 빌드하지 않고 포트와 모드만 바꿨습니다. 설정이 코드 밖에 있으면 개발·운영 환경이나 PC가 달라도 이미지 하나로 대응할 수 있습니다.
- 실제 <code>.env</code>는 PC마다 다르고 비밀값이 들어갈 수 있으므로 [.gitignore](./.gitignore)로 커밋에서 빼고, 어떤 키가 필요한지는 <code>.env.example</code>로 공유합니다. [.dockerignore](./.dockerignore)에도 <code>.env</code>를 넣어 이미지에 섞여 들어가지 않게 했습니다.

### 12-5. GitHub SSH 키 설정

> **실행 상태**: 이 과제는 작성자의 GitHub 계정에 공개키를 등록해야 하고, 위 클라우드 검증 환경은 외부 SSH 접속(22번 포트)이 막혀 있어 직접 실행하지 못했습니다. 아래는 작성자 PC(WSL2 Ubuntu)에서 실행할 절차와 통과 기준입니다. 실행 후 출력은 맨 아래 “실제 실행 로그” 자리에 붙입니다.

HTTPS와 SSH의 차이:

| 구분 | HTTPS (10절 현재 방식) | SSH |
|---|---|---|
| 원격 주소 | <code>https://github.com/buildergarlic/buildergarlic-codyssey.git</code> | <code>git@github.com:buildergarlic/buildergarlic-codyssey.git</code> |
| 인증 수단 | GitHub 계정 + 토큰(Git Credential Manager가 보관) | 내 PC의 개인키 + GitHub에 등록한 공개키 |
| 네트워크로 보내는 것 | 토큰 | 개인키는 보내지 않고, 개인키로 만든 서명만 보냄 |
| 포트 | 443 | 22 (막힌 곳에서는 <code>ssh.github.com:443</code>) |
| 폐기 방법 | 토큰 revoke | GitHub에서 해당 키 삭제 |

재현 절차 (WSL2 Ubuntu):

~~~bash
# 1. 기존 키 확인 (id_ed25519가 이미 있으면 2단계는 건너뛰거나 다른 파일 이름 사용)
ls -al ~/.ssh

# 2. 키 생성: 저장 경로는 Enter(기본값), passphrase는 입력 권장
ssh-keygen -t ed25519 -C "nobody@nobody.com"

# 3. 권한 확인 (5절: 디렉터리 700, 개인키 600, 공개키 644)
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
ls -ld ~/.ssh
ls -l ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub

# 4. ssh-agent에 개인키 등록 (passphrase를 매번 입력하지 않도록)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 5. 공개키를 Windows 클립보드로 복사한 뒤
#    GitHub → Settings → SSH and GPG keys → New SSH key → Key type: Authentication Key → 붙여넣기
cat ~/.ssh/id_ed25519.pub | clip.exe

# 6. 연결 테스트
ssh -T git@github.com

# 7. 원격 주소를 SSH로 바꾸고 push
cd ~/buildergarlic-codyssey
git remote set-url origin git@github.com:buildergarlic/buildergarlic-codyssey.git
git remote -v
git push -u origin main
~~~

통과 기준:

| 단계 | 기대 결과 |
|---|---|
| 3 | <code>drwx------ … /home/&lt;사용자&gt;/.ssh</code>, 개인키 <code>-rw-------</code>, 공개키 <code>-rw-r--r--</code> |
| 6 (처음) | <code>ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.</code> 질문이 나오면 [GitHub 공식 값](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)과 같은지 확인한 뒤에만 <code>yes</code> |
| 6 | <code>Hi buildergarlic! You've successfully authenticated, but GitHub does not provide shell access.</code> |
| 7 | <code>git remote -v</code>가 <code>git@github.com:buildergarlic/buildergarlic-codyssey.git</code>를 표시하고, <code>git push</code>가 토큰·비밀번호 입력 없이 끝남 |

학교·회사 네트워크에서 22번 포트가 막혀 6단계가 시간 초과되면 <code>~/.ssh/config</code>에 아래를 추가하고 다시 시도합니다([GitHub 안내](https://docs.github.com/en/authentication/troubleshooting-ssh/using-ssh-over-the-https-port)).

~~~text
Host github.com
  Hostname ssh.github.com
  Port 443
  User git
~~~

**배움 포인트: 인증 방식 차이와 보안 습관**

- 개인키(<code>id_ed25519</code>)는 커밋·메신저·스크린샷 어디에도 올리지 않습니다. 공유하는 것은 <code>.pub</code> 공개키뿐입니다.
- passphrase를 걸어 두면 개인키 파일이 유출되어도 바로 쓰이지 않습니다. 입력 부담은 ssh-agent로 줄입니다.
- 첫 접속 때 fingerprint를 공식 값과 비교하는 것은 가짜 서버(중간자 공격)를 걸러내는 단계입니다.
- PC마다 키를 따로 만들고 GitHub 키 Title에 PC 이름을 적어 두면, PC를 잃어버리거나 바꿀 때 그 키만 삭제할 수 있습니다. 공용 실습 PC에서 만든 키는 실습 후 GitHub에서 삭제합니다.

실제 실행 로그 (작성자 PC에서 6·7단계 실행 후 추가):

~~~console
(미실행 — 작성자 WSL2에서 ssh -T git@github.com, git remote -v, git push 출력을 붙여 넣습니다)
~~~

## 13. 재현 가이드 (평가자용)

이 README만 보고 처음부터 같은 결과를 확인하기 위한 절차입니다.

### 13-1. 준비 상태 확인

| 항목 | 확인 명령 | 기준 |
|---|---|---|
| Docker 데몬 | <code>docker version --format '{{.Server.Version}}'</code> | 버전이 출력되면 데몬 연결 정상 (29.9.2·29.9.3에서 검증). 오류는 10절 Case 3 |
| Docker 실행 권한 | <code>docker ps</code> | sudo 없이 표 머리글이 출력되면 정상. <code>permission denied</code>면 6-5절 |
| Docker Compose v2 | <code>docker compose version</code> | v2 이상. 하이픈이 들어간 옛 <code>docker-compose</code>(v1)는 쓰지 않습니다. |
| Git, curl | <code>git --version</code>, <code>curl --version</code> | 출력되면 정상 |
| 빈 포트 | 8080, 8081, 8090, 8091, 8092, 9090 | 사용 중이면 9절 순서로 확인·해제하거나 호스트 포트만 바꿉니다. |

- **Windows 11**: 2절대로 WSL2 Ubuntu를 설치하고, Ubuntu 터미널에서 6-2절 0~6단계로 Docker Engine을 설치한 뒤, PowerShell이 아니라 **WSL2 Ubuntu 터미널**에서 아래 명령을 실행합니다. Docker가 Ubuntu 안에 있으므로 PowerShell에서는 <code>docker</code> 명령을 쓸 수 없습니다.
- **Ubuntu (WSL 아님)**: 6-2절 1~6단계(0단계 제외)를 그대로 실행한 뒤 같은 명령을 씁니다.
- **macOS**: Linux용 Docker Engine을 직접 설치할 수 없으므로 OrbStack 등 Docker 호환 런타임을 설치한 뒤 같은 명령을 씁니다.

### 13-2. 처음부터 따라 하기

리눅스 홈 아래에 clone합니다. <code>/mnt/c</code> 아래는 권한·성능 문제가 있어 쓰지 않습니다(4·5절, 10절 Case 4).

~~~bash
cd ~
git clone https://github.com/buildergarlic/buildergarlic-codyssey.git
cd buildergarlic-codyssey
docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}'
docker compose version
# 7절: 이미지 빌드 → 실행 → 접속
docker build -t custom-nginx:1.0 .
docker run -d --name web-server -p 8080:80 custom-nginx:1.0
sleep 2
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080
docker rm -f web-server
# 8절: 바인드 마운트 (실습 후 원본 복구)
docker run -d --name bind-web -p 8081:80 -v "$(pwd)/app:/usr/share/nginx/html" custom-nginx:1.0
sleep 2
curl -sS http://localhost:8081 | grep Version
sed -i 's/Version 1.0/Version 2.0 (Bind Mounted on WSL2)/' app/index.html
curl -sS http://localhost:8081 | grep Version
git restore app/index.html
docker rm -f bind-web
# 8절: 볼륨 영속성
docker volume create mission-vol
docker run --name vol-writer -v mission-vol:/data alpine sh -c "echo 'Persistent Data Test 123' > /data/record.txt"
docker rm vol-writer
docker run --rm -v mission-vol:/data alpine cat /data/record.txt
~~~

이어서 12-1 → 12-2 → 12-3 → 12-4의 “재현 명령” 블록을 순서대로 실행하고, 마지막에 13-4로 정리합니다.

통과 기준:

| 단계 | 통과 기준 | 근거 절 |
|---|---|---|
| 7절 빌드·실행 | <code>HTTP 200</code> | 7절 |
| 바인드 마운트 | 다시 빌드하지 않아도 <code>Version 1.0</code> → <code>Version 2.0 (Bind Mounted on WSL2)</code> | 8절 |
| 볼륨 | 기록한 컨테이너를 삭제한 뒤 새 컨테이너에서 <code>Persistent Data Test 123</code> | 8절 |
| 12-1 | <code>curl</code> HTTP 200, <code>ps</code>에 <code>(healthy)</code>, <code>down</code> 후 빈 목록 | 12-1절 |
| 12-2 | checker 로그 OK, <code>nslookup web</code>이 IP 응답, 호스트에서 <code>web</code>은 해석 실패 | 12-2절 |
| 12-3 | web 중지 시 FAIL, 재시작 후 OK, <code>down</code> 후 네트워크까지 삭제 | 12-3절 |
| 12-4 | <code>/mode</code>가 <code>development listen=80</code> → <code>production listen=8088</code>, 셸 값 <code>staging</code> 우선 | 12-4절 |
| 12-5 | <code>ssh -T</code> 성공 메시지, SSH 원격으로 push | 12-5절 |

### 13-3. 작성자 PC에 종속된 값과 대체 방법

| 항목 | README에 나온 값 | 평가자 대체 방법·주의사항 |
|---|---|---|
| 작업 경로 | <code>/home/buildergarlic/workstation-mission</code> (4·5·8절 로그) | 작성자의 실습 폴더입니다. 평가자는 clone한 <code>~/buildergarlic-codyssey</code>에서 실행합니다. 명령은 저장소 루트 기준 상대경로(<code>.</code>, <code>./app</code>, <code>../..</code>)라 폴더 이름과 관계없이 동작합니다. |
| 사용자·호스트 이름 | <code>buildergarlic@GNIA-C202-A01</code> (부록 프롬프트), 파일 소유자 <code>buildergarlic</code> | 각자 계정명으로 표시됩니다(<code>whoami</code>, <code>hostname</code>). |
| Windows 경로 | <code>PS D:\buildergarlic-codyssey&gt;</code> (부록), 10절의 <code>PS&gt;</code> 로그 | 작성자가 D 드라이브에 clone해 PowerShell로 Git 명령을 실행한 기록입니다. Docker Engine은 Ubuntu 안에 설치되므로 Docker 명령은 모두 WSL2 Ubuntu 터미널에서, WSL2 홈 아래 clone한 저장소에서 실행합니다. |
| WSL 배포판 이름 | <code>Ubuntu-22.04</code> | <code>wsl -l -v</code>의 NAME과 VERSION 2를 확인하고 <code>wsl -d &lt;NAME&gt;</code>으로 들어가 6-2절을 실행합니다. 6-2절 5단계의 <code>wsl --terminate</code>에도 이 NAME을 씁니다. |
| Docker 저장소 코드네임 | <code>noble</code> (6-3절, Ubuntu 24.04) | WSL2 Ubuntu 22.04에서는 같은 명령이 <code>jammy</code>를 자동으로 넣습니다. 직접 입력하지 않습니다. |
| docker 그룹 사용자 | <code>mission</code> (6-5절 검증용 사용자) | 본인 계정에 <code>sudo usermod -aG docker $USER</code>를 적용합니다. 공용 PC는 실습 후 <code>sudo gpasswd -d $USER docker</code>로 제거합니다. |
| 데몬 시작 방법 | 검증 환경은 <code>dockerd</code> 직접 실행 (10절 Case 3) | 컨테이너 샌드박스 전용 대체입니다. WSL2에서는 <code>sudo systemctl enable --now docker</code>를 씁니다. |
| Git 사용자 정보 | <code>buildergarlic</code> / <code>nobody@nobody.com</code>(마스킹 값) | 본인 값으로 설정합니다. 이메일 공개가 싫으면 GitHub의 noreply 주소를 씁니다. |
| 자격 증명 도우미 | <code>/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe</code> (부록) | Git for Windows 설치 위치에 따라 다릅니다. <code>ls "/mnt/c/Program Files/Git/mingw64/bin/" \| grep credential</code>로 확인합니다. 12-5의 SSH 방식을 쓰면 필요 없습니다. |
| 원격 저장소 권한 | <code>buildergarlic/buildergarlic-codyssey</code> | clone과 실행에는 권한이 필요 없습니다. push까지 확인하려면 본인 저장소(fork)로 <code>git remote set-url</code> 합니다. |
| 베이스 이미지 버전 | <code>FROM nginx:alpine</code> (태그만 지정) | 태그가 가리키는 이미지는 시간이 지나면 바뀝니다. 11/04(부록 Step 4)는 digest <code>785835ea…</code>, 11/07(7·13-5절)은 <code>713fc2eb…</code>였고 두 날 모두 <code>nginx/1.31.8</code>이었습니다. 완전히 같은 이미지가 필요하면 <code>FROM nginx:alpine@sha256:&lt;digest&gt;</code>로 고정합니다. |
| 실행마다 바뀌는 값 | 컨테이너 ID, 내부 IP(<code>172.18.0.x</code>), 시각, ETag | 비교 대상이 아닙니다. 상태(<code>healthy</code>), HTTP 코드, 응답 본문을 비교합니다. |
| 줄바꿈(CRLF) | - | Windows에서 clone하면 <code>core.autocrlf</code> 설정에 따라 줄바꿈이 CRLF로 바뀔 수 있습니다. WSL2 안에서 clone하거나 <code>git config --global core.autocrlf input</code>을 씁니다. |
| sudo 비밀번호 | 6-2절 설치, <code>sudo lsof</code> (9절) | Docker Engine 설치에는 Ubuntu 계정의 sudo 비밀번호가 필요합니다(Windows 관리자 권한은 필요 없음). 9절은 비밀번호를 모르면 <code>ss -ltnp</code>만으로 확인합니다. |
| 실습실 PC 제한 | 코디세이 코딩스튜디오에서 Windows “선택적 기능” 진입 제한 (부록) | WSL2·Ubuntu가 이미 설치된 것으로 보고 진행합니다. Docker Engine은 Windows 설정 없이 Ubuntu 안에서 6-2절로 설치합니다. 개인 PC는 2절 설치 순서를 따릅니다. |
| 네트워크 제한 | Docker Hub <code>429 Too Many Requests</code> (6-6절) | <code>download.docker.com</code>(6-2절 apt 설치), Docker Hub(<code>registry-1.docker.io</code> 등), 22번 포트가 막힌 망에서는 설치·<code>pull</code>·<code>ssh</code>가 실패합니다. 접속 가능한 망에서 실행하고, SSH는 12-5의 443 포트 설정을 씁니다. <code>429</code>는 익명 다운로드 횟수 제한이므로 잠시 후 다시 시도하거나 <code>docker login</code> 후 받습니다. |

### 13-4. 실습 후 정리

~~~bash
cd ~/buildergarlic-codyssey
docker rm -f web-server bind-web 2>/dev/null
(cd compose/single && docker compose down)
(cd compose/multi && docker compose down)
(cd compose/env && docker compose down && rm -f .env)
docker volume rm mission-vol
docker image rm custom-nginx:1.0
git status --short
~~~

<code>git status --short</code>가 아무것도 출력하지 않으면 저장소가 clone 직후 상태로 돌아온 것입니다. 8절 실습으로 바뀐 <code>app/index.html</code>이 남아 있다면 <code>git restore app/index.html</code>로 되돌립니다.

### 13-5. 클린 clone 재현 검증 로그

새 디렉터리에 저장소를 clone하고 13-2 → 12-1 → 12-2 → 12-3 → 12-4 → 13-4 명령 블록을 README에 적힌 그대로 실행했습니다(12-1~12-4의 로그가 이 실행의 출력입니다). 시작 전 Docker 이미지·컨테이너·볼륨을 모두 비운 상태였습니다.

> 검증 시점에는 이번 변경분(<code>compose/</code>, <code>.gitignore</code>, <code>.dockerignore</code>, README)이 아직 GitHub에 push되지 않아, clone 직후 같은 내용을 로컬 커밋으로 반영한 뒤 진행했습니다.

13-2 실행 로그:

~~~console
[2026-11-07 18:21 KST, 클라우드 Linux 검증 환경]

$ cd ~

$ git clone https://github.com/buildergarlic/buildergarlic-codyssey.git
Cloning into 'buildergarlic-codyssey'...

$ cd buildergarlic-codyssey

$ docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}'
Client=29.9.2 Server=29.9.2

$ docker compose version
Docker Compose version v5.7.0

# 7절: 이미지 빌드 → 실행 → 접속
$ docker build -t custom-nginx:1.0 .
#0 building with "default" instance using docker driver

#1 [internal] load build definition from Dockerfile
#1 transferring dockerfile: 223B done
#1 DONE 0.0s

#2 [internal] load metadata for docker.io/library/nginx:alpine
#2 DONE 1.1s

#3 [internal] load .dockerignore
#3 transferring context: 91B done
#3 DONE 0.0s

#4 [internal] load build context
#4 transferring context: 350B done
#4 DONE 0.0s

#5 [1/2] FROM docker.io/library/nginx:alpine@sha256:713fc2ebfd92e8217db451477182ee91944b123d2b1ee9fd5a8c6e91ca6c3a11
#5 resolve docker.io/library/nginx:alpine@sha256:713fc2ebfd92e8217db451477182ee91944b123d2b1ee9fd5a8c6e91ca6c3a11 0.0s done
#5 … 레이어 다운로드·압축 해제 진행 표시 26줄 생략 …
#5 DONE 1.3s

#6 [2/2] COPY ./app /usr/share/nginx/html
#6 DONE 0.1s

#7 exporting to image
#7 exporting layers 0.0s done
#7 exporting manifest sha256:013341081c0e9fb2744c25f96325ebcf73e29fbbbcf6fce55e60c9e7bdb072bb
#7 exporting manifest sha256:013341081c0e9fb2744c25f96325ebcf73e29fbbbcf6fce55e60c9e7bdb072bb done
#7 exporting config sha256:2f5f0989c582dfdbaca22f314b3b33a46791b84429e407157da1368055922964 done
#7 exporting attestation manifest sha256:21d9058b37f8ce644e566b33e42de18f9625e6ab6a577091d796c2f1261fb5c0 done
#7 exporting manifest list sha256:95709216685f127c6bbfa6c928e576e6f0c51342bcb2ba9e7f41364e8849079c done
#7 naming to docker.io/library/custom-nginx:1.0 done
#7 unpacking to docker.io/library/custom-nginx:1.0
#7 unpacking to docker.io/library/custom-nginx:1.0 0.4s done
#7 DONE 0.5s

$ docker run -d --name web-server -p 8080:80 custom-nginx:1.0
41b288c4ba53a8129b9ea43dc01fefcdaec7b85acf8fca4692df9f54bf90d37c

$ sleep 2

$ curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080
HTTP 200

$ docker rm -f web-server
web-server

# 8절: 바인드 마운트 (실습 후 원본 복구)
$ docker run -d --name bind-web -p 8081:80 -v "$(pwd)/app:/usr/share/nginx/html" custom-nginx:1.0
a26ae04c101bb3fb09c670e4f8cc6522a68f4a734c82b8c28a2cf7a3d178c885

$ sleep 2

$ curl -sS http://localhost:8081 | grep Version
  <p>Version 1.0</p>

$ sed -i 's/Version 1.0/Version 2.0 (Bind Mounted on WSL2)/' app/index.html

$ curl -sS http://localhost:8081 | grep Version
  <p>Version 2.0 (Bind Mounted on WSL2)</p>

$ git restore app/index.html

$ docker rm -f bind-web
bind-web

# 8절: 볼륨 영속성
$ docker volume create mission-vol
mission-vol

$ docker run --name vol-writer -v mission-vol:/data alpine sh -c "echo 'Persistent Data Test 123' > /data/record.txt"
Unable to find image 'alpine:latest' locally
latest: Pulling from library/alpine
881fc932939e: Pulling fs layer
881fc932939e: Already exists
86ff264fe568: Download complete
c35a7d82b8fa: Download complete
Digest: sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a
Status: Downloaded newer image for alpine:latest

$ docker rm vol-writer
vol-writer

$ docker run --rm -v mission-vol:/data alpine cat /data/record.txt
Persistent Data Test 123
~~~

13-4 실행 로그:

~~~console
[2026-11-07 18:23 KST, 클라우드 Linux 검증 환경]

$ cd ~/buildergarlic-codyssey

$ docker rm -f web-server bind-web 2>/dev/null

$ (cd compose/single && docker compose down)

$ (cd compose/multi && docker compose down)

$ (cd compose/env && docker compose down && rm -f .env)

$ docker volume rm mission-vol
mission-vol

$ docker image rm custom-nginx:1.0
Untagged: custom-nginx:1.0
Deleted: sha256:a889a70ad8cdd8f8c1b625d8a2d10195d5c017fe68020df47e646851f333d4e0

$ git status --short
~~~

13-2의 HTTP 200·바인드 마운트·볼륨 결과와 12-1~12-4의 결과가 모두 통과 기준과 일치했고, 정리 후 <code>git status --short</code>가 빈 출력이라 실습이 저장소 파일을 바꾸지 않은 상태로 끝났습니다. 남은 항목은 GitHub 계정이 필요한 12-5뿐입니다.

---

## 부록: 기존 상세 실습 로그

아래에는 최초 작성 당시의 전체 명령 흐름을 보존했습니다. 단, Docker 설치·연동 부분은 본문 6절의 Ubuntu bash 설치 방식에 맞춰 정리했습니다. 부록은 이력 증거이며 현재 권장 절차는 위 1~13절입니다.

> 안전 주의: 부록의 <code>git gc --prune=now</code>는 도달할 수 없는 객체를 즉시 정리해 복구 가능성을 낮출 수 있으므로 백업과 영향 검토 없이 재실행하지 않습니다. 또한 부록 마지막의 “단순 오타” 문장은 Git 사용자 설정 오류의 원인을 뜻할 뿐, 원격 <code>commit_refs</code> 오류의 원인까지 입증한 것은 아닙니다.

<details>
<summary>기존 원본 상세 실습 로그 보기</summary>

## 1. 실행환경
| **OS** | Windows 11 (WSL2 - Ubuntu 22.04.x LTS, Kernel 5.15.x / 6.6.x) |
| **Shell / Terminal** | GNU bash 5.1.16 (Windows Terminal + VSCode Remote-WSL Terminal) |
| **Container Engine** | Docker Engine 29.9.2 (linux/amd64). 권장 설치 절차는 본문 6-2절 (Ubuntu bash, apt) |
| **Git Version** | git version 2.34.1 (WSL2 Ubuntu 내장 Git) |


## 2. 수행 체크리스트
- [x] 터미널 기본 조작 및 폴더 구성
- [x] 권한 변경 실습
- [x] Docker 설치/점검
- [x] hello-world 실행
- [x] Dockerfile 빌드/실행
- [x] 포트 매핑 접속(2회)
- [x] 바인드 마운트 반영
- [x] 볼륨 영속성
- [x] Git 설정 + VSCode GitHub 연동
- [x] 추가 선택 Docker Compose 설정 

## 3. 설치 진행과 수행 로그(핵심 발췌)
1. Windows 11 사전 환경 세팅 (PowerShell 관리자 권한)
WSL2와 Ubuntu가 아직 설치되지 않은 경우 아래 절차를 먼저 수행합니다. Docker는 Windows가 아니라 WSL2 Ubuntu 안에 설치합니다.

1-1. WSL2 활성화
wsl --install --no-distribution
WSL2 기능만 먼저 활성화 (Ubuntu 배포판은 1-2에서 설치)

1-1-1. 왜 WSL 설치?
- Windows 11에서 Docker를 쓰려면 WSL2(Windows Subsystem for Linux 2)로 실제 Linux(Ubuntu)를 띄우고, 그 Ubuntu 안에 Linux용 Docker Engine을 설치합니다. 따라서 Ubuntu 배포판 설치가 필수입니다.
- 도커의 태생적 구조: 도커 컨테이너(Linux 컨테이너)는 Linux 커널의 핵심 기능(Cgroups, Namespaces)을 공유하여 작동합니다. Windows 커널에는 이 기능이 직접 들어있지 않으므로, 백그라운드에서 경량 Linux 커널을 띄워줄 가상화 계층(WSL2)이 반드시 필요합니다.

- Windows의 기본 파일 시스템(NTFS)이나 Git Bash(MinGW)에서는 리눅스의 8진수 권한(chmod 700 등)이 정상적으로 반영되지 않아 과제 검증(요구사항 4-3)에서 결함이 발생합니다. 또한 WSL2의 /mnt/c/... 경로(Windows 호스트 마운트 경로)에서 작업할 경우에도 권한 변경이 무시되거나 Docker 바인드 마운트 I/O 성능 저하가 발생하므로, 반드시 WSL2 내부의 리눅스 네이티브 홈 디렉토리(~ 또는 /home/<계정명>)에서 모든 실습을 진행해야 합니다.
*(참고: 미션 안내문의 OrbStack은 macOS 전용 도구이므로, Windows 11에서는 WSL2 Ubuntu에 Docker Engine을 직접 설치해 구동합니다.)*

1-1-2. WSL vs WSL2
- WSL 1은 윈도우가 리눅스 흉내를 내는 번역기라면, WSL 2는 윈도우 안에 진짜 리눅스 커널을 통째로 집어넣은 가상 머신입니다.
- WSL 2는 실제 Linux 커널이 있어 Ubuntu 안에 Docker Engine을 그대로 설치·실행할 수 있지만, WSL 1은 아키텍처 한계로 Docker 데몬을 정상적으로 구동할 수 없습니다.

1-1-3. WSL2 (경량 Hyper-V 기반)
1) 윈도우즈 Hyper-V 설치 필요
2) 윈도우즈 "선택적 기능"(설정->앱->선택 기능)에서 추가
3) 명령어줄에서 다음 명령어 실행
3-1) 키보드에서 Win + R 키를 눌러 실행창을 엽니다.
3-2) 열기 칸에 ms-settings:optionalfeatures를 입력하고 확인을 누릅니다.
3-3) 선택적 기능 설정 화면이 즉시 나타납니다
**코디세이 코딩스튜디오에서는 실행 안됨.(설정 진입 막혀 있음)
**설치된 것을 가정하고 진행한다.

1-2. WSL2 Ubuntu와 Docker Engine 설치
2-2-1. Docker 왜 설치?
"내 컴퓨터에서는 잘 돌아가는데, 서버나 다른 사람 컴퓨터에서는 왜 안 되지?"(일명 "It works on my machine") 문제를 원천 차단하기 위함입니다.


1) WSL2 및 Ubuntu 22.04 설치
Windows 터미널(PowerShell)을 관리자 권한으로 열고 실행합니다.
# WSL2 활성화 및 Ubuntu 22.04 설치
wsl --install -d Ubuntu-22.04

# 설치 및 재부팅 후 WSL 버전이 2인지 확인 (VERSION이 2여야 함)
wsl -l -v

2) Ubuntu bash에서 Docker Engine 설치
Ubuntu 터미널을 열고 본문 6-2절 0~6단계를 그대로 실행합니다. 핵심 흐름:
[Bash]
# 0. systemd 확인 (systemd가 아니면 /etc/wsl.conf에 [boot] systemd=true 추가 → PowerShell에서 wsl --shutdown)
ps -p 1 -o comm=
# 1~3. 충돌 패키지 제거 → Docker 공식 apt 저장소 등록(6-2절 2단계) → 설치
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# 4~5. 서비스 시작·자동 시작, sudo 없이 쓰도록 docker 그룹 추가 (다시 로그인 후 적용)
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

3) VSCode 확장 프로그램 설치 (Windows 호스트)
VSCode를 열고 아래 확장(Extension)을 설치해야 WSL 내부 폴더를 직접 열고 GitHub 연동을 캡처할 수 있습니다.
- WSL (ms-vscode-remote.remote-wsl)
- Docker (ms-azuretools.vscode-docker)

2. WSL2(Ubuntu) 터미널 진입 및 실습 수행
이제 PowerShell이 아닌 Ubuntu 터미널(Windows 터미널에서 Ubuntu 탭 선택 또는 wsl -d Ubuntu-22.04 입력)을 엽니다.

Step 0: 작업 위치 검증 (가장 중요)
# 반드시 /mnt/c/... 가 아닌 /home/<유저명> 경로로 이동해야 chmod 권한 실습이 정상 작동함
cd ~
pwd
# 출력 예시: /home/don
*왜요? 리눅스 명령어인 chmod로 권한이 진짜 바뀌는 걸 눈으로 확인하고 실습하려면, 윈도우 영토(/mnt/c)가 아닌 리눅스 본연의 영토(/home/<유저명>)에서 작업해야 하기 때문이다.

1. 파일 시스템의 근본적인 차이
• /home/<유저명>: 리눅스 고유의 파일 시스템(ext4 등)을 사용하므로, 리눅스의 파일 권한 체계(rwxr-xr-x 등)가 완벽하게 기록되고 작동합니다.
• /mnt/c/...: 윈도우의 NTFS 파일 시스템입니다. 윈도우는 리눅스와 권한을 관리하는 방식(ACL 구조)이 완전히 달라서 리눅스의 chmod 명령이 먹히지 않거나 무시됩니다.

2. /mnt/c/...에서 실행하면 생기는 문제
기본 설정 상태의 WSL에서 /mnt/c/에 있는 파일에 chmod 755나 chmod 644를 실행하면, 명령어는 에러 없이 실행되는 것처럼 보이지만 실제 권한은 전혀 바뀌지 않고 고정되어 있습니다.
• 모든 파일이 무조건 777(또는 rwxrwxrwx)로 보이거나, 변경 요청이 무시되어 실습 결과가 정상적으로 확인되지 않습니다.


## Step 1: 작업 디렉토리 생성 및 터미널 기본 조작 (요구사항 4-2)
# 1. 작업 폴더 생성 및 이동
[Bash]
mkdir -p ~/workstation-mission && cd ~/workstation-mission
buildergarlic@GNIA-C202-A01:~$ mkdir -p ~/workstation-mission && cd ~/workstation-mission

# 2. 현재 위치 확인
[Bash]
pwd
buildergarlic@GNIA-C202-A01:~/workstation-mission$ pwd
/home/buildergarlic/workstation-mission

# 3. 빈 파일 및 디렉토리 생성
[Bash]
mkdir test_dir
touch empty_file.txt
echo "Hello Windows 11 WSL2 Workstation" > sample.txt

# 4. 목록 확인 (숨김 파일 포함) 및 파일 내용 확인
[Bash]
ls -la
buildergarlic@GNIA-C202-A01:~/workstation-mission$ ls -al
total 16
drwxr-xr-x 3 buildergarlic buildergarlic 4096 Nov  4 21:00 .
drwxr-x--- 6 buildergarlic buildergarlic 4096 Nov  4 20:54 ..
-rw-r--r-- 1 buildergarlic buildergarlic    0 Nov  4 20:59 empty_file.txt
-rw-r--r-- 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 20:59 test_dir

[Bash]
cat sample.txt
buildergarlic@GNIA-C202-A01:~/workstation-mission$ cat sample.txt
Hello Windows 11 WSL2 Workstation

# 5. 복사, 이동/이름변경, 삭제
[Bash]
cp sample.txt sample_copy.txt
mv sample_copy.txt test_dir/moved_sample.txt
ls -l test_dir/
buildergarlic@GNIA-C202-A01:~/workstation-mission$ cp sample.txt sample_copy.txt
buildergarlic@GNIA-C202-A01:~/workstation-mission$ mv sample_copy.txt test_dir/moved_sample.txt
buildergarlic@GNIA-C202-A01:~/workstation-mission$ ls -l test_dir/
total 4
-rw-r--r-- 1 buildergarlic buildergarlic 34 Nov  4 21:03 moved_sample.txt

[Bash]
rm empty_file.txt
ls -la
drwxr-xr-x 3 buildergarlic buildergarlic 4096 Nov  4 21:03 .
drwxr-x--- 6 buildergarlic buildergarlic 4096 Nov  4 20:54 ..
-rw-r--r-- 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 21:03 test_dir
buildergarlic@GNIA-C202-A01:~/workstation-mission$ 


## Step 2: 파일 및 디렉토리 권한 실습 (요구사항 4-3) - Permission 
WSL2 네이티브 경로(~/workstation-mission)이므로 chmod 결과가 즉시 반영됩니다.

# 변경 전 권한 확인 (일반적으로 파일 644, 디렉토리 755)
[Bash]
ls -ld test_dir sample.txt
buildergarlic@GNIA-C202-A01:~/workstation-mission$ ls -ld test_dir sample.txt
-rw-r--r-- 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 21:03 test_dir

# 권한 변경 (파일: 644 -> 755, 디렉토리: 755 -> 700)
[Bash]
chmod 755 sample.txt
chmod 700 test_dir

# 변경 후 권한 확인 (-rwxr-xr-x 및 drwx------ 로 변경된 것 확인)
[Bash] 이하 명령어는 모두 Bash로 생략한다.
ls -ld test_dir sample.txt
buildergarlic@GNIA-C202-A01:~/workstation-mission$ ls -ld test_dir sample.txt
-rwxr-xr-x 1 buildergarlic buildergarlic   34 Nov  4 21:00 sample.txt
drwx------ 2 buildergarlic buildergarlic 4096 Nov  4 21:03 test_dir

**리눅스 파일 권한 숫자(644, 755, 700)는 [소유자(User) · 그룹(Group) · 기타 사용자(Others)] 각각의 권한을 숫자로 조합한 것입니다.

권한의 기본 값은 읽기(Read = 4), 쓰기(Write = 2), 실행(Execute = 1)의 합으로 계산합니다.
• 4: 읽기 (r) / • 2: 쓰기 (w) / • 1: 실행 (x) / • 0: 권한 없음 (-)

1. 644 (rw-r--r--)
• 소유자(6 = 4+2): 읽기(4) + 쓰기(2) 가능
• 그룹(4): 읽기(4)만 가능
• 기타 사용자(4): 읽기(4)만 가능
• 주요 용도: 일반 문서 파일, 설정 파일, 웹 페이지용 소스코드 파일 (수정은 소유자만 하고, 남들은 보기만 함)

2. 755 (rwxr-xr-x)
• 소유자(7 = 4+2+1): 읽기(4) + 쓰기(2) + 실행(1) 모두 가능
• 그룹(5 = 4+1): 읽기(4) + 실행(1) 가능 (수정은 불가)
• 기타 사용자(5 = 4+1): 읽기(4) + 실행(1) 가능 (수정은 불가)
• 주요 용도: 디렉터리(폴더) 기본값, 실행 가능한 프로그램이나 셸 스크립트(.sh)

3. 700 (rwx------)
• 소유자(7 = 4+2+1): 읽기(4) + 쓰기(2) + 실행(1) 모두 가능
• 그룹(0): 권한 없음 (---)
• 기타 사용자(0): 권한 없음 (---)
• 주요 용도: 오직 소유자 본인만 접근할 수 있어야 하는 민감한 디렉터리나 파일 (예: 사용자 SSH키가 담긴 .ssh 폴더, 비밀번호 파일 등)


## Step 3: Docker 설치 점검 및 기본 운영 명령 (요구사항 4-4, 4-5, 4-6)

# 버전 및 데몬 동작 점검 (본문 6-2절대로 Docker Engine을 설치하고 docker 서비스가 실행 중이어야 동작함)
docker --version
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker --version
Docker version 29.9.2, build a82e528

docker info | head -n 25
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker info | head -n 25
Client:
 Version:    29.9.2
 Context:    default
 Debug Mode: false
 Plugins:
  … 플러그인 목록 생략 (설치 방식에 따라 다름. Ubuntu apt 설치 기준 출력은 본문 10절 Case 3) …

# hello-world 실행
docker run hello-world
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker run hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
4f55086f7dd0: Pull complete 
d5e71e642bf5: Download complete 
Digest: sha256:c567b231f65614688711a75f31518a064258a51d442117a3e771a3a8fdba78ef
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.

To try something more ambitious, you can run an Ubuntu container with:
 $ docker run -it ubuntu bash

Share images, automate workflows, and more with a free Docker ID:
 https://hub.docker.com/

For more examples and ideas, visit:
 https://docs.docker.com/get-started/


# Ubuntu 컨테이너 백그라운드 실행 및 내부 진입
docker run -dit --name my-ubuntu ubuntu:22.04 bash
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker run -dit --name my-ubuntu ubuntu:22.04 bash
Unable to find image 'ubuntu:22.04' locally
22.04: Pulling from library/ubuntu
0626d3cc316c: Pull complete 
ae52aad3a114: Download complete 
Digest: sha256:076e7bf82319619f28dd0aa9c02ab34b055ad37100395b4f49a2ffba04fb5e11
Status: Downloaded newer image for ubuntu:22.04
415d6191fc85d995feb8365469469b4e3de3cf625b39961fbf929d0028c5b16d

docker ps
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker ps
CONTAINER ID   IMAGE          COMMAND   CREATED          STATUS          PORTS     NAMES
415d6191fc85   ubuntu:22.04   "bash"    21 seconds ago   Up 20 seconds             my-ubuntu

docker exec -it my-ubuntu bash -c "ls -la / && echo 'Inside WSL2 Docker Container'"
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker exec -it my-ubuntu bash -c "ls -la / && echo 'Inside WSL2 Docker Container'"
total 56
drwxr-xr-x   1 root root 4096 Nov  4 12:25 .
drwxr-xr-x   1 root root 4096 Nov  4 12:25 ..
-rwxr-xr-x   1 root root    0 Nov  4 12:25 .dockerenv
lrwxrwxrwx   1 root root    7 Oct 20 17:07 bin -> usr/bin
drwxr-xr-x   2 root root 4096 Apr 18  2022 boot
drwxr-xr-x   5 root root  360 Nov  4 12:25 dev
drwxr-xr-x   1 root root 4096 Nov  4 12:25 etc
drwxr-xr-x   2 root root 4096 Apr 18  2022 home
lrwxrwxrwx   1 root root    7 Oct 20 17:07 lib -> usr/lib
lrwxrwxrwx   1 root root    9 Oct 20 17:07 lib32 -> usr/lib32
lrwxrwxrwx   1 root root    9 Oct 20 17:07 lib64 -> usr/lib64
lrwxrwxrwx   1 root root   10 Oct 20 17:07 libx32 -> usr/libx32
drwxr-xr-x   2 root root 4096 Oct 20 17:07 media
drwxr-xr-x   2 root root 4096 Oct 20 17:07 mnt
drwxr-xr-x   2 root root 4096 Oct 20 17:07 opt
dr-xr-xr-x 333 root root    0 Nov  4 12:25 proc
drwx------   2 root root 4096 Oct 20 17:15 root
drwxr-xr-x   5 root root 4096 Oct 20 17:15 run
lrwxrwxrwx   1 root root    8 Oct 20 17:07 sbin -> usr/sbin
drwxr-xr-x   2 root root 4096 Oct 20 17:07 srv
dr-xr-xr-x  12 root root    0 Nov  4 12:25 sys
drwxrwxrwt   2 root root 4096 Oct 20 17:15 tmp
drwxr-xr-x  14 root root 4096 Oct 20 17:07 usr
drwxr-xr-x  11 root root 4096 Oct 20 17:15 var
Inside WSL2 Docker Container


# 운영 명령어 (로그, 리소스, 전체 목록 확인) 수행 후 중지
docker logs my-ubuntu
docker stats --no-stream my-ubuntu
docker stop my-ubuntu
docker ps -a

buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker logs my-ubuntu
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker stats --no-stream my-ubuntu
CONTAINER ID   NAME        CPU %     MEM USAGE / LIMIT     MEM %     NET I/O         BLOCK I/O   PIDS
415d6191fc85   my-ubuntu   0.00%     3.039MiB / 15.25GiB   0.02%     1.17kB / 126B   0B / 0B     1
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker stop my-ubuntu
my-ubuntu
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker ps -a
CONTAINER ID   IMAGE          COMMAND    CREATED         STATUS                      PORTS     NAMES
415d6191fc85   ubuntu:22.04   "bash"     2 minutes ago   Exited (137) 1 second ago             my-ubuntu
0692d7cb1287   hello-world    "/hello"   8 minutes ago   Exited (0) 8 minutes ago              romantic_rhodes
buildergarlic@GNIA-C202-A01:~/workstation-mission$ 

## Step 4: 커스텀 웹 서버 이미지 빌드 및 포트 매핑 (요구사항 4-7, 4-8)

# 웹 소스 디렉토리 및 HTML 파일 생성
mkdir -p ~/workstation-mission/app
cat << 'EOF' > ~/workstation-mission/app/index.html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Workstation Mission</title></head>
<body><h1>Custom Nginx Container on Windows 11 (WSL2)</h1><p>Version 1.0</p></body>
</html>
EOF

buildergarlic@GNIA-C202-A01:~/workstation-mission$ pwd
/home/buildergarlic/workstation-mission
buildergarlic@GNIA-C202-A01:~/workstation-mission$ mkdir -p ~/workstation-mission/app
buildergarlic@GNIA-C202-A01:~/workstation-mission$ cat << 'EOF' > ~/workstation-mission/app/index.html
> <!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Workstation Mission</title></head>
<body><h1>Custom Nginx Container on Windows 11 (WSL2)</h1><p>Version 1.0</p></body>
</html>
EOF
buildergarlic@GNIA-C202-A01:~/workstation-mission$ ls -al /app
ls: cannot access '/app': No such file or directory
buildergarlic@GNIA-C202-A01:~/workstation-mission$ cd app
buildergarlic@GNIA-C202-A01:~/workstation-mission/app$ ls -al
total 12
drwxr-xr-x 2 buildergarlic buildergarlic 4096 Nov  4 21:29 .
drwxr-xr-x 4 buildergarlic buildergarlic 4096 Nov  4 21:29 ..
-rw-r--r-- 1 buildergarlic buildergarlic  185 Nov  4 21:29 index.html

# Dockerfile 작성
cat << 'EOF' > ~/workstation-mission/Dockerfile
FROM nginx:alpine
LABEL maintainer="developer"
COPY ./app /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ || exit 1
EOF

buildergarlic@GNIA-C202-A01:~/workstation-mission/app$ cat << 'EOF' > ~/workstation-mission/Dockerfile
FROM nginx:alpine
LABEL maintainer="developer"
COPY ./app /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ || exit 1
EOF
buildergarlic@GNIA-C202-A01:~/workstation-mission/app$ 

# 이미지 빌드 및 컨테이너 실행 (호스트 8080 -> 컨테이너 80)
cd ~/workstation-mission
docker build -t custom-nginx:1.0 .
docker images | grep custom-nginx
docker run -d --name web-server -p 8080:80 custom-nginx:1.0

buildergarlic@GNIA-C202-A01:~/workstation-mission/app$ cd ~/workstation-mission
buildergarlic@GNIA-C202-A01:~/workstation-mission$ pwd
/home/buildergarlic/workstation-mission
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker build -t custom-nginx:1.0 .
[+] Building 5.1s (7/7) FINISHED                                                                                 docker:default
 => [internal] load build definition from Dockerfile                                                                       0.0s
 => => transferring dockerfile: 211B                                                                                       0.0s
 => [internal] load metadata for docker.io/library/nginx:alpine                                                            2.2s
 => [internal] load .dockerignore                                                                                          0.0s
 => => transferring context: 2B                                                                                            0.0s
 => [internal] load build context                                                                                          0.1s
 => => transferring context: 255B                                                                                          0.0s
 => [1/2] FROM docker.io/library/nginx:alpine@sha256:785835ea65db4bba6f021acc0f3be91b0fef76a53fe41f8588c6698d2aed0606      2.1s
 => => resolve docker.io/library/nginx:alpine@sha256:785835ea65db4bba6f021acc0f3be91b0fef76a53fe41f8588c6698d2aed0606      0.0s
 => => sha256:9b0f7dfe35b2711a17f60dadd6d4035dc0cdee152538cc5c0987029e94679548 1.40kB / 1.40kB                             0.2s
 => => sha256:b9b388a21ecfde6ac80505f23f527146a2129dfb104e79b029bbd00d4cc1a919 20.53MB / 20.53MB                           1.7s
 => => sha256:2ec5fb117ffa9a78b15fb6a78745ffc569c8da0aee9f36ace4cd67a44b1fef79 1.21kB / 1.21kB                             0.6s
 => => sha256:26185d08a3ec318dd85a6c9f2172e714ec13cececd7f33c533b40b1689f9fedb 404B / 404B                                 0.7s
 => => sha256:7cc330898115ce55acccb0cc1e7dd091df4410c8c5f3c540710ee0ac689f5fcb 964B / 964B                                 0.4s
 => => sha256:657023555a2a19dc6036468198bb350d2c7feaac7f2d0a3901b4dd3cb25e40c5 629B / 629B                                 0.2s
 => => sha256:12b85cff06fd7d383d36a9c96503fe049c9d4bf3dfda5cbb9ffa6ae99b9c07a6 1.94MB / 1.94MB                             0.4s
 => => sha256:7b229517ed222597277036d94892173207d01a731ab3a88eeb1de2e963a2c788 3.85MB / 3.85MB                             0.7s
 => => extracting sha256:7b229517ed222597277036d94892173207d01a731ab3a88eeb1de2e963a2c788                                  0.1s
 => => extracting sha256:12b85cff06fd7d383d36a9c96503fe049c9d4bf3dfda5cbb9ffa6ae99b9c07a6                                  0.1s
 => => extracting sha256:657023555a2a19dc6036468198bb350d2c7feaac7f2d0a3901b4dd3cb25e40c5                                  0.0s
 => => extracting sha256:7cc330898115ce55acccb0cc1e7dd091df4410c8c5f3c540710ee0ac689f5fcb                                  0.0s
 => => extracting sha256:26185d08a3ec318dd85a6c9f2172e714ec13cececd7f33c533b40b1689f9fedb                                  0.0s
 => => extracting sha256:2ec5fb117ffa9a78b15fb6a78745ffc569c8da0aee9f36ace4cd67a44b1fef79                                  0.0s
 => => extracting sha256:9b0f7dfe35b2711a17f60dadd6d4035dc0cdee152538cc5c0987029e94679548                                  0.0s
 => => extracting sha256:b9b388a21ecfde6ac80505f23f527146a2129dfb104e79b029bbd00d4cc1a919                                  0.2s
 => [2/2] COPY ./app /usr/share/nginx/html                                                                                 0.1s
 => exporting to image                                                                                                     0.6s
 => => exporting layers                                                                                                    0.1s
 => => exporting manifest sha256:adf6c34f2ebd9eedc15583028e927fc81c36eaa6c16af9f3081ac418d38229a5                          0.0s
 => => exporting config sha256:166794eed9949bb1110da65861991969a6ab2b4a126086d1ba432c0484d9242c                            0.0s
 => => exporting attestation manifest sha256:b81311542c6b52e4b667e4931b29d2ddf245b7f84f0b85b19e13c695865d9d8b              0.0s
 => => exporting manifest list sha256:2919e0c82b0c7b36a0aa90df0473c9e9c54077eaa84c4664a276af719473fa0d                     0.0s
 => => naming to docker.io/library/custom-nginx:1.0                                                                        0.0s
 => => unpacking to docker.io/library/custom-nginx:1.0                                                                     0.4s
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker images | grep custom-nginx
custom-nginx:1.0     2919e0c82b0c       93.6MB         26.3MB        
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker run -d --name web-server -p 8080:80 custom-nginx:1.0
9075b12f2c4cc8cba4a26d77316f69dc0e0b25f97268eb3586affca4203903df
buildergarlic@GNIA-C202-A01:~/workstation-mission$ 

# CLI 응답 확인
curl -i http://localhost:8080
buildergarlic@GNIA-C202-A01:~/workstation-mission$ curl -i http://localhost:8080
HTTP/1.1 200 OK
Server: nginx/1.31.8
Date: Wed, 04 Nov 2026 12:33:28 GMT
Content-Type: text/html
Content-Length: 185
Last-Modified: Wed, 04 Nov 2026 12:29:20 GMT
Connection: keep-alive
ETag: "6aeb2520-b9"
Accept-Ranges: bytes

<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Workstation Mission</title></head>
<body><h1>Custom Nginx Container on Windows 11 (WSL2)</h1><p>Version 1.0</p></body>
</html>

docker logs web-server
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker logs web-server
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
/docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/11/04 12:32:56 [notice] 1#1: using the "epoll" event method
2026/11/04 12:32:56 [notice] 1#1: nginx/1.31.8
2026/11/04 12:32:56 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0) 
2026/11/04 12:32:56 [notice] 1#1: OS: Linux 6.18.54.1-microsoft-standard-WSL2
2026/11/04 12:32:56 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 1048576:1048576
2026/11/04 12:32:56 [notice] 1#1: start worker processes
2026/11/04 12:32:56 [notice] 1#1: start worker process 30
2026/11/04 12:32:56 [notice] 1#1: start worker process 31
2026/11/04 12:32:56 [notice] 1#1: start worker process 32
2026/11/04 12:32:56 [notice] 1#1: start worker process 33
2026/11/04 12:32:56 [notice] 1#1: start worker process 34
2026/11/04 12:32:56 [notice] 1#1: start worker process 35
2026/11/04 12:32:56 [notice] 1#1: start worker process 36
2026/11/04 12:32:56 [notice] 1#1: start worker process 37
2026/11/04 12:32:56 [notice] 1#1: start worker process 38
2026/11/04 12:32:56 [notice] 1#1: start worker process 39
2026/11/04 12:32:56 [notice] 1#1: start worker process 40
2026/11/04 12:32:56 [notice] 1#1: start worker process 41
2026/11/04 12:32:56 [notice] 1#1: start worker process 42
2026/11/04 12:32:56 [notice] 1#1: start worker process 43
2026/11/04 12:32:56 [notice] 1#1: start worker process 44
2026/11/04 12:32:56 [notice] 1#1: start worker process 45
2026/11/04 12:32:56 [notice] 1#1: start worker process 46
2026/11/04 12:32:56 [notice] 1#1: start worker process 47
2026/11/04 12:32:56 [notice] 1#1: start worker process 48
2026/11/04 12:32:56 [notice] 1#1: start worker process 49
2026/11/04 12:32:56 [notice] 1#1: start worker process 50
2026/11/04 12:32:56 [notice] 1#1: start worker process 51
2026/11/04 12:32:56 [notice] 1#1: start worker process 52
2026/11/04 12:32:56 [notice] 1#1: start worker process 53
::1 - - [04/Nov/2026:12:33:26 +0000] "GET / HTTP/1.1" 200 185 "-" "Wget" "-"
172.17.0.1 - - [04/Nov/2026:12:33:28 +0000] "GET / HTTP/1.1" 200 185 "-" "curl/7.81.0" "-"
::1 - - [04/Nov/2026:12:33:56 +0000] "GET / HTTP/1.1" 200 185 "-" "Wget" "-"

docker stop web-server && docker rm web-server
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker stop web-server && docker rm web-server
web-server
web-server


## Step 5: 바인드 마운트 & 볼륨 영속성 검증 (요구사항 2-7, 4-9)
Windows PowerShell에서는 $(pwd) 문법이나 경로 구분자(\) 때문에 마운트 오류가 자주 발생하지만, WSL2 Ubuntu 내부에서는 리눅스 표준 문법이 그대로 동작합니다.

# [1] 바인드 마운트 검증 (호스트 파일 수정 시 컨테이너 즉시 반영 확인)
docker run -d --name bind-web -p 8081:80 -v "$(pwd)/app:/usr/share/nginx/html" custom-nginx:1.0
curl http://localhost:8081

buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker run -d --name bind-web -p 8081:80 -v "$(pwd)/app:/usr/share/nginx/html" custom-nginx:1.0
ebd5ee3377b74a813864dd32ea29f8c11a4681c45e84cc7a1bafaa031bb333f3
buildergarlic@GNIA-C202-A01:~/workstation-mission$ curl http://localhost:8081
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Workstation Mission</title></head>
<body><h1>Custom Nginx Container on Windows 11 (WSL2)</h1><p>Version 1.0</p></body>
</html>

# 호스트(WSL2) 파일 내용 수정
sed -i 's/Version 1.0/Version 2.0 (Bind Mounted on WSL2)/g' app/index.html
buildergarlic@GNIA-C202-A01:~/workstation-mission$ sed -i 's/Version 1.0/Version 2.0 (Bind Mounted on WSL2)/g' app/index.html

# 이미지 재빌드 없이 변경사항 즉시 반영 확인
curl http://localhost:8081
buildergarlic@GNIA-C202-A01:~/workstation-mission$ curl http://localhost:8081
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Workstation Mission</title></head>
<body><h1>Custom Nginx Container on Windows 11 (WSL2)</h1><p>Version 2.0 (Bind Mounted on WSL2)</p></body>
</html>

docker stop bind-web && docker rm bind-web
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker stop bind-web && docker rm bind-web
bind-web
bind-web

# [2] Docker 볼륨 영속성 검증 (컨테이너 삭제 전/후 비교)
docker volume create mission-vol
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker volume create mission-vol
mission-vol

docker volume ls | grep mission-vol
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker volume ls | grep mission-vol
local     mission-vol

# 첫 번째 컨테이너에서 볼륨에 데이터 기록 후 컨테이너 삭제
docker run --name vol-writer -v mission-vol:/data alpine sh -c "echo 'Persistent Data Test 123' > /data/record.txt && cat /data/record.txt"
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker run --name vol-writer -v mission-vol:/data alpine sh -c "echo 'Persistent Data Test 123' > /data/record.txt && cat /data/record.txt"
Unable to find image 'alpine:latest' locally
latest: Pulling from library/alpine
7b229517ed22: Already exists 
3ec36f3670df: Download complete 
3da1513d2124: Download complete 
Digest: sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
Status: Downloaded newer image for alpine:latest
Persistent Data Test 123

docker rm vol-writer
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker rm vol-writer
vol-writer

# 두 번째 신규 컨테이너에 동일 볼륨 연결 후 데이터 보존 확인
docker run --rm --name vol-reader -v mission-vol:/data alpine cat /data/record.txt
buildergarlic@GNIA-C202-A01:~/workstation-mission$ docker run --rm --name vol-reader -v mission-vol:/data alpine cat /data/record.txt
Persistent Data Test 123


## Step 6: Git 설정 및 VSCode-WSL-GitHub 연동 (요구사항 2-8, 4-10)
WSL2 내부의 Git과 Windows의 Git 자격 증명 관리자(Git Credential Manager)를 연결하면 토큰 노출 없이 안전하게 VSCode 및 GitHub와 연동됩니다.

# 1. Git 사용자 정보 및 기본 브랜치 설정
git config --global user.name "buildergarlic"
git config --global user.email "nobody@nobody.com"
git config --global init.defaultBranch main

# 2. Windows 11의 Git Credential Manager를 WSL2와 연동 (토큰/비밀번호 평문 노출 방지)
git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"

# 3. 설정 확인 (README 기록 시 이메일 등은 마스킹할 것)
git config --list

buildergarlic@GNIA-C202-A01:~/workstation-mission$ git config --global user.name "buildergarlic"
buildergarlic@GNIA-C202-A01:~/workstation-mission$ 
buildergarlic@GNIA-C202-A01:~/workstation-mission$ git config --global user.email "nobody@nobody.com"
buildergarlic@GNIA-C202-A01:~/workstation-mission$ git config --global init.defaultBranch main
buildergarlic@GNIA-C202-A01:~/workstation-mission$ git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
buildergarlic@GNIA-C202-A01:~/workstation-mission$ git config --list
credential.helper=/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe
user.name=buildergarlic
user.email=nobody@nobody.com
init.defaultbranch=main
core.repositoryformatversion=0
core.filemode=true
core.bare=false
core.logallrefupdates=true
buildergarlic@GNIA-C202-A01:~/workstation-mission$ 

# 4. 로컬 저장소 초기화 및 현재 디렉토리에서 VSCode 실행
cd ~/workstation-mission
git init
code .
![컨테이너 웹서버](screenshots/container-webserver.png)


## 6. 트러블슈팅 기록

### Case 1: Windows 마운트 경로(`/mnt/c/...`)에서 `chmod` 파일 권한 변경이 적용되지 않는 문제
* **문제 현상:** WSL2 터미널에서 Windows 바탕화면 경로(`/mnt/c/Users/...`)에 폴더를 만들고 `chmod 755 sample.txt` 및 `chmod 700 test_dir`을 실행했으나, 에러 메시지 없이 `ls -ld`의 권한 표기가 변경 전(`-rwxrwxrwx`) 그대로 유지됨.
* **원인 가설:** WSL2에서 `/mnt/c` 경로는 Windows의 NTFS 파일 시스템을 `drvfs`로 마운트한 영역이므로, 기본적으로 Linux 고유의 POSIX 파일 권한 메타데이터를 지원하지 않아 `chmod` 명령이 무시되는 것으로 추정.
* **확인 절차:** `df -T .` 명령어로 파일 시스템 타입을 확인한 결과 `/mnt/c` 경로는 `9p` (drvfs)로 마운트되어 있었고, WSL 고유 홈 디렉토리(`~`)는 리눅스 네이티브 파일 시스템인 `ext4`로 구성된 것을 확인함.
* **해결 및 대안:** 작업 디렉토리를 `/mnt/c/...`에서 리눅스 네이티브 파일 시스템 영역인 `/home/<사용자>/workstation-mission`(`~/workstation-mission`)으로 이전하여 실습을 재수행함. 이후 `chmod 755`, `chmod 700`이 정확히 반영됨을 확인함(추후 Docker 바인드 마운트 시의 파일 I/O 속도 저하 문제도 동시에 예방).

### Case 2: Docker 데몬 연결 실패 (`Cannot connect to the Docker daemon`)
본문 10절 Case 3에 Ubuntu bash Docker Engine 기준의 실제 오류·원인·조치로 정리했습니다.

### Case 3: git user setting Error
#git user setting 
PS D:\buildergarlic-codyssey> git config --global buildergarlic
error: key does not contain a section: buildergarlic
PS D:\buildergarlic-codyssey> git config --global nobody@nobody.com
error: invalid key: nobody@nobody.com
PS D:\buildergarlic-codyssey> 

# 단순 오타
PS D:\buildergarlic-codyssey> git config --global user.email "nobody@nobody.com"
PS D:\buildergarlic-codyssey> git config --global user.email "nobody@nobody.com"
PS D:\buildergarlic-codyssey> 

### Case 4: git push -u origin main
> git push -u origin main
remote: fatal error in commit_refs        
To https://github.com/buildergarlic/buildergarlic-codyssey.git
 ! [remote rejected] main -> main (failure)
error: failed to push some refs to 'https://github.com/buildergarlic/buildergarlic-codyssey.git'

해결 방법
1단계: 원격 저장소 연결 상태 확인 및 갱신:1분.현재 연결된 원격 저장소 주소가 올바른지 확인하고 연결을 새로고침합니다.PowerShellgit remote -v
주소가 [https://github.com/buildergarlic/buildergarlic-codyssey.git](https://github.com/buildergarlic/buildergarlic-codyssey.git)로 정확히 나오는지 확인한 뒤, 연결을 재설정합니다.PowerShellgit remote set-url origin https://github.com/buildergarlic/buildergarlic-codyssey.git
Verification: 오류 없이 명령어가 실행되면 연결 정보가 갱신된 것입니다.

2단계: 가비지 컬렉션(Garbage Collection) 실행:1분.로컬 Git 데이터베이스가 손상되었거나 일시적으로 꼬인 경우 내부 저장소를 정리하여 해결할 수 있습니다.PowerShellgit gc --prune=now
Verification: 최적화 작업이 완료되고 프롬프트가 정상적으로 돌아오면 성공입니다.

3단계: 강제 푸시 대신 안전하게 다시 푸시 시도:1분.서버와 로컬의 커밋 히스토리를 맞추기 위해 일반 푸시를 다시 시도합니다.PowerShellgit push -u origin main --force-with-lease
Verification: Everything up-to-date 또는 Writing objects... Done 메시지와 함께 

*GitHub에 정상적으로 업로드되는지 확인합니다.대용량 파일 주의프로젝트 폴더 내에 100MB가 넘는 대용량 파일(동영상, 빌드 결과물 등)이 포함되어 있는지 확인해 보세요. GitHub는 개별 파일이 100MB를 초과하면 원격 거부(remote rejected) 오류를 발생시킵니다.

실제 원인 - 단순 오타 Case 3 해결로 설정 완료.

</details>
