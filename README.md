## DECS Docker Images

DECS 이미지는 GPU/driver 호환성을 관리하기 위해 CUDA variant별로 빌드한다. 공통 Dockerfile은 하나만 유지하고, 실제 CUDA/TensorFlow 조합은 `image-variants.json`에서 관리한다.

## Image Variants

| Variant tag | CUDA | TensorFlow | Base image | 최소 NVIDIA driver | 상태 |
| --- | --- | --- | --- | --- | --- |
| `cuda11.8-tf2.13-ubuntu22.04-260621` | 11.8 | 2.13.0 | `nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04` | 520.61.05 | stable |
| `cuda12.2-tf2.15-ubuntu22.04-260621` | 12.2 | 2.15.0 | `nvidia/cuda:12.2.2-cudnn8-devel-ubuntu22.04` | 535.104.05 | stable |
| `cuda12.5-tf2.20-ubuntu22.04-260621` | 12.5 | 2.20.0 | `nvidia/cuda:12.5.1-cudnn-devel-ubuntu22.04` | 555.42.06 | stable |
| `cuda12.8-tf2.20-ubuntu22.04-260621` | 12.8 | 2.20.0 | `nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04` | 570.124.06 | experimental |

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
- system packages: SSH, sudo, auditd, Kerberos client, Korean fonts/input, Chrome, Xfce, TigerVNC, noVNC
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
  --version cuda12.5-tf2.20-ubuntu22.04-260621
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
| `KRB5CCNAME` | unset | Kerberos ccache path. 설정하면 사용자 shell/Jupyter/noVNC 환경에도 전달한다. |
| `DECS_KRB5CCNAME` | unset | `KRB5CCNAME` fallback. |
| `KRB5_REALM` | `FARM.DECS.INTERNAL` | `DECS_KRB5_PRINCIPAL` 기본값을 만들 때 쓰는 realm. |
| `DECS_KRB5_PRINCIPAL` | `$USER_ID@$KRB5_REALM` | 이 컨테이너가 기대하는 Kerberos principal. |
| `DECS_KERBEROS_HOST_KEYTAB` | `false` | `true`이면 사용자가 `kinit`하는 대신 host-side keytab refresh가 ccache를 만든다고 보고 대기한다. |
| `DECS_DISABLE_USER_SUDO` | `false` | `true`이면 생성 사용자에게 passwordless sudo를 주지 않고 기존 `/etc/sudoers.d/$USER_ID`도 제거한다. Kerberized NFS에서는 UID spoofing 방지를 위해 켜야 한다. |

Kerberized NFS 모드에서는 `~/uid/script/create_container.sh --enable-kerberos true`가 host ccache directory를 컨테이너에 bind mount하고 `KRB5CCNAME`을 설정한다. host는 root-only keytab으로 `kinit -kt`를 수행해 ticket을 만들고, 컨테이너에는 keytab 없이 ccache만 공유한다. ticket 상태는 컨테이너 안에서 `decs-kerberos-status`로 확인할 수 있다. 이 모드에서는 사용자가 container root가 되면 다른 UID로 전환해 host의 다른 ccache를 사용할 수 있으므로 `DECS_DISABLE_USER_SUDO=true`로 passwordless sudo를 비활성화해야 한다.

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
tar -czf /tmp/decs-build-context-260621.tgz Dockerfile entrypoint.sh .dockerignore

ansible-playbook \
  -i /home/jy/ansible/inventory.ini \
  tests/ansible/decs_image_build.yml \
  -e target_hosts=lab10 \
  -e image_tag=cuda12.8-tf2.20-ubuntu22.04-260621 \
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
  -e image_tag=cuda12.8-tf2.20-ubuntu22.04-260621
```

VNC까지 확인:

```bash
ansible-playbook \
  -i /home/jy/ansible/inventory.ini \
  tests/ansible/decs_image_smoke.yml \
  -e target_hosts=lab10 \
  -e image_tag=cuda12.5-tf2.20-ubuntu22.04-260621 \
  -e enable_vnc=true
```

## Admin Notes

관리자용 노션 문서:
https://www.notion.so/DECS-280c7692a263802ca40ff68b38f58dd1?source=copy_link
