#!/bin/bash

# 이 파일은 decs:241102 이미지의 entrypoint.sh 입니다.

############################# version history #############################

###### decs:1.4 변경 사항 ######
# 변경한 사람: 박민균 관리자
# ssh 다중 접속을 허용하도록 변경함.
# 컨테이너 생성 시 ssh 서비스를 시작하도록 설정을 변경함.

##### decs:1.4.18 변경 사항 #####
# 변경한 사람: 박민균 관리자
# USER_GROUP 환경 변수를 이용하여 그룹 기능을 구현함.
## 그룹 디렉토리가 없는 경우(신규 그룹) 생성
## 그룹 추가, 등록, 권한 설정

##### decs:241102 #####
# 변경한 사람: 김민기 관리자
# USER_GROUP 환경 변수가 설정되지 않은 경우 그룹 기능이 활성화되지 않도록 수정함.
# 64번째 줄에 ssh restart 코드가 빠져 있어 추가 하였음
## decs:1.4.18에서는 USER_GROUP이 설정되어 있지 않더라도 그룹 디렉토리 생성, 그룹 추가, 등록, 권한 설정을 수행함.
## 그 결과 다른 유저들 디렉토리의 소유자, 그룹, 권한이 모두 변경되는 오류가 발생했었음.

##### decs:250113 ####
# 변경한 사람: 임준영 관리자
# 241102 이미지를 이용하여 생성한 컨테이너를 재시작하는 경우,
# 이미 USER_GROUP 디렉토리가 존재하지만 chown -R 명령어를 실행하는 문제가 있음.
# 또한 USER_NAME과 USER_GROUP이 동일한 경우, user 디렉토리 자체 소유권 svmanager로 변경되는 문제가 있음.
# 이를 해결하기 위해 /home/$USER_GROUP 디렉토리가 존재하지 않는 경우에만 명령어를 실행하도록 변경함.


########################### version history end ##########################


# sudo docker logs [container_name] 으로 로그 확인 가능
echo "hello entrypoint!"

echo -e "\n\n -------------------------------------------------------------------------------------------------------------------------------------------- 
\n\n 안녕하세요. 동국대학교 AI lab 입니다. \n\n 해당 컨테이너는 sudo권한을 가집니다. 
\n 따라서, 컨테이너 또는 컨테이너가 실행중인 로컬서버에 해가 되는 행동을 할 시 사용자분에게 전적인 책임이 있음을 안내드립니다. 
\n 디렉토리 또는 파일을 삭제하는 행위 또는 root 권한을 통해 시스템을 수정하는 명령어 등을 조심히 사용해주시면 됩니다.  
\n 추가로, 사용자분의 디렉토리는 별도로 백업되지 않습니다. 중요한 파일의 경우 주기적으로 백업해 주시기 바랍니다. 감사합니다.
\n (이미지 버전 : decs:1.4) \n\n
--------------------------------------------------------------------------------------------------------------------------------------------\n" > /etc/motd
# 유저 계정 생성
if ! id "$USER_ID" >/dev/null 2>&1; then
    echo "No User account detected..."

    # 유저 계정을 생성, 홈폴더는 decs폴더로 설정
    useradd -s /bin/bash -d /$USER_ID $USER_ID
    # sudo 권한을 준다.
    echo "$USER_ID ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # 홈폴더 생성
    # skeleton 파일을 복사하여, 유저명이 tf-docker 로 표시되는 것을 방지
    cp -R /etc/skel/. "/home/$USER_ID"
    usermod -d "/home/$USER_ID" "$USER_ID"

    # 입력받은 비밀번호로 유저 계정 변경
    echo "$USER_ID:$USER_PW" | chpasswd

    echo "user account config done..."
    
    # sshd 설정도 바꾼다.
    # 서버관리자와 유저계정의 ssh 접속을 허용 및 다중접속 허용
    sed -i "/^#PermitRootLogin/a AllowUsers svmanager" /etc/ssh/sshd_config
    sed -i "/^#PermitRootLogin/a AllowUsers $USER_ID" /etc/ssh/sshd_config
    sed -i 's/^UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

    # 24년 11월 18일 추가 - ssh 서비스 재시작 코드 추가
    service ssh restart
    echo "ssh change done..."

fi

