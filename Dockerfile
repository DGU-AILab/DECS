# DECS CUDA/TensorFlow image template.
# Build variants are defined in image-variants.json and passed as build args.

ARG BASE_IMAGE=nvidia/cuda:12.5.1-cudnn-devel-ubuntu22.04
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG DECS_IMAGE_VARIANT=cuda12.5-tf2.20-ubuntu22.04
ARG CUDA_VERSION=12.5
ARG TENSORFLOW_VERSION=2.20.0
ARG TENSORFLOW_PACKAGE=tensorflow==2.20.0
ARG PYTHON_VERSION=3.10
ARG UBUNTU_VERSION=22.04
ARG MIN_NVIDIA_DRIVER=555.42.06
ARG MINIFORGE_VERSION=25.3.1-0

LABEL org.opencontainers.image.base.name="${BASE_IMAGE}" \
      ai.dgu.decs.variant="${DECS_IMAGE_VARIANT}" \
      ai.dgu.decs.cuda="${CUDA_VERSION}" \
      ai.dgu.decs.tensorflow="${TENSORFLOW_VERSION}" \
      ai.dgu.decs.python="${PYTHON_VERSION}" \
      ai.dgu.decs.ubuntu="${UBUNTU_VERSION}" \
      ai.dgu.decs.min_nvidia_driver="${MIN_NVIDIA_DRIVER}"

ENV DEBIAN_FRONTEND=noninteractive \
    CONDA_DIR=/opt/conda \
    DECS_IMAGE_VARIANT="${DECS_IMAGE_VARIANT}" \
    DECS_CUDA_VERSION="${CUDA_VERSION}" \
    DECS_TENSORFLOW_VERSION="${TENSORFLOW_VERSION}" \
    DECS_PYTHON_VERSION="${PYTHON_VERSION}" \
    DECS_MIN_NVIDIA_DRIVER="${MIN_NVIDIA_DRIVER}" \
    SUDOER_ID=svmanager \
    SUDOER_PW=decs2260 \
    SUDOER_DIR=/svmanager \
    SSHD_CONFIG_PATH=/etc/ssh/sshd_config

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        auditd \
        ca-certificates \
        curl \
        dbus-x11 \
        fcitx-hangul \
        fonts-nanum \
        fonts-nanum-coding \
        fonts-nanum-extra \
        gnupg \
        net-tools \
        novnc \
        openssh-server \
        software-properties-common \
        sudo \
        tigervnc-common \
        tigervnc-standalone-server \
        update-motd \
        vim \
        websockify \
        wget \
        xfce4 \
        xfce4-terminal \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$SUDOER_DIR" /home/decs /run/sshd \
    && useradd -s /bin/bash -d "$SUDOER_DIR" -G sudo "$SUDOER_ID" \
    && echo "$SUDOER_ID ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && cp -R /etc/skel/. "$SUDOER_DIR" \
    && echo "$SUDOER_ID:$SUDOER_PW" | chpasswd

RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

RUN printf 'LANG="ko_KR.UTF-8"\nLANGUAGE="ko_KR:ko:en_GB:en"\n' >> /etc/environment \
    && fc-cache -r

RUN wget -q "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-Linux-x86_64.sh" \
    && bash Miniforge3-Linux-x86_64.sh -b -p "$CONDA_DIR" \
    && rm Miniforge3-Linux-x86_64.sh

ENV PATH=/opt/conda/bin:$PATH

RUN conda config --system --set channel_priority strict \
    && conda config --system --add channels conda-forge \
    && conda install -n base -y \
        "python=${PYTHON_VERSION}" \
        ipywidgets \
        jupyterlab \
        micromamba \
        notebook \
        pip \
    && python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir "${TENSORFLOW_PACKAGE}" \
    && conda clean -afy \
    && conda init bash

RUN apt-get update \
    && apt-get install -y --no-install-recommends tigervnc-tools \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /jupyter_config \
    && touch /jupyter_config/jupyter_notebook_config.py

COPY entrypoint.sh /

# noVNC listens on 6080. The TigerVNC server binds to localhost only.
EXPOSE 6080

RUN chmod +x /entrypoint.sh
ENTRYPOINT ["bash", "/entrypoint.sh"]
