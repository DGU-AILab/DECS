#!/bin/bash
set -euo pipefail

# 이 entrypoint는 root 권한으로 시작한다. 시스템 설정처럼 root가 필요한
# 초기화는 앞쪽에서 처리하고, 사용자 워크로드는 계정 파일 검증 후 gosu로
# 실제 사용자 권한으로 내려서 실행한다.
CONDA_DIR="${CONDA_DIR:-/opt/conda}"
JUPYTER_BIN="${JUPYTER_BIN:-$CONDA_DIR/bin/jupyter}"
USER_PW="${USER_PW:-ailab2260}"

: "${USER_ID:?USER_ID is required}"

# USER_ID/USER_GROUP/TARGET_UID/TARGET_GID는 config-server가 내려준다.
# /etc/passwd, /etc/group, /etc/shadow는 공용 계정 NFS 경로에서 마운트된다.
# 따라서 이 컨테이너 안에서 Linux 계정을 새로 만들거나 수정하면 안 된다.
USER_GROUP="${USER_GROUP:-$USER_ID}"
TARGET_UID="${TARGET_UID:-}"
TARGET_GID="${TARGET_GID:-${TARGET_UID:-}}"
USER_HOME="/home/$USER_ID"
JUPYTER_DIR="$USER_HOME/decs_jupyter_lab"
JUPYTER_CONFIG_DIR="$USER_HOME/.jupyter"
JUPYTER_CONFIG_FILE="$JUPYTER_CONFIG_DIR/jupyter_notebook_config.py"

is_truthy() {
    case "${1:-}" in
        true|TRUE|1|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

version_ge() {
    local current="$1"
    local required="$2"
    [[ "$(printf "%s\n%s\n" "$required" "$current" | sort -V | head -n1)" == "$required" ]]
}

print_image_runtime_info() {
    # 기본값은 non-fatal이다. GPU runtime 없이 시작되는 작업도 있을 수 있다.
    # host driver 버전이 부족할 때 반드시 실패시켜야 하는 스케줄링 정책이면
    # STRICT_CUDA_COMPAT=true를 사용한다.
    echo "DECS image variant: ${DECS_IMAGE_VARIANT:-unknown}"
    echo "DECS CUDA version: ${DECS_CUDA_VERSION:-unknown}"
    echo "DECS TensorFlow version: ${DECS_TENSORFLOW_VERSION:-unknown}"
    echo "DECS minimum NVIDIA driver: ${DECS_MIN_NVIDIA_DRIVER:-unknown}"

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "nvidia-smi not found. GPU runtime may not be attached."
        return 0
    fi

    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader || true

    local required_driver="${DECS_MIN_NVIDIA_DRIVER:-}"
    if [[ -z "$required_driver" ]]; then
        return 0
    fi

    local host_driver
    host_driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d '[:space:]')"
    if [[ -z "$host_driver" ]]; then
        echo "Could not read NVIDIA driver version from nvidia-smi."
        return 0
    fi

    if version_ge "$host_driver" "$required_driver"; then
        return 0
    fi

    local message="Host NVIDIA driver $host_driver is lower than required $required_driver for ${DECS_IMAGE_VARIANT:-this image}."
    if is_truthy "${STRICT_CUDA_COMPAT:-false}"; then
        echo "ERROR: $message"
        return 1
    fi

    echo "WARNING: $message Set STRICT_CUDA_COMPAT=true to fail startup."
}

