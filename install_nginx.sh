#!/bin/bash
# 契约
# 做：从 Nginx 官方 APT 源安装 nginx，enable 并启动
# 系统：Ubuntu（用 lsb_release 写源）
# 权限：sudo
# 参数：无；-h/--help 查看用法
# 改：APT 源与密钥、安装 nginx、启动服务
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
    sudo apt update && wait && sudo apt install -y curl gnupg2 ca-certificates lsb-release
}

install_nginx(){
    curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
    sudo apt update
    sudo apt install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
}

pre_config
wait
install_nginx
wait
echo "Nginx install Complated"
wait
rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
