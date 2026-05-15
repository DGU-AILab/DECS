## DECS Docker Images

DECS 이미지는 GPU/driver 호환성을 관리하기 위해 CUDA variant별로 빌드한다. 공통 Dockerfile은 하나만 유지하고, 실제 CUDA/TensorFlow 조합은 `image-variants.json`에서 관리한다.

## Image Variants

| Variant tag | CUDA | TensorFlow | Base image | 최소 NVIDIA driver | 상태 |
| --- | --- | --- | --- | --- | --- |
| `cuda11.8-tf2.13-ubuntu22.04-260515` | 11.8 | 2.13.0 | `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04` | 520.61.05 | stable |
| `cuda12.2-tf2.15-ubuntu22.04-260515` | 12.2 | 2.15.0 | `nvidia/cuda:12.2.2-cudnn8-devel-ubuntu22.04` | 535.104.05 | stable |
| `cuda12.5-tf2.20-ubuntu22.04-260515` | 12.5 | 2.20.0 | `nvidia/cuda:12.5.1-cudnn-devel-ubuntu22.04` | 555.42.06 | stable |
| `cuda12.8-tf2.20-ubuntu22.04-260515` | 12.8 | 2.20.0 | `nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04` | 570.124.06 | experimental |

Alias tags:

| Alias | Target |
| --- | --- |
| `latest`, `stable`, `cuda12.5-tf2.20` | CUDA 12.5 / TensorFlow 2.20 |
| `legacy`, `cuda11.8-tf2.13` | CUDA 11.8 / TensorFlow 2.13 |
| `cuda12.2-tf2.15` | CUDA 12.2 / TensorFlow 2.15 |
| `cuda12.8-tf2.20`, `h200-experimental` | CUDA 12.8 / TensorFlow 2.20 |

TensorFlow 공식 빌드 구성 기준으로 TensorFlow 2.20.0은 CUDA 12.5/cuDNN 9.3 조합이다. CUDA 12.8 이미지는 H200/LAB10 검증 전까지 experimental로 둔다.

## Included Runtime

모든 variant는 다음을 포함한다.

- CUDA/cuDNN base image
- TensorFlow
- system packages: SSH, sudo, auditd, Korean fonts/input, Chrome, Xfce, TigerVNC, noVNC
- Miniforge under `/opt/conda`
- micromamba
- JupyterLab / Notebook / ipywidgets

`entrypoint.sh`는 시작 시 이미지 variant, CUDA/TensorFlow 버전, 요구 driver 버전, 실제 `nvidia-smi` 정보를 출력한다. `STRICT_CUDA_COMPAT=true`를 주면 host driver가 variant의 최소 driver보다 낮을 때 시작을 실패시킨다.

## Build

전체 variant dry-run:

```bash
python3 scripts/build_variants.py --dry-run
```

특정 variant build:

```bash
python3 scripts/build_variants.py --variant cuda12.5-tf2.20-ubuntu22.04
```

push까지 수행:

```bash
python3 scripts/build_variants.py --variant cuda12.5-tf2.20-ubuntu22.04 --push
```

GitHub Actions는 `main` 대상 PR이 merge되거나 `workflow_dispatch`로 실행될 때 `image-variants.json`을 읽어 matrix build/push를 수행한다.

## Usage

운영 스크립트(`~/uid/script/create_container.sh`)에서는 이미지 이름과 버전을 분리해서 전달한다.

```bash
bash ~/uid/script/create_container.sh \
  --image decs \
  --version cuda12.5-tf2.20-ubuntu22.04-260515
```

noVNC는 기존처럼 opt-in이다.

```bash
--enable-vnc true
```

관련 환경변수:

| 환경변수 | 기본값 | 설명 |
| --- | --- | --- |
| `ENABLE_VNC` | `false` | `true`이면 TigerVNC/noVNC를 시작한다. |
| `VNC_PASSWORD` | 랜덤 8자리 | 지정하지 않으면 `/home/$USER_ID/vnc_password.txt`에 저장한다. |
| `VNC_RESOLUTION` | `1920x1080` | VNC 화면 해상도 |
| `VNC_DEPTH` | `24` | VNC 색상 깊이 |
| `VNC_DISPLAY` | `1` | VNC display 번호. 기본 VNC 포트는 `5901` |
| `NOVNC_PORT` | `6080` | noVNC listen 포트 |
| `STRICT_CUDA_COMPAT` | `false` | 최소 NVIDIA driver 미만이면 startup 실패 |

## Tests

이 저장소 내부의 테스트 파일만 사용한다. 외부 `~/uid`와 ansible inventory는 호출 대상이다.

로컬 이미지 smoke test:

```bash
python3 scripts/test_image_variants.py --variant cuda12.5-tf2.20-ubuntu22.04
python3 scripts/test_image_variants.py --variant cuda12.5-tf2.20-ubuntu22.04 --gpu
```

`~/uid/script_test/create_container.sh` dry-run 연동 테스트:

```bash
python3 scripts/test_uid_create_container.py --variant cuda12.5-tf2.20-ubuntu22.04
```

LAB10 같은 실제 GPU host에서 ansible smoke test:

```bash
tar -czf /tmp/decs-build-context-260515.tgz Dockerfile entrypoint.sh .dockerignore

ansible-playbook \
  -i /home/jy/ansible/inventory.ini \
  tests/ansible/decs_image_build.yml \
  -e target_hosts=lab10 \
  -e image_tag=cuda12.8-tf2.20-ubuntu22.04-260515 \
  -e base_image=nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04 \
  -e decs_image_variant=cuda12.8-tf2.20-ubuntu22.04 \
  -e cuda_version=12.8 \
  -e tensorflow_version=2.20.0 \
  -e tensorflow_package=tensorflow==2.20.0 \
  -e min_nvidia_driver=570.124.06

ansible-playbook \
  -i /home/jy/ansible/inventory.ini \
  tests/ansible/decs_image_smoke.yml \
  -e target_hosts=lab10 \
  -e image_tag=cuda12.8-tf2.20-ubuntu22.04-260515
```

VNC까지 확인:

```bash
ansible-playbook \
  -i /home/jy/ansible/inventory.ini \
  tests/ansible/decs_image_smoke.yml \
  -e target_hosts=lab10 \
  -e image_tag=cuda12.5-tf2.20-ubuntu22.04-260515 \
  -e enable_vnc=true
```

## Admin Notes

관리자용 노션 문서:
https://www.notion.so/DECS-280c7692a263802ca40ff68b38f58dd1?source=copy_link
