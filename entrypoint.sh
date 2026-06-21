#!/bin/bash
set -euo pipefail

CONDA_DIR="${CONDA_DIR:-/opt/conda}"
JUPYTER_BIN="${JUPYTER_BIN:-$CONDA_DIR/bin/jupyter}"
USER_PW="${USER_PW:-ailab2260}"

: "${USER_ID:?USER_ID is required}"

USER_GROUP="${USER_GROUP:-$USER_ID}"
TARGET_UID="${TARGET_UID:-${UID:-}}"
TARGET_GID="${TARGET_GID:-${GID:-${TARGET_UID:-}}}"
KRB5CCNAME="${KRB5CCNAME:-${DECS_KRB5CCNAME:-}}"
KRB5_REALM="${KRB5_REALM:-FARM.DECS.INTERNAL}"
DECS_KRB5_PRINCIPAL="${DECS_KRB5_PRINCIPAL:-${USER_ID}@${KRB5_REALM}}"
DECS_KERBEROS_HOST_KEYTAB="${DECS_KERBEROS_HOST_KEYTAB:-false}"
DECS_HOME_WRITABLE=true
USER_HOME="/home/$USER_ID"
JUPYTER_DIR="$USER_HOME/decs_jupyter_lab"
JUPYTER_CONFIG_DIR="$USER_HOME/.jupyter"
JUPYTER_CONFIG_FILE="$JUPYTER_CONFIG_DIR/jupyter_notebook_config.py"

if ! [[ "$TARGET_UID" =~ ^[0-9]+$ && "$TARGET_GID" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] TARGET_UID and TARGET_GID must be numeric." >&2
    exit 1
fi

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

run_as_user() {
    local -a user_env
    user_env=(HOME="$USER_HOME" USER="$USER_ID")
    if [[ -n "$KRB5CCNAME" ]]; then
        user_env+=(KRB5CCNAME="$KRB5CCNAME")
    fi
    sudo -H -u "$USER_ID" env "${user_env[@]}" "$@"
}

print_image_runtime_info() {
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

ensure_group_and_user() {
    if getent group "$USER_GROUP" >/dev/null 2>&1; then
        local actual_gid
        actual_gid="$(getent group "$USER_GROUP" | awk -F: '{print $3}')"
        if [[ "$actual_gid" != "$TARGET_GID" ]]; then
            echo "[ERROR] Group '$USER_GROUP' has gid '$actual_gid', expected '$TARGET_GID'." >&2
            exit 1
        fi
    else
        groupadd -g "$TARGET_GID" "$USER_GROUP"
    fi

    if id "$USER_ID" >/dev/null 2>&1; then
        local actual_uid actual_primary_gid
        actual_uid="$(id -u "$USER_ID")"
        actual_primary_gid="$(id -g "$USER_ID")"
        if [[ "$actual_uid" != "$TARGET_UID" ]]; then
            echo "[ERROR] User '$USER_ID' has uid '$actual_uid', expected '$TARGET_UID'." >&2
            exit 1
        fi
        if [[ "$actual_primary_gid" != "$TARGET_GID" ]]; then
            usermod -g "$USER_GROUP" "$USER_ID"
        fi
    else
        useradd -M -s /bin/bash -d "$USER_HOME" -u "$TARGET_UID" -g "$USER_GROUP" "$USER_ID"
    fi

    usermod -aG "$USER_GROUP" "$USER_ID"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_ID" > "/etc/sudoers.d/$USER_ID"
    chmod 0440 "/etc/sudoers.d/$USER_ID"
    echo "$USER_ID:$USER_PW" | chpasswd
}

ensure_user_home() {
    if [[ ! -d "$USER_HOME" ]]; then
        mkdir -p "$USER_HOME" || {
            echo "[ERROR] Could not create $USER_HOME. If /home is an NFS mount with root_squash, pre-create this directory on the NAS as ${TARGET_UID}:${TARGET_GID}." >&2
            exit 1
        }
    fi

    chown "$TARGET_UID:$TARGET_GID" "$USER_HOME" 2>/dev/null || true

    if ! run_as_user test -w "$USER_HOME"; then
        if [[ -n "$KRB5CCNAME" ]]; then
            DECS_HOME_WRITABLE=false
            echo "[WARN] $USER_HOME is not writable yet. Kerberos ticket may be required; run kinit inside the container." >&2
            return 0
        else
            echo "[ERROR] $USER_HOME is not writable by $USER_ID (${TARGET_UID}:${TARGET_GID}). Check NAS ownership and root_squash provisioning." >&2
            exit 1
        fi
    fi

    run_as_user chmod 750 "$USER_HOME" || true

    local skel_file
    for skel_file in .profile .bashrc .bash_logout; do
        if [[ -f "/etc/skel/$skel_file" && ! -e "$USER_HOME/$skel_file" ]]; then
            run_as_user cp "/etc/skel/$skel_file" "$USER_HOME/$skel_file"
        fi
    done

    run_as_user bash -c '
set -euo pipefail
touch "$HOME/.bash_logout"
if ! grep -q "history -w.*current_time" "$HOME/.bash_logout"; then
  cat >> "$HOME/.bash_logout" <<'"'"'EOF'"'"'
cd ~
current_time=$(date +%Y-%m-%d_%H-%M-%S)
history -w $current_time.txt
sudo mv $current_time.txt /var/log/audit/
EOF
fi
'
}

ensure_kerberos_runtime() {
    if [[ -z "$KRB5CCNAME" ]]; then
        return 0
    fi

    local ccache_path="$KRB5CCNAME"
    if [[ "$ccache_path" == FILE:* ]]; then
        ccache_path="${ccache_path#FILE:}"
    fi

    local ccache_dir
    ccache_dir="$(dirname "$ccache_path")"
    mkdir -p "$ccache_dir"
    chown "$TARGET_UID:$TARGET_GID" "$ccache_dir" 2>/dev/null || true
    chmod 700 "$ccache_dir" 2>/dev/null || true

    cat >/etc/profile.d/decs-kerberos.sh <<EOF
export KRB5CCNAME='${KRB5CCNAME}'
export KRB5_REALM='${KRB5_REALM}'
export DECS_KRB5_PRINCIPAL='${DECS_KRB5_PRINCIPAL}'
EOF
    chmod 0644 /etc/profile.d/decs-kerberos.sh

    cat >/usr/local/bin/decs-kerberos-status <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ -z "${KRB5CCNAME:-}" ]]; then
  echo "KRB5CCNAME is not set."
  exit 1
fi
klist -c "$KRB5CCNAME"
EOF
    chmod 0755 /usr/local/bin/decs-kerberos-status
}

