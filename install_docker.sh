#!/bin/bash
# 契约
# 做：从 Docker 官方 APT 源安装 docker-ce 及 compose/buildx，enable 并启动
# 系统：Ubuntu
# 权限：sudo
# 参数：无；-h/--help 查看用法
# 改：APT 源与密钥、安装 Docker 组件、启动 docker.service
# 完：成功后删除脚本自身
set -eo pipefail

SCRIPT_NAME=$(basename -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "$#" -gt 0 ]]; then
    echo "用法：$0（无参数）" >&2
    [[ "$#" -eq 1 && ( "$1" == -h || "$1" == --help ) ]] && exit 0
    exit 2
fi

pre_config(){
    sudo apt update && wait && sudo apt install -y unzip zip wget logrotate apt-transport-https ca-certificates curl gnupg lsb-release
}

config_docker_install(){
    sudo mkdir -m 0755 -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo \
        "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
}

install_docker(){
    sudo apt update \
    && wait \
    && sudo chmod a+r /etc/apt/keyrings/docker.gpg \
    && wait \
    && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}


install(){
    pre_config
    wait
    config_docker_install
    wait
    install_docker
    wait
    sudo systemctl enable --now docker
}

install
wait
echo "docker is installed"
wait
rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
