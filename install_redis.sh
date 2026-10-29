#!/bin/bash
# 契约
# 做：从 Redis 官方 APT 源安装 redis，enable redis-server
# 系统：Ubuntu / Debian（lsb_release）
# 权限：sudo
# 参数：无；-h/--help 查看用法
# 改：APT 源与密钥、安装 redis、enable 服务；不写生产持久化（见 redis_persistence_setup.sh）
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

install_redis(){
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg \
    && wait \
    && echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list \
    && wait \
    && sudo apt update \
    && wait \
    && sudo apt -y install redis \
    && sudo systemctl enable redis-server.service
}

pre_config
wait
install_redis
wait
echo "redis is installed"
wait
rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