refresh_user_bashrc() {
    [[ -f "$USER_HOME/.bashrc" ]] || return 0

    local conda_block_file
    conda_block_file="$(mktemp)"
    {
        echo "# !!! Do NOT delete the conda initialize comments below. !!!"
        echo "# !!! Do NOT add anything inside the conda initialize block. It will be removed on container restart/update. !!!"
        sed -n '/# >>> conda initialize >>>/,/# <<< conda initialize <<</p' /root/.bashrc || true
    } > "$conda_block_file"
    chmod 0644 "$conda_block_file"

    run_as_user bash -c '
set -euo pipefail
sed -i \
  -e "/# !!! Do NOT delete the conda initialize comments below\. !!!/d" \
  -e "/# !!! Do NOT add anything inside the conda initialize block\. It will be removed on container restart\/update\. !!!/d" \
  -e "/# >>> conda initialize >>>/,/# <<< conda initialize <<</d" \
  "$HOME/.bashrc"
cat "$1" >> "$HOME/.bashrc"
' _ "$conda_block_file"

    rm -f "$conda_block_file"
}

ensure_sshd_allow_user() {
    local user_name="$1"
    if ! getent passwd "$user_name" >/dev/null 2>&1; then
        echo "[WARN] Skipping AllowUsers for missing account '$user_name'" >&2
        return 0
    fi
    if ! grep -qxF "AllowUsers $user_name" /etc/ssh/sshd_config; then
        printf '\nAllowUsers %s\n' "$user_name" >> /etc/ssh/sshd_config
    fi
}

