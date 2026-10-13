#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 || $# -ne 2 ]]; then
    echo "用法：sudo bash install.sh <编译产物目录> <Q8 模型文件>" >&2
    exit 1
fi

build_dir=$(realpath "$1")
model_path=$(realpath "$2")
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
test -x "$build_dir/llama-server"
test -f "$model_path"

if ! getent passwd clef-flash >/dev/null; then
    useradd --system --user-group --home-dir /var/lib/clef-flash --shell /usr/sbin/nologin clef-flash
fi

if systemctl is-active --quiet clef-flash.service; then
    systemctl stop clef-flash.service
fi

install -d -m 0755 /opt/clef-flash/bin /etc/clef-flash
cp -a "$build_dir/." /opt/clef-flash/bin/
chown -R "${SUDO_USER:-root}:" /opt/clef-flash
install -d -o clef-flash -g clef-flash -m 0750 /var/lib/clef-flash

# 保留已有模型和运行配置，重复部署时只更新程序与服务单元。
if [[ ! -f /var/lib/clef-flash/Clef-Flash-Q8_0.gguf ]]; then
    cp --reflink=auto "$model_path" /var/lib/clef-flash/Clef-Flash-Q8_0.gguf
    chown clef-flash:clef-flash /var/lib/clef-flash/Clef-Flash-Q8_0.gguf
    chmod 0640 /var/lib/clef-flash/Clef-Flash-Q8_0.gguf
fi
if [[ ! -f /etc/clef-flash/env ]]; then
    install -o root -g root -m 0640 "$script_dir/env.example" /etc/clef-flash/env
fi

install -o root -g root -m 0644 "$script_dir/clef-flash.service" /etc/systemd/system/clef-flash.service
systemd-analyze verify /etc/systemd/system/clef-flash.service
systemctl daemon-reload
systemctl enable --now clef-flash.service
