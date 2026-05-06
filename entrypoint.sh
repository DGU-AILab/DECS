#!/bin/bash

USER_PW="${USER_PW:-ailab2260}"

start_novnc() {
    case "${ENABLE_VNC:-false}" in
        true|TRUE|1|yes|YES|on|ON) ;;
        *)
            echo "VNC/noVNC disabled. Set ENABLE_VNC=true to enable it."
            return 0
            ;;
    esac

    local user_home="/home/$USER_ID"
    local vnc_dir="$user_home/.vnc"
    local vnc_display="${VNC_DISPLAY:-1}"
    local vnc_resolution="${VNC_RESOLUTION:-1920x1080}"
    local vnc_depth="${VNC_DEPTH:-24}"
    local novnc_port="${NOVNC_PORT:-6080}"
    local vnc_password_file="$user_home/vnc_password.txt"
    local vnc_password

    vnc_display="${vnc_display#:}"
    if ! [[ "$vnc_display" =~ ^[0-9]+$ && "$novnc_port" =~ ^[0-9]+$ && "$vnc_depth" =~ ^[0-9]+$ ]]; then
        echo "Invalid VNC configuration. Check VNC_DISPLAY, NOVNC_PORT, and VNC_DEPTH."
        return 1
    fi
    local vnc_port=$((5900 + vnc_display))

    if ! command -v vncserver >/dev/null 2>&1 || ! command -v websockify >/dev/null 2>&1; then
        echo "VNC/noVNC packages are not installed. Skipping GUI startup."
        return 0
    fi

    mkdir -p "$vnc_dir" "$user_home/decs_jupyter_lab" /tmp/.X11-unix /tmp/.ICE-unix
    chown root:root /tmp/.X11-unix /tmp/.ICE-unix
    chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix

    if [[ -n "${VNC_PASSWORD:-}" ]]; then
        vnc_password="$VNC_PASSWORD"
    elif [[ -s "$vnc_password_file" ]]; then
        vnc_password=$(tr -d '\r\n' < "$vnc_password_file" | head -c 8)
    else
        vnc_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    fi
    vnc_password="${vnc_password:0:8}"

    if [[ -z "$vnc_password" ]]; then
        echo "Failed to prepare VNC password. Skipping GUI startup."
        return 1
    fi

    printf "%s\n" "$vnc_password" > "$vnc_password_file"
    chmod 600 "$vnc_password_file"

    printf "%s\n" "$vnc_password" | vncpasswd -f > "$vnc_dir/passwd"
    chmod 600 "$vnc_dir/passwd"

    cat > "$vnc_dir/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XKL_XMODMAP_DISABLE=1
xrdb "$HOME/.Xresources" 2>/dev/null || true
exec dbus-launch --exit-with-session startxfce4
EOF
    chmod +x "$vnc_dir/xstartup"
    chown -R "$USER_ID:$USER_GROUP" "$vnc_dir" "$vnc_password_file"

    sudo -u "$USER_ID" env HOME="$user_home" USER="$USER_ID" \
        vncserver -kill ":$vnc_display" >/tmp/vnc-kill.log 2>&1 || true

    echo "trying TigerVNC on localhost:$vnc_port..."
    if ! sudo -u "$USER_ID" env HOME="$user_home" USER="$USER_ID" \
        vncserver -localhost yes ":$vnc_display" -geometry "$vnc_resolution" -depth "$vnc_depth" >/tmp/vncserver.log 2>&1; then
        echo "TigerVNC startup failed. See /tmp/vncserver.log."
        cat /tmp/vncserver.log
        return 1
    fi
    echo "TigerVNC listening on localhost:$vnc_port"

    if [[ -d /usr/share/novnc && -f /usr/share/novnc/vnc.html ]]; then
        ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html
    fi

    pkill -f "websockify.*$novnc_port" >/dev/null 2>&1 || true
    echo "trying noVNC on 0.0.0.0:$novnc_port..."
    nohup websockify --web=/usr/share/novnc "0.0.0.0:$novnc_port" "localhost:$vnc_port" >/tmp/novnc.log 2>&1 &
    echo "noVNC listening on port $novnc_port. VNC password saved to $vnc_password_file"
}

sudo apt update
sudo apt install -y auditd

# /etc/audit/audit.rules 파일에 줄 추가
echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$USER_ID -k rm_commands" >> /etc/audit/audit.rules

# history 명령어 칠 때 명령어를 입력한 시간이 같이 나오게 하는 명령어
echo 'HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "' >> /etc/profile
echo 'export HISTTIMEFORMAT' >> /etc/profile