configure_system_login() {
    echo "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid=$TARGET_UID -k rm_commands" >> /etc/audit/audit.rules

    if ! grep -q 'HISTTIMEFORMAT="\[%Y-%m-%d %H:%M:%S\] "' /etc/profile; then
        echo 'HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "' >> /etc/profile
        echo 'export HISTTIMEFORMAT' >> /etc/profile
    fi

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

    sed -i.bak '/^[[:space:]]*else[[:space:]]*$/,/^[[:space:]]*EXPL[[:space:]]*$/d' /etc/bash.bashrc || true

    local motd_file
    for motd_file in /etc/update-motd.d/60-unminimize /etc/update-motd.d/10-help-text; do
        if [[ -f "$motd_file" ]]; then
            sed -i '/^[^#]/ s/^/#/' "$motd_file"
        fi
    done

    sed -i.bak '/echo -e "\\e\[1;31m"/d; /cat<<TF/,/TF/d; /tf-docker/d; /^cd "\$HOME"$/d' /etc/bash.bashrc || true
    sed -i '/ldconfig/d' /etc/bash.bashrc || true

    [[ ! -f /etc/legal ]] || rm /etc/legal
    service ssh restart
}

ensure_jupyter_config() {
    run_as_user mkdir -p "$JUPYTER_DIR" "$JUPYTER_CONFIG_DIR"

    if [[ ! -f "$JUPYTER_CONFIG_FILE" ]]; then
        echo "jupyter_notebook_config.py not found, generating..."
        if [[ -s /jupyter_config/jupyter_notebook_config.py ]]; then
            run_as_user cp /jupyter_config/jupyter_notebook_config.py "$JUPYTER_CONFIG_FILE"
        else
            run_as_user touch "$JUPYTER_CONFIG_FILE"
        fi
    else
        echo "jupyter_notebook_config.py already exists."
    fi

    run_as_user bash -c '
set -euo pipefail
config="$1"
notebook_dir="$2"
tmp="$(mktemp "${config}.XXXX")"
{
  printf "%s\n" "c.JupyterApp.config_file_name = '\''jupyter_notebook_config.py'\''"
  printf "%s\n" "c.NotebookApp.allow_origin = '\''*'\''"
  printf "%s\n" "c.NotebookApp.ip = '\''0.0.0.0'\''"
  printf "%s\n" "c.NotebookApp.open_browser = False"
  printf "%s\n" "c.NotebookApp.allow_remote_access = True"
  printf "%s\n" "c.NotebookApp.allow_root = False"
  printf "%s\n" "c.NotebookApp.notebook_dir='\''${notebook_dir}'\''"
  grep -vE "^(c\\.JupyterApp\\.config_file_name|c\\.NotebookApp\\.(allow_origin|ip|open_browser|allow_remote_access|allow_root|notebook_dir))" "$config" || true
} > "$tmp"
mv "$tmp" "$config"
' _ "$JUPYTER_CONFIG_FILE" "$JUPYTER_DIR"
}

generate_token() {
    "$CONDA_DIR/bin/python" - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(10)))
PY
}

start_jupyter() {
    local token
    local -a user_env
    token="$(generate_token)"
    user_env=(HOME="$USER_HOME" USER="$USER_ID")
    if [[ -n "$KRB5CCNAME" ]]; then
        user_env+=(KRB5CCNAME="$KRB5CCNAME")
    fi

    run_as_user bash -c '
set -euo pipefail
printf "%s\n" "$1" > "$2"
chmod 600 "$2"
' _ "$token" "$JUPYTER_DIR/jupyter_token.txt"

    echo "trying jupyter lab..."
    nohup sudo -H -u "$USER_ID" env "${user_env[@]}" \
        "$JUPYTER_BIN" lab --NotebookApp.token="$token" --config="$JUPYTER_CONFIG_FILE" \
        >/tmp/jupyter-${USER_ID}.log 2>&1 &
    echo "jupyter lab listening!"
}

