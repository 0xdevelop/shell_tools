#!/bin/bash
# 契约
# 做：把 /etc/nginx/nginx.conf 的 worker 连接等调到 51200 量级
# 系统：已安装 Nginx 的 Linux
# 权限：root，需要写 Nginx/systemd 配置并重启服务
# 参数：无；-h/--help 查看用法
# 改：nginx.conf（先覆盖备份为 nginx.conf.bak）、systemd nginx.service.d/override.conf；daemon-reload 并重启 Nginx
# 完：成功后删除脚本自身
set -e

CUSTOM_FILNAME=$(basename "$0")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "$#" -gt 0 ]]; then
    echo "用法：$0（无参数）" >&2
    [[ "$#" -eq 1 && ( "$1" == -h || "$1" == --help ) ]] && exit 0
    exit 2
fi
echo "file name with "$CUSTOM_FILNAME

# 定义 nginx.conf 的路径
nginx_conf="/etc/nginx/nginx.conf"
nginx_limit_base=51200

# 更新 nginx.conf 文件
function update_nginx_conf() {
    # 备份 nginx 配置文件
    cp $nginx_conf "$nginx_conf.bak"

    if ! grep -q "worker_rlimit_nofile" $nginx_conf; then
        echo "worker_rlimit_nofile ${nginx_limit_base};" >> $nginx_conf
    else
        sed -i "/worker_rlimit_nofile/c\worker_rlimit_nofile ${nginx_limit_base};" $nginx_conf
    fi

    if ! grep -q "events {" $nginx_conf; then
        echo -e "events {\n    worker_connections ${nginx_limit_base};\n    multi_accept on;\n    use epoll;\n}" >> $nginx_conf
    else
        if ! grep -q "worker_connections" $nginx_conf; then
            sed -i "/events {/a\    worker_connections ${nginx_limit_base};" $nginx_conf
        else
            sed -i "/worker_connections/c\    worker_connections ${nginx_limit_base};" $nginx_conf
        fi
        if ! grep -q "multi_accept" $nginx_conf; then
            sed -i "/events {/a\    multi_accept on;" $nginx_conf
        fi
        if ! grep -q "use epoll;" $nginx_conf; then
            sed -i "/events {/a\    use epoll;" $nginx_conf
        fi
    fi
}



# 更新 systemd 服务文件
function update_nginx_override_conf() {
    # 计算 LimitNOFILE 值
    cpu_cores=$(nproc)
    limit_nofile=$((cpu_cores * 51200))
    systemd_dir="/etc/systemd/system/nginx.service.d"
    if [ ! -d "$systemd_dir" ]; then
        mkdir -p "$systemd_dir"
    fi

    # 创建或修改 override.conf 文件，动态设置 LimitNOFILE
    echo -e "[Service]\nLimitNOFILE=$limit_nofile" > "${systemd_dir}/override.conf"

    # 重新加载 systemd 配置并尝试重启 Nginx
    systemctl daemon-reload
    systemctl restart nginx

    echo "Nginx and systemd configuration updated successfully."
}


update_nginx_conf
update_nginx_override_conf
wait
rm -rf -- "$SCRIPT_DIR/$CUSTOM_FILNAME"
