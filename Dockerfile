FROM tensorflow/tensorflow:2.6.0-gpu
# # 설치 시 geographic area 를 물어보지 않도록 설정(apt install 시 interrupted 됨)
ENV DEBIAN_FRONTEND noninteractive

ENV SUDOER_ID svmanager
ENV SUDOER_PW decs2260
ENV SUDOER_DIR /$SUDOER_ID
ENV SSHD_CONFIG_PATH /etc/ssh/sshd_config
# RUN apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub

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

# motd install
RUN apt-get update && apt-get install -y update-motd


# 관리자 계정의 home directory 로 쓸 폴더 추가(home은 nfs이므로, 다른 곳에 생성)
RUN mkdir "$SUDOER_DIR"
# 관리자 계정을 추가, home directory 를 위에서 생성한 폴더로 설정
RUN useradd -s /bin/bash -d /$SUDOER_ID -G sudo $SUDOER_ID \
    && echo "$SUDOER_ID ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
# skel 을 복사 (로그인 시 tf-docker 로 뜨지 않게 하는 목적)
RUN cp -R /etc/skel/. "$SUDOER_DIR"

RUN echo $SUDOER_ID:$SUDOER_PW | chpasswd


# decs dir 을 생성
RUN mkdir /home/decs

RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - \
    && sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list' \
    && apt-get update && apt-get install -y google-chrome-stable

RUN printf "LANG=\"ko_KR.UTF-8\"\nLANG=\"ko_KR.EUC-KR\"\nLANGUAGE=\"ko_KR:ko:en_GB:en\"\n" >> /etc/environment \
&& fc-cache -r

RUN cat /etc/environment


# # Anaconda 설치 및 환경설정
RUN wget https://repo.anaconda.com/archive/Anaconda3-2020.02-Linux-x86_64.sh \
    && bash Anaconda3-2020.02-Linux-x86_64.sh -b -p /opt/anaconda3 \
    && rm Anaconda3-2020.02-Linux-x86_64.sh

ENV PATH opt/anaconda3/bin:$PATH
RUN echo "export PATH="/opt/anaconda3/bin:$PATH >> /etc/profile \
    && /opt/anaconda3/bin/conda init

# # jupyterlab 설치
RUN /opt/anaconda3/bin/conda install -y jupyterlab

# # jupyterlab 설정파일 생성
RUN mkdir /jupyter_config \
    && /opt/anaconda3/bin/jupyter lab --generate-config --config=/jupyter_config/jupyter_notebook_config.py




# entrypoint.sh 복사
COPY entrypoint.sh /

# SSHD 서버를 실행하고, entrypoint 파일을 start/restart 시 마다 실행, dev/null에 entrypoint 로그를 저장
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["bash", "/entrypoint.sh"]
