## 🗒️ 이미지 버전 요약
각 이미지 태그는 생성된 날짜(YYMMDD)를 따르며, latest 태그는 항상 최신 버전의 이미지를 가리킵니다.

| 이미지 태그 (Image Tag) | TensorFlow 버전 | CUDA / cuDNN | 베이스 OS (Base OS) | 주요 변경사항 및 설명 |
| :--- | :--- | :--- | :--- | :--- |
| `dguailab/decs:latest`<br>`dguailab/decs:260501` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | **(최신)** Xfce + TigerVNC + noVNC 기반 브라우저 GUI 접속 지원 추가 |
| `dguailab/decs:260427` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | 기존 사용자 컨테이너 변경 시 `~/.bashrc`의 conda initialize 블록 갱신, 경고 주석 영문화 및 인덴트 수정 |
| `dguailab/decs:260403` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | 계정/권한 검증 강화, config-server 주입 기반 sudo 권한 축소, Jupyter 및 컨테이너 유지 프로세스 비-root 실행, gosu 추가 |
| `dguailab/decs:260201` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | 의도되지 않은 MOTD 출력 방지 버그 수정 |
| `dguailab/decs:251023` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | **(이전 안정 버전)** Jupyter Notebook 설정 파일 생성/경로 오류 해결, 랜덤 토큰 저장 방식 반영 |
| `dguailab/decs:251002` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | TensorFlow 2.18.0 업그레이드, 최신 GPU 환경 지원, Docker Hub 자동 빌드/푸시 워크플로 도입 |
| `dguailab/decs:250926` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | **(이전 안정 버전)** 사용자 홈 디렉토리 소유권 설정 순서 수정, 이슈/PR 템플릿 추가 |
| `dguailab/decs:250428` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | Jupyter Lab 설정 파일을 사용자 홈의 `.jupyter` 경로에서 생성하고 사용하도록 수정 |
| `dguailab/decs:250416` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | Jupyter Notebook 설정 파일 생성 로직 수정, 10자리 랜덤 토큰 생성 및 파일 저장 추가 |
| `dguailab/decs:250323` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | `useradd` 옵션 보완, MOTD 공지 추가, TensorFlow ASCII 출력 제거 |
| `dguailab/decs:250309` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | ldconfig permission denied 오류 방지, MOTD/Slack 공지 반영, Conda 최신화 반영 |
| `dguailab/decs:250218` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | Anaconda3 2024.10-1 설치로 Conda 24.9.2 업그레이드 |

## ⚙️ 사용 방법
필요한 버전의 이미지를 Docker Hub에서 pull 받아 사용합니다.

### 최신 버전 사용하기
latest 태그를 사용하여 항상 최신 버전의 이미지를 받을 수 있습니다.
```
docker pull dguailab/decs:latest
```

### 날짜 태그를 직접 명시하여 받기
```
docker pull dguailab/decs:251002
```

### 특정 구버전 사용하기
이전 버전의 TensorFlow 환경이 필요한 경우, 해당 날짜 태그를 명시하여 이미지를 받습니다.
```
docker pull dguailab/decs:250926
```

### GUI 접속(noVNC)
`260501` 버전부터 브라우저 기반 GUI 접속을 지원합니다. GUI 접속은 기본 비활성화 상태이며, 컨테이너 생성 시 `ENABLE_VNC=true` 환경변수를 전달한 경우에만 시작됩니다.

- 컨테이너 내부 noVNC 포트: `6080`
- 컨테이너 내부 VNC 포트: `localhost:5901` 전용
- 접속 URL: `http://서버주소:외부포트/vnc.html`
- VNC 비밀번호 저장 위치: `/home/$USER_ID/decs_jupyter_lab/vnc_password.txt`

직접 `docker run`을 사용할 때는 다음처럼 환경변수와 포트를 함께 지정합니다.

```
-e ENABLE_VNC=true -p 외부포트:6080
```

운영 스크립트(`~/uid`)에서는 `--enable_vnc true`를 주면 컨테이너 내부 `6080` 포트를 자동으로 추가하고, Docker 실행 환경변수에 `ENABLE_VNC=true`를 함께 전달합니다. FARM2 예시는 외부 포트 범위 `9100~9199` 중 하나가 `6080`에 연결되는 방식입니다.

```
--enable_vnc true
```

관련 환경변수:

| 환경변수 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `ENABLE_VNC` | `false` | `true`로 설정한 경우에만 VNC/noVNC를 시작합니다. |
| `VNC_PASSWORD` | 랜덤 8자리 | 지정하지 않으면 자동 생성 후 `vnc_password.txt`에 저장합니다. |
| `VNC_RESOLUTION` | `1920x1080` | VNC 화면 해상도입니다. |
| `VNC_DEPTH` | `24` | VNC 색상 깊이입니다. |
| `VNC_DISPLAY` | `1` | VNC display 번호입니다. 기본 VNC 포트는 `5901`입니다. |
| `NOVNC_PORT` | `6080` | noVNC가 컨테이너 내부에서 listen할 포트입니다. |


# ⚒️ 빌드 자동화
이 Docker 이미지는 GitHub Actions를 통해 자동으로 빌드 및 배포됩니다.
- 실행 조건: decsYYMMDD 형식의 브랜치가 develop 브랜치로 병합(merge)될 때
- 자동 생성 태그:
- 브랜치 이름에서 추출한 날짜 태그 (예: `dguailab/decs:251002`)
- 최신 버전을 가리키는 latest 태그 (`dguailab/decs:latest`)


<br><br><br>
### 🔗 관리자용 노션 문서 링크
https://www.notion.so/DECS-280c7692a263802ca40ff68b38f58dd1?source=copy_link
