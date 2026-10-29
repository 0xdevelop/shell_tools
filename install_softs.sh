#!/bin/bash
# 契约
# 做：交互菜单，再拉起同仓 install_docker / install_redis / install_nginx
# 系统：Ubuntu 20+
# 权限：sudo（子脚本需要）
# 参数：无，终端选择 1-3；-h/--help 查看用法
# 改：由选中的安装脚本决定；本脚本会再 wget 同仓脚本
# 完：成功后删除脚本自身
set -e

SCRIPT_NAME=$(basename -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "$#" -gt 0 ]]; then
    echo "用法：$0（无参数）" >&2
    [[ "$#" -eq 1 && ( "$1" == -h || "$1" == --help ) ]] && exit 0
    exit 2
fi
PROJECT_NAME=install_softs

install_redis(){
    wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_redis.sh && chmod a+x ./install_redis.sh && ./install_redis.sh
}

install_docker(){
    wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_docker.sh && chmod a+x ./install_docker.sh && ./install_docker.sh
}

install_nginx(){
    wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_nginx.sh && chmod a+x ./install_nginx.sh && ./install_nginx.sh
}

echo "============================ ${PROJECT_NAME} ============================"
echo "  1、install Docker"
echo "  2、install Redis"
echo "  3、install nginx"
echo "======================================================================"
read -p "$(echo -e "请选择[1-3]：")" choose
case $choose in
1)
    install_docker
    ;;
2)
    install_redis
    ;;
3)
    install_nginx
    ;;
*)
    echo "输入错误，请重新输入！"
    exit 1
    ;;
esac
wait
rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