# 그룹 기능(여러 사용자가 동일한 폴더에 접근 가능)
# 2024년 11월 02일 추가 - $USER_GROUP 환경 변수값이 있을 때만 그룹 관련 명령을 실행
# 2025년 01월 13일 추가 - /home/$USER_GROUP 디렉토리가 존재하지 않을 때에만 디렉토리를 생성하고, 해당 디렉토리 소유권을 수정하도록 변경
if [ -n "$USER_GROUP" ]; then

  # 그룹 추가, 등록, 권한 설정
  groupadd $USER_GROUP
  usermod -aG $USER_GROUP $USER_ID
  if [ ! -d "/home/$USER_GROUP/" ]; then
    # 폴더 생성
    mkdir /home/$USER_GROUP
    echo "Created /home/$USER_GROUP...."

    # 그룹의 공유 디렉토리의 모든 파일의 소유권 설정
    chown -R svmanager:$USER_GROUP /home/$USER_GROUP
    chmod -R 770 /home/$USER_GROUP

    # 그룹의 공유 디렉토리의 권한 설정
    chmod g+rw /home/$USER_GROUP
    echo "Group Permission Setting done"
  fi
fi

# UID, GID 설정 (UID가 기본적으로 1001로 시작되는데, 컨테이너끼리 겹치면 접근 제한 불가)
groupmod -g $UID $USER_ID
usermod -u $UID -g $UID $USER_ID

# readme 안내문 생성
echo "Hello Decs, 동국대학교 GPU 서버 컨테이너 서비스 decs 입니다." > /home/$USER_ID/readme_decs.txt

# ssh restart
service ssh restart

# jupyter lab 에서 생성한 ipynb 파일을 저장할 디렉토리 생성 (없는경우만 신규 생성)
if [ ! -d "/home/$USER_ID/decs_jupyter_lab" ]; then
  mkdir /home/$USER_ID/decs_jupyter_lab
  echo "Created /home/$USER_ID/decs_jupyter_lab dir...."
fi

# jupyter lab 접속 설정
sed -i "1i c.JupyterApp.config_file_name = 'jupyter_notebook_config.py'\nc.NotebookApp.allow_origin = '*'\nc.NotebookApp.ip = '0.0.0.0'\nc.NotebookApp.open_browser = False\nc.NotebookApp.allow_remote_access = True\nc.NotebookApp.allow_root = True\nc.NotebookApp.notebook_dir='/home/$USER_ID/decs_jupyter_lab'" /jupyter_config/jupyter_notebook_config.py

# jupyter_lab 기동
echo "trying jupyter lab..."
nohup /opt/anaconda3/bin/jupyter lab --NotebookApp.token=decs --config=/jupyter_config/jupyter_notebook_config.py >/dev/null 2>&1 &
echo "jupyter lab listening!"

# auditd 설치
sudo apt update
sudo apt install -y auditd

# /etc/audit/audit.rules 파일에 줄 추가
# sed -i "/^#-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$USER_ID -k rm_commands" /etc/audit/audit.rules
echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$USER_ID -k rm_commands" >> /etc/audit/audit.rules

# history 명령어 칠 때 명령어를 입력한 시간이 같이 나오게끔 하는 명령어
echo 'HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "' >> /etc/profile
echo 'export HISTTIMEFORMAT' >> /etc/profile

# history -w 현재시간.txt파일을 만들고, /var/log/audit로 이동하는 부분임. 사용자가 로그아웃 할 때
echo 'cd ~' >> /home/$USER_ID/.bash_logout
echo 'current_time=$(date +%Y-%m-%d_%H-%M-%S)' >> /home/$USER_ID/.bash_logout
echo 'history -w $current_time.txt' >> /home/$USER_ID/.bash_logout
echo 'sudo mv $current_time.txt /var/log/audit/' >> /home/$USER_ID/.bash_logout

# 유저 개인폴더 안에 프로그램을 모두 설치하고 나면, 유저 개인폴더의 모든 파일의 소유자를 유저로 변경. 시간이 약간 소요됨(재귀로 모든 파일의 권한을 변경.)
chown -R "$UID:$UID" "/home/$USER_ID"
chmod -R 700 "/home/$USER_ID"
echo "decs chown change done..."


#entrypoint.sh 를 실행하고 나서 컨테이너가 Exit 하지 않게함
tail -F /dev/null
