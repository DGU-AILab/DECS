FROM tensorflow/tensorflow:2.5.0rc1-gpu
# # 설치 시 geographic area 를 물어보지 않도록 설정(apt install 시 interrupted 됨)
ENV DEBIAN_FRONTEND noninteractive

ENV SUDOER_ID svmanager
ENV SUDOER_PW decs2260
ENV SUDOER_DIR /home/$SUDOER_ID
ENV SSHD_CONFIG_PATH /etc/ssh/sshd_config

RUN apt-get clean \
&& apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A4B469963BF863CC \
&& apt-get -y update \
&& apt install -y \
sudo \
net-tools \
fcitx-hangul \
fonts-nanum* \
vim \
wget \
curl \
ssh \
software-properties-common 

# # 관리자 계정 추가
RUN useradd -s /bin/bash -d /home/$SUDOER_ID -m -G sudo $SUDOER_ID \
    && echo "$SUDOER_ID ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN echo $SUDOER_ID:$SUDOER_PW | chpasswd
RUN chown -R $SUDOER_ID:$SUDOER_ID "$SUDOER_DIR"

# decs dir 을 생성
RUN mkdir /home/decs

RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
    && apt-get update && apt-get install -y google-chrome-stable

RUN printf "LANG=\"ko_KR.UTF-8\"\nLANG=\"ko_KR.EUC-KR\"\nLANGUAGE=\"ko_KR:ko:en_GB:en\"\n" >> /etc/environment \
&& fc-cache -r

RUN cat /etc/environment

# xrdp 실행을 위한 그래픽 인터페이스 설치
RUN apt-get install -y xrdp xfce4 xfce4-terminal


# Anaconda 설치 및 환경설정
RUN wget https://repo.anaconda.com/archive/Anaconda3-2020.02-Linux-x86_64.sh \
    && bash Anaconda3-2020.02-Linux-x86_64.sh -b -p /opt/anaconda3 \
    && rm Anaconda3-2020.02-Linux-x86_64.sh

ENV PATH opt/anaconda3/bin:$PATH
RUN echo "export PATH="/opt/anaconda3/bin:$PATH >> /etc/profile \
    && /opt/anaconda3/bin/conda init

# jupyterlab 설치
RUN /opt/anaconda3/bin/conda install -y jupyterlab

# jupyterlab 설정파일 생성
RUN mkdir /jupyter_config \
    && /opt/anaconda3/bin/jupyter lab --generate-config --config=/jupyter_config/jupyter_notebook_config.py

# jupyterlab 설정파일 수정

# jupyter lab 에서 생성한 ipynb 파일을 저장할 디렉토리 생성
RUN mkdir /home/decs/decs_jupyter_lab

# jupyter lab 접속
RUN sudo sed -i \
'1i c.JupyterApp.config_file_name = "jupyter_notebook_config.py"\nc.NotebookApp.allow_origin = "*"\nc.NotebookApp.ip = "0.0.0.0"\nc.NotebookApp.open_browser = False\nc.NotebookApp.allow_remote_access = True\nc.NotebookApp.allow_root = True\nc.NotebookApp.notebook_dir="/home/decs/decs_jupyter_lab"' /jupyter_config/jupyter_notebook_config.py


# entrypoint.sh 복사
COPY entrypoint.sh /

# SSHD 서버를 실행하고, entrypoint 파일을 start/restart 시 마다 실행, dev/null에 entrypoint 로그를 저장
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["bash", "/entrypoint.sh"]