ensure_account_matches_mounts() {
    # 계정 파일이 단일 데이터 베이스다. 여기서 빠르게 실패해야 사용자 NFS PVC와
    # 공유 그룹 볼륨의 UID/GID와 맞지 않는 로컬 계정이 조용히 생성되는 일을
    # 막을 수 있다.
    if [[ -z "$TARGET_UID" || -z "$TARGET_GID" ]]; then
        echo "[ERROR] TARGET_UID and TARGET_GID are required for mounted account files" >&2
        exit 1
    fi

    local passwd_entry
    local group_entry
    local actual_uid
    local actual_gid
    local actual_home
    local actual_group_gid

    passwd_entry="$(getent passwd "$USER_ID" || true)"
    if [[ -z "$passwd_entry" ]]; then
        echo "[ERROR] User '$USER_ID' not found in mounted /etc/passwd" >&2
        exit 1
    fi

    IFS=: read -r _ _ actual_uid actual_gid _ actual_home _ <<<"$passwd_entry"

    if [[ "$actual_uid" != "$TARGET_UID" ]]; then
        echo "[ERROR] USER_ID '$USER_ID' has uid '$actual_uid', expected '$TARGET_UID'" >&2
        exit 1
    fi

    if [[ "$actual_gid" != "$TARGET_GID" ]]; then
        echo "[ERROR] USER_ID '$USER_ID' has gid '$actual_gid', expected '$TARGET_GID'" >&2
        exit 1
    fi

    if [[ "$actual_home" != "$USER_HOME" ]]; then
        echo "[ERROR] USER_ID '$USER_ID' has home '$actual_home', expected '$USER_HOME'" >&2
        exit 1
    fi

    group_entry="$(getent group "$USER_GROUP" || true)"
    if [[ -z "$group_entry" ]]; then
        echo "[ERROR] Group '$USER_GROUP' not found in mounted /etc/group" >&2
        exit 1
    fi

    IFS=: read -r _ _ actual_group_gid _ <<<"$group_entry"
    if [[ "$actual_group_gid" != "$TARGET_GID" ]]; then
        echo "[ERROR] USER_GROUP '$USER_GROUP' has gid '$actual_group_gid', expected '$TARGET_GID'" >&2
        exit 1
    fi
}

ensure_local_sudoers() {
    # sudo는 root 소유가 아닌 sudoers 파일을 거부한다. Synology root_squash는
    # root가 NFS에 만든 파일을 nobody:nogroup로 저장하므로,
    # /etc/sudoers.d/$USER_ID는 NFS subPath가 아니라 컨테이너 로컬 파일이어야 함.
    local sudoers_file="/etc/sudoers.d/$USER_ID"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_ID" > "$sudoers_file"
    chown root:root "$sudoers_file"
    chmod 0440 "$sudoers_file"
}

ensure_sshd_allow_user() {
    # 컨테이너 재시작 시 sshd_config가 중복으로 오염되지 않도록 같은 작업을 같은 결과로(멱등성)
    # 처리한다. 환경에 따라 svmanager가 마운트된 passwd에 없을 수 있으므로,
    # 없는 사용자는 전체 워크로드 컨테이너를 중단하지 않고 건너뛴다.
    local user_name="$1"
    if ! getent passwd "$user_name" >/dev/null 2>&1; then
        echo "[WARN] Skipping AllowUsers for missing account '$user_name'" >&2
        return 0
    fi
    if ! grep -qxF "AllowUsers $user_name" /etc/ssh/sshd_config; then
        printf '\nAllowUsers %s\n' "$user_name" >> /etc/ssh/sshd_config
    fi
}

bootstrap_user_home() {
    # 홈 경로는 보통 NFS 기반 PVC다. 여기서는 런타임에 필요한 홈 디렉토리
    # 뼈대만 만들고, 소유권을 마운트된 계정 UID/GID에 맞춘다.
    # 워크로드 이미지 안에서 useradd/groupadd/chpasswd를 호출하지 않는다.
    mkdir -p "$USER_HOME"
    chown "$TARGET_UID:$TARGET_GID" "$USER_HOME"
    chmod 750 "$USER_HOME"

    local skel_file
    local src
    local dst
    for skel_file in .profile .bashrc .bash_logout; do
        src="/etc/skel/$skel_file"
        dst="$USER_HOME/$skel_file"
        if [[ -f "$src" && ! -e "$dst" ]]; then
            install -m 644 -o "$TARGET_UID" -g "$TARGET_GID" "$src" "$dst"
        fi
    done
}

