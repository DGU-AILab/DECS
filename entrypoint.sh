#!/bin/bash
set -euo pipefail

: "${USER_ID:?USER_ID is required}"
: "${TARGET_UID:?TARGET_UID is required}"

USER_GROUP="${USER_GROUP:-$USER_ID}"
TARGET_GID="${TARGET_GID:-$TARGET_UID}"
USER_HOME="/home/$USER_ID"
JUPYTER_DIR="$USER_HOME/decs_jupyter_lab"
JUPYTER_CONFIG_DIR="$USER_HOME/.jupyter"
JUPYTER_CONFIG_FILE="$JUPYTER_CONFIG_DIR/jupyter_notebook_config.py"

ensure_account_matches_mounts() {
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

ensure_sshd_allow_user() {
    local user_name="$1"
    if ! grep -qxF "AllowUsers $user_name" /etc/ssh/sshd_config; then
        printf '\nAllowUsers %s\n' "$user_name" >> /etc/ssh/sshd_config
    fi
}

apt-get update
apt-get install -y auditd

# /etc/audit/audit.rules 파일에 줄 추가
echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$TARGET_UID -k rm_commands" >> /etc/audit/audit.rules

# history 명령어 칠 때 명령어를 입력한 시간이 같이 나오게 하는 명령어
echo 'HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "' >> /etc/profile
echo 'export HISTTIMEFORMAT' >> /etc/profile

ensure_account_matches_mounts

# admin_infra가 주입한 account files를 기준으로, writable path만 준비한다.
mkdir -p "$USER_HOME"
chown "$TARGET_UID:$TARGET_GID" "$USER_HOME"
chmod 750 "$USER_HOME"

# MOTD 공지 출력하도록 설정
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
mkdir -p "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"
chown -R "$TARGET_UID:$TARGET_GID" "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"

if [ ! -f "$JUPYTER_CONFIG_FILE" ]; then
    echo "jupyter_notebook_config.py not found, generating..."
    gosu "$USER_ID:$USER_GROUP" /opt/anaconda3/bin/jupyter notebook --generate-config --config="$JUPYTER_CONFIG_FILE"
else
    echo "jupyter_notebook_config.py already exists."
fi

# jupyter lab 접속 설정
sed -i "1i c.JupyterApp.config_file_name = 'jupyter_notebook_config.py'\nc.NotebookApp.allow_origin = '*'\nc.NotebookApp.ip = '0.0.0.0'\nc.NotebookApp.open_browser = False\nc.NotebookApp.allow_remote_access = True\nc.NotebookApp.allow_root = False\nc.NotebookApp.notebook_dir='$JUPYTER_DIR'" "$JUPYTER_CONFIG_FILE"
chown "$TARGET_UID:$TARGET_GID" "$JUPYTER_CONFIG_FILE"

# ldconfig permission 오류 방지
# bash.bashrc에서 ldconfig 명령어 삭제 후 명령어 실행 및 결과 출력
sed -i '/ldconfig/d' /etc/bash.bashrc
ldconfig && echo "ldconfig executed successfully" || echo "ldconfig failed"

# Jupyter 실행과 컨테이너 유지는 비-root 사용자로 전환한다.
exec gosu "$USER_ID:$USER_GROUP" bash -lc '
TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
echo "$TOKEN" > "'"$JUPYTER_DIR"'/jupyter_token.txt"
chmod 600 "'"$JUPYTER_DIR"'/jupyter_token.txt"
echo "trying jupyter lab..."
nohup /opt/anaconda3/bin/jupyter lab --NotebookApp.token="$TOKEN" --config="'"$JUPYTER_CONFIG_FILE"'" >/dev/null 2>&1 &
echo "jupyter lab listening!"
exec tail -F /dev/null
'
