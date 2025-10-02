## 이미지 버전 요약
각 이미지 태그는 생성된 날짜(YYMMDD)를 따르며, latest 태그는 항상 최신 버전의 이미지를 가리킵니다.

| 이미지 태그 (Image Tag) | TensorFlow 버전 | CUDA / cuDNN | 베이스 OS (Base OS) | 주요 변경사항 및 설명 |
| :--- | :--- | :--- | :--- | :--- |
| `dguailab/decs:latest`<br>`dguailab/decs:251002` | **2.18.0** | CUDA 12.5<br>cuDNN 8.9 | Ubuntu 22.04 | **(최신)** TensorFlow 2.18.0 업그레이드, 최신 GPU 환경 지원 |
| `dguailab/decs:250926` | **2.13.0** | CUDA 11.8<br>cuDNN 8.6 | Ubuntu 20.04 | **(이전 안정 버전)** TensorFlow 2.13.0 기반의 안정화 버전 |

## 사용 방법
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


# 빌드 자동화
이 Docker 이미지는 GitHub Actions를 통해 자동으로 빌드 및 배포됩니다.
- 실행 조건: decsYYMMDD 형식의 브랜치가 develop 브랜치로 병합(merge)될 때
- 자동 생성 태그:
- 브랜치 이름에서 추출한 날짜 태그 (예: `dguailab/decs:251002`)
- 최신 버전을 가리키는 latest 태그 (`dguailab/decs:latest`)
