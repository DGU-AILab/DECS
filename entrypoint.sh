#!/bin/bash

sudo apt update
sudo apt install -y auditd

# /etc/audit/audit.rules 파일에 줄 추가
# sed -i "/^#-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$USER_ID -k rm_commands" /etc/audit/audit.rules
echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$USER_ID -k rm_commands" >> /etc/audit/audit.rules

# history 명령어 칠 때 명령어를 입력한 시간이 같이 나오게 하는 명령어
echo 'HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "' >> /etc/profile
echo 'export HISTTIMEFORMAT' >> /etc/profile

if ! id "$USER_ID" >/dev/null 2>&1; then
    # 유저 디렉토리 존재하지 않는 경우, 디렉토리와 skel 생성
    if [ ! -d "/home/$USER_ID/" ]; then
        cp -R /etc/skel/. "/home/$USER_ID"
        chmod -R 700 "/home/$USER_ID"
        
        # history -w 현재시간.txt파일을 만들고, /var/log/audit로 이동하는 부분임. 사용자가 로그아웃 할 때
        echo 'cd ~' >> /home/$USER_ID/.bash_logout
        echo 'current_time=$(date +%Y-%m-%d_%H-%M-%S)' >> /home/$USER_ID/.bash_logout
        echo 'history -w $current_time.txt' >> /home/$USER_ID/.bash_logout
        echo 'sudo mv $current_time.txt /var/log/audit/' >> /home/$USER_ID/.bash_logout
    fi
    useradd -s /bin/bash -d /home/$USER_ID -u $UID $USER_ID

    # sudo 권한 제공
    echo "$USER_ID ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # 비밀번호 설정
    echo "$USER_ID:$USER_PW" | chpasswd

    # 소유권 지정
    chown -R "$USER_ID:$USER_ID" "/home/$USER_ID"

    # 서버관리자와 유저계정의 ssh 접속을 허용 및 다중접속 허용
    sed -i "/^#PermitRootLogin/a AllowUsers svmanager" /etc/ssh/sshd_config
    sed -i "/^#PermitRootLogin/a AllowUsers $USER_ID" /etc/ssh/sshd_config
    sed -i 's/^UsePAM yes/UsePAM no/' /etc/ssh/sshd_config
fi

if [ "$USER_ID" != "$USER_GROUP" ]; then
    groupadd -g $GID $USER_GROUP
    usermod -aG $USER_GROUP $USER_ID
    if [ ! -d "/home/$USER_GROUP/" ]; then
        # 폴더 생성
        mkdir /home/$USER_GROUP
        echo "Created /home/$USER_GROUP...."

        # 그룹의 공유 디렉토리의 모든 파일의 소유권 설정
        chown -R svmanager:$USER_GROUP /home/$USER_GROUP
        # 그룹의 공유 디렉토리의 권한 설정
        chmod -R 770 /home/$USER_GROUP
    fi
fi


# MOTD 공지 출력하도록 설정
sed -i 's/^#\?UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config
cat <<EOF > /etc/default/motd-news
ENABLED=1
echo "\e[0;33m
서버에서 사용 중인 데이터는 언제 장애가 발생해서 사라질지 모릅니다.
항상 중요한 데이터는 서버 밖에 백업해두시기 바랍니다.
Data on the server can be lost at any time due to unexpected failures.
Always back up important data outside the server.

Slack에 공지 후 24시간 이내에 확인 및 응답이 없어 발생하는 모든 불이익은
사용자 본인 책임입니다.
You are solely responsible for any disadvantages
resulting from failing to check and respond within 24 hours of a Slack notice.
\e[0m"
EOF

for file in /etc/update-motd.d/60-unminimize /etc/update-motd.d/10-help-text; do
    if [[ -f "$file" ]]; then
        sed -i '/^[^#]/ s/^/#/' "$file"
    fi
done
sed -i.bak '/echo -e "\\e\[1;31m"/d; /cat<<TF/,/TF/d' /etc/bash.bashrc

if [[ -f "/etc/legal" ]]; then
    rm /etc/legal
fi

# ssh restart
service ssh restart

# jupyter lab 에서 생성한 ipynb 파일을 저장할 디렉토리 생성 (없는경우만 신규 생성)
if [ ! -d "/home/$USER_ID/decs_jupyter_lab" ]; then
  mkdir /home/$USER_ID/decs_jupyter_lab
  echo "Created /home/$USER_ID/decs_jupyter_lab dir...."
fi


# 해당 경로에 config 파일을 생성 - 직접 생성
jupyter notebook --generate-config --config

cp /home/$USER_ID/.jupyter/jupyter_notebook_config.py /jupyter_config/jupyter_notebook_config.py


echo "Config 파일 생성 완료"


# jupyter lab 접속 설정
sed -i "1i c.JupyterApp.config_file_name = 'jupyter_notebook_config.py'\nc.NotebookApp.allow_origin = '*'\nc.NotebookApp.ip = '0.0.0.0'\nc.NotebookApp.open_browser = False\nc.NotebookApp.allow_remote_access = True\nc.NotebookApp.allow_root = True\nc.NotebookApp.notebook_dir='/home/$USER_ID/decs_jupyter_lab'" /jupyter_config/jupyter_notebook_config.py

# Jupyter Lab 토큰을 랜덤 문자열로 생성하고 저장
TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
echo "$TOKEN" > /home/$USER_ID/decs_jupyter_lab/jupyter_token.txt
chmod 600 /home/$USER_ID/decs_jupyter_lab/jupyter_token.txt
chown $USER_ID:$USER_ID /home/$USER_ID/decs_jupyter_lab/jupyter_token.txt

# jupyter_lab 기동
echo "trying jupyter lab..."
nohup /opt/anaconda3/bin/jupyter lab --NotebookApp.token=$TOKEN --config=/jupyter_config/jupyter_notebook_config.py >/dev/null 2>&1 &
echo "jupyter lab listening!"

# ldconfig permission 오류 방지
# bash.bashrc에서 ldconfig 명령어 삭제 후 명령어 실행 및 결과 출력
sed -i '/ldconfig/d' /etc/bash.bashrc
ldconfig && echo "ldconfig executed successfully" || echo "ldconfig failed"

#entrypoint.sh 를 실행하고 나서 컨테이너가 Exit 하지 않게함
tail -F /dev/null