start_novnc() {
    # GUI 기능은 opt-in이다. VNC/noVNC는 홈 디렉토리에 사용자 소유 상태 파일을
    # 쓰므로, root가 소켓과 로그 파일의 소유권을 준비한 뒤 USER_ID 권한으로 실행한다.
    if ! is_truthy "${ENABLE_VNC:-false}"; then
        echo "VNC/noVNC disabled. Set ENABLE_VNC=true to enable it."
        return 0
    fi

    local vnc_dir="$USER_HOME/.vnc"
    local vnc_display="${VNC_DISPLAY:-1}"
    local vnc_resolution="${VNC_RESOLUTION:-1920x1080}"
    local vnc_depth="${VNC_DEPTH:-24}"
    local novnc_port="${NOVNC_PORT:-6080}"
    local vnc_password_file="$JUPYTER_DIR/vnc_password.txt"
    local vnc_password

    vnc_display="${vnc_display#:}"
    if ! [[ "$vnc_display" =~ ^[0-9]+$ && "$novnc_port" =~ ^[0-9]+$ && "$vnc_depth" =~ ^[0-9]+$ ]]; then
        echo "Invalid VNC configuration. Check VNC_DISPLAY, NOVNC_PORT, and VNC_DEPTH."
        return 1
    fi
    local vnc_port=$((5900 + vnc_display))

    if ! command -v vncserver >/dev/null 2>&1 || ! command -v vncpasswd >/dev/null 2>&1 || ! command -v websockify >/dev/null 2>&1; then
        echo "VNC/noVNC packages are not installed. Skipping GUI startup."
        return 0
    fi

    mkdir -p "$vnc_dir" "$JUPYTER_DIR" /tmp/.X11-unix /tmp/.ICE-unix
    chown root:root /tmp/.X11-unix /tmp/.ICE-unix
    chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix

    if [[ -n "${VNC_PASSWORD:-}" ]]; then
        vnc_password="$VNC_PASSWORD"
    elif [[ -s "$vnc_password_file" ]]; then
        vnc_password=$(tr -d '\r\n' < "$vnc_password_file" | head -c 8 || true)
    else
        vnc_password=$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8 || true)
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
    chown -R "$TARGET_UID:$TARGET_GID" "$vnc_dir" "$vnc_password_file"

    gosu "$USER_ID:$USER_GROUP" env HOME="$USER_HOME" USER="$USER_ID" \
        vncserver -kill ":$vnc_display" >/tmp/vnc-kill.log 2>&1 || true

    echo "trying TigerVNC on localhost:$vnc_port..."
    if ! gosu "$USER_ID:$USER_GROUP" env HOME="$USER_HOME" USER="$USER_ID" \
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
    # websockify는 비특권 포트에서 사용자 권한으로 실행된다. /tmp 소유권을
    # 관리할 수 있는 root 구간에서 로그 파일을 미리 만들어 둔다.
    : > /tmp/novnc.log
    chown "$TARGET_UID:$TARGET_GID" /tmp/novnc.log
    chmod 640 /tmp/novnc.log
    echo "trying noVNC on 0.0.0.0:$novnc_port..."
    nohup gosu "$USER_ID:$USER_GROUP" env HOME="$USER_HOME" USER="$USER_ID" \
        websockify --web=/usr/share/novnc "0.0.0.0:$novnc_port" "localhost:$vnc_port" \
        >/tmp/novnc.log 2>&1 &
    echo "noVNC listening on port $novnc_port. VNC password saved to $vnc_password_file"
}

# root 권한이 필요한 시작 구간.
print_image_runtime_info || exit 1
ensure_account_matches_mounts
ensure_local_sudoers

# audit rule의 auid는 마운트된 계정 파일의 숫자 UID를 사용한다.
# USER_ID는 사용자 이름이므로 유효한 auid 값이 아니다.
echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$TARGET_UID -k rm_commands" >> /etc/audit/audit.rules

echo 'HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "' >> /etc/profile
echo 'export HISTTIMEFORMAT' >> /etc/profile