start_novnc() {
    if ! is_truthy "${ENABLE_VNC:-false}"; then
        echo "VNC/noVNC disabled. Set ENABLE_VNC=true to enable it."
        return 0
    fi

    local vnc_dir="$USER_HOME/.vnc"
    local vnc_display="${VNC_DISPLAY:-1}"
    local vnc_resolution="${VNC_RESOLUTION:-1920x1080}"
    local vnc_depth="${VNC_DEPTH:-24}"
    local novnc_port="${NOVNC_PORT:-6080}"
    local vnc_password_file="$USER_HOME/vnc_password.txt"
    local vnc_password
    local -a user_env

    user_env=(HOME="$USER_HOME" USER="$USER_ID")
    if [[ -n "$KRB5CCNAME" ]]; then
        user_env+=(KRB5CCNAME="$KRB5CCNAME")
    fi

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

    mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
    chown root:root /tmp/.X11-unix /tmp/.ICE-unix
    chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix
    run_as_user mkdir -p "$vnc_dir" "$JUPYTER_DIR"

    if [[ -n "${VNC_PASSWORD:-}" ]]; then
        vnc_password="$VNC_PASSWORD"
    elif [[ -s "$vnc_password_file" ]]; then
        vnc_password="$(run_as_user head -c 8 "$vnc_password_file" | tr -d '\r\n')"
    else
        vnc_password="$(generate_token | head -c 8)"
    fi
    vnc_password="${vnc_password:0:8}"

    if [[ -z "$vnc_password" ]]; then
        echo "Failed to prepare VNC password. Skipping GUI startup."
        return 1
    fi

    run_as_user bash -c '
set -euo pipefail
printf "%s\n" "$1" > "$2"
chmod 600 "$2"
printf "%s\n" "$1" | vncpasswd -f > "$3/passwd"
chmod 600 "$3/passwd"
cat > "$3/xstartup" <<'"'"'EOF'"'"'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XKL_XMODMAP_DISABLE=1
xrdb "$HOME/.Xresources" 2>/dev/null || true
exec dbus-launch --exit-with-session startxfce4
EOF
chmod +x "$3/xstartup"
' _ "$vnc_password" "$vnc_password_file" "$vnc_dir"

    run_as_user vncserver -kill ":$vnc_display" >/tmp/vnc-kill.log 2>&1 || true

    echo "trying TigerVNC on localhost:$vnc_port..."
    if ! run_as_user vncserver -localhost yes ":$vnc_display" -geometry "$vnc_resolution" -depth "$vnc_depth" >/tmp/vncserver.log 2>&1; then
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
    nohup sudo -H -u "$USER_ID" env "${user_env[@]}" \
        websockify --web=/usr/share/novnc "0.0.0.0:$novnc_port" "localhost:$vnc_port" \
        >/tmp/novnc.log 2>&1 &
    echo "noVNC listening on port $novnc_port. VNC password saved to $vnc_password_file"
}

start_user_apps() {
    refresh_user_bashrc
    ensure_jupyter_config
    start_jupyter
    start_novnc || echo "VNC/noVNC startup failed."
}

start_kerberos_home_watcher() {
    if [[ -z "$KRB5CCNAME" ]]; then
        return 0
    fi

    if is_truthy "$DECS_KERBEROS_HOST_KEYTAB"; then
        echo "Kerberos home is waiting for host-managed ticket refresh for ${DECS_KRB5_PRINCIPAL}."
    else
        echo "Kerberos home is waiting for a user ticket. Run: kinit ${DECS_KRB5_PRINCIPAL}"
    fi
    (
        for _ in $(seq 1 720); do
            if run_as_user test -w "$USER_HOME"; then
                echo "Kerberos home is writable; starting user services."
                DECS_HOME_WRITABLE=true
                ensure_user_home
                start_user_apps
                exit 0
            fi
            sleep 10
        done
        echo "Timed out waiting for Kerberos ticket for $USER_ID; SSH remains available."
    ) &
}

print_image_runtime_info || exit 1
ensure_group_and_user
ensure_kerberos_runtime
ensure_user_home
configure_system_login
if [[ "$DECS_HOME_WRITABLE" == "true" ]]; then
    start_user_apps
else
    start_kerberos_home_watcher
fi
ldconfig && echo "ldconfig executed successfully" || echo "ldconfig failed"

tail -F /dev/null
