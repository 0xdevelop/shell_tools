#!/bin/bash
# 契约
# 做：装基础工具链，停掉 ufw，再跑同仓 optimize_network.sh
# 系统：Ubuntu 20+
# 权限：root（部分命令另调用 sudo）
# 参数：无；-h/--help 查看用法
# 改：apt 包、禁用 ufw、文件句柄与 sysctl（含关闭 ipv6）；会再拉 optimize_network.sh
# 完：成功后删除脚本自身
set -e

SCRIPT_NAME=$(basename -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "$#" -gt 0 ]]; then
    echo "用法：$0（无参数）" >&2
    [[ "$#" -eq 1 && ( "$1" == -h || "$1" == --help ) ]] && exit 0
    exit 2
fi

pre_config(){
    sudo apt update && wait && sudo apt install -y unzip zip wget net-tools logrotate apt-transport-https ca-certificates curl gnupg lsb-release
}

dislble_ufw(){
    systemctl disable ufw.service && systemctl stop ufw.service
}

optimize_network(){
    wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/optimize_network.sh && chmod a+x ./optimize_network.sh && ./optimize_network.sh
}

NEW_SSH_PORT=22
input_ssh_port(){
    while true; do
        echo "====Please Input SSH Port For New===="
        read -p "Please Input(请输入): " input_string
        if [[ -z "${input_string// }" ]]; then
            INPUT_DOMAIN="$input_string"
            break
        else
            echo "Invalid Domain"
        fi
    done
}

pre_config
wait
dislble_ufw
wait
optimize_network
wait
echo "Ubuntu 20.0.4 LTS Setup End"
wait
rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