bootstrap_user_home

# SSH/MOTD 설정은 root 소유 시스템 설정으로 유지한다. SSH로 생성되는 사용자
# shell 프로세스는 config-server가 제공한 passwd/group 기준으로 실행된다.
sed -i 's/^#\?UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config
ensure_sshd_allow_user "svmanager"
ensure_sshd_allow_user "$USER_ID"

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

sed -i.bak '/^[[:space:]]*else[[:space:]]*$/,/^[[:space:]]*EXPL[[:space:]]*$/d' /etc/bash.bashrc

for file in /etc/update-motd.d/60-unminimize /etc/update-motd.d/10-help-text; do
    if [[ -f "$file" ]]; then
        sed -i '/^[^#]/ s/^/#/' "$file"
    fi
done
# TensorFlow 기반 이미지가 tf-docker 프롬프트나 자동 cd 동작을 주입할 수 있다.
# 대화형 shell이 마운트된 사용자 홈과 기대한 프롬프트로 시작되도록 제거한다.
sed -i.bak '/echo -e "\\e\[1;31m"/d; /cat<<TF/,/TF/d' /etc/bash.bashrc
sed -i.bak '/tf-docker/d; /^cd "\$HOME"$/d' /etc/bash.bashrc

if [[ -f "/etc/legal" ]]; then
    rm /etc/legal
fi

service ssh restart

# Jupyter 상태 파일은 사용자 데이터다. 가능한 한 실제 사용자 권한으로 생성하고
# 수정해서 NFS 소유권이 UID/GID 정책과 어긋나지 않게 한다.
mkdir -p "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"
chown -R "$TARGET_UID:$TARGET_GID" "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"

if [[ ! -f "$JUPYTER_CONFIG_FILE" ]]; then
    echo "jupyter_notebook_config.py not found, generating..."
    gosu "$USER_ID:$USER_GROUP" "$JUPYTER_BIN" notebook --generate-config --config="$JUPYTER_CONFIG_FILE"
else
    echo "jupyter_notebook_config.py already exists."
fi

sed -i "1i c.JupyterApp.config_file_name = 'jupyter_notebook_config.py'\nc.NotebookApp.allow_origin = '*'\nc.NotebookApp.ip = '0.0.0.0'\nc.NotebookApp.open_browser = False\nc.NotebookApp.allow_remote_access = True\nc.NotebookApp.allow_root = False\nc.NotebookApp.notebook_dir='$JUPYTER_DIR'" "$JUPYTER_CONFIG_FILE"
chown "$TARGET_UID:$TARGET_GID" "$JUPYTER_CONFIG_FILE"

start_novnc || echo "VNC/noVNC startup failed."

# 상속된 shell startup 파일에서 ldconfig가 호출될 수 있다. bash.bashrc의 호출은
# 제거하고, 시작 시 root 권한으로 한 번만 실행한다.
sed -i '/ldconfig/d' /etc/bash.bashrc
ldconfig && echo "ldconfig executed successfully" || echo "ldconfig failed"

# 최종 프로세스는 사용자 권한으로 실행한다. 이 시점 이후 홈 PVC에 생성되는
# 파일은 TARGET_UID:TARGET_GID 소유가 되며, 일반 워크로드 동작은 NFS
# root_squash 영향을 받지 않는다.
exec gosu "$USER_ID:$USER_GROUP" bash -lc '
TOKEN=$(head -c 64 /dev/urandom | tr -dc A-Za-z0-9 | head -c 10 || true)
echo "$TOKEN" > "'"$JUPYTER_DIR"'/jupyter_token.txt"
chmod 600 "'"$JUPYTER_DIR"'/jupyter_token.txt"
echo "trying jupyter lab..."
nohup "'"$JUPYTER_BIN"'" lab --NotebookApp.token="$TOKEN" --config="'"$JUPYTER_CONFIG_FILE"'" >/dev/null 2>&1 &
echo "jupyter lab listening!"
exec tail -F /dev/null
'