if ! id "$USER_ID" >/dev/null 2>&1; then
    # 유저 디렉토리 존재하지 않는 경우, 디렉토리와 skel 생성
    if [ ! -d "/home/$USER_ID/" ]; then
        cp -R /etc/skel/. "/home/$USER_ID"
        chmod -R 700 "/home/$USER_ID" # 초기 권한 설정 후 아래에서 변경
        
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

    # 서버관리자와 유저계정의 ssh 접속을 허용 및 다중접속 허용
    sed -i "/^#PermitRootLogin/a AllowUsers svmanager" /etc/ssh/sshd_config
    sed -i "/^#PermitRootLogin/a AllowUsers $USER_ID" /etc/ssh/sshd_config
    sed -i 's/^UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

else

    # 기존 유저 디렉토리의 /.bashrc에서 conda initialize 블록과 경고 주석을 제거
    sed -i \
        -e "/# !!! Do NOT delete the conda initialize comments below\. !!!/d" \
        -e "/# !!! Do NOT add anything inside the conda initialize block\. It will be removed on container restart\/update\. !!!/d" \
        -e "/# >>> conda initialize >>>/,/# <<< conda initialize <<</d" \
        /home/$USER_ID/.bashrc

    # /root/.bashrc에서 conda initialize 블록 추출해서 /home/$USER_ID/.bashrc에 추가
    {
        echo "# !!! Do NOT delete the conda initialize comments below. !!!"
        echo "# !!! Do NOT add anything inside the conda initialize block. It will be removed on container restart/update. !!!"
        sed -n '/# >>> conda initialize >>>/,/# <<< conda initialize <<</p' /root/.bashrc
    } >> /home/$USER_ID/.bashrc

fi

# 그룹이 존재하지 않을 경우 생성하고 사용자를 그룹에 추가
if ! getent group "$USER_GROUP" >/dev/null 2>&1; then
    groupadd -g $GID "$USER_GROUP"
fi
usermod -aG "$USER_GROUP" "$USER_ID"

# 사용자와 그룹이 모두 준비된 후, 소유권과 권한을 설정합니다.
chown -R "$USER_ID:$USER_GROUP" "/home/$USER_ID"
chmod 750 "/home/$USER_ID"


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

# 의도되지 않은 MOTD 출력 방지
sed -i.bak '/^[[:space:]]*else[[:space:]]*$/,/^[[:space:]]*EXPL[[:space:]]*$/d' /etc/bash.bashrc

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

# jupyter lab config 파일이 없으면 생성
mkdir -p /home/$USER_ID/.jupyter/

if [ ! -f /home/$USER_ID/.jupyter/jupyter_notebook_config.py ]; then
        echo "jupyter_notebook_config.py not found, generating..."
        /opt/anaconda3/bin/jupyter notebook --generate-config
        cp /root/.jupyter/jupyter_notebook_config.py /home/$USER_ID/.jupyter/
else
        echo "jupyter_notebook_config.py already exists."
fi

# jupyter lab 접속 설정
sed -i "1i c.JupyterApp.config_file_name = 'jupyter_notebook_config.py'\nc.NotebookApp.allow_origin = '*'\nc.NotebookApp.ip = '0.0.0.0'\nc.NotebookApp.open_browser = False\nc.NotebookApp.allow_remote_access = True\nc.NotebookApp.allow_root = True\nc.NotebookApp.notebook_dir='/home/$USER_ID/decs_jupyter_lab'" /home/$USER_ID/.jupyter/jupyter_notebook_config.py

# Jupyter Lab 토큰을 랜덤 문자열로 생성하고 저장
TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
echo "$TOKEN" > /home/$USER_ID/decs_jupyter_lab/jupyter_token.txt
chmod 600 /home/$USER_ID/decs_jupyter_lab/jupyter_token.txt
chown $USER_ID:$USER_ID /home/$USER_ID/decs_jupyter_lab/jupyter_token.txt

# jupyter_lab 기동
echo "trying jupyter lab..."
nohup /opt/anaconda3/bin/jupyter lab --NotebookApp.token=$TOKEN --config=/home/$USER_ID/.jupyter/jupyter_notebook_config.py >/dev/null 2>&1 &
echo "jupyter lab listening!"

# noVNC 기동. 외부에서는 컨테이너의 6080 포트를 매핑해서 접속합니다.
start_novnc || echo "VNC/noVNC startup failed."

# ldconfig permission 오류 방지
# bash.bashrc에서 ldconfig 명령어 삭제 후 명령어 실행 및 결과 출력
sed -i '/ldconfig/d' /etc/bash.bashrc
ldconfig && echo "ldconfig executed successfully" || echo "ldconfig failed"

#entrypoint.sh 를 실행하고 나서 컨테이너가 Exit 하지 않게함
tail -F /dev/null
