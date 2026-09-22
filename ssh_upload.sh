#!/usr/bin/env bash

# 上传配置。
LOCAL_DIR="/opt/ssl_certs/test.com"
REMOTE_DIR="/nginx_web/ssl_certs/test.com"
SSH_PRIVATE_KEY="$HOME/.ssh/id_ed25519"
# "*" 表示目录内所有文件。
FILE_NAME="*"
# 自动处理容器网桥路由。
AUTO_ROUTE=true

# 用户名@服务器:端口；IPv6 地址加方括号。
TARGET_REMOTES=(
    "root@172.18.1.131:22"
    "root@172.18.1.146:22"
    "root@172.18.1.135:22"
)

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  修改脚本开头的配置，然后运行 ./ssh_upload.sh

LOCAL_DIR        本地文件夹目录
REMOTE_DIR       所有服务器使用的远端文件夹绝对路径，不存在时自动创建
SSH_PRIVATE_KEY  本地私钥路径，对应公钥须已配置到远端 authorized_keys
FILE_NAME        单个文件名（不包含目录）；"*" 表示目录下所有文件
TARGET_REMOTES   多台服务器，每项为 用户名@服务器:端口
AUTO_ROUTE       true 自动绕过 docker0 / br-* 路由；false 完全使用现有路由

自动路由仅支持 Linux 上直接填写的 IPv4 地址；域名和 IPv6 使用现有路由。
只在命中 docker0 / br-* 时添加 /32 路由，多个默认路由时报错，不覆盖已有路由。
添加路由影响本机访问该目标的所有进程，不重启 Docker；重启后下次运行会重新添加。
所有文件模式包含隐藏文件，不递归子目录；空目录报错退出。
逐台、逐文件上传并覆盖同名文件，无备份；失败后继续其余文件和服务器。
每个文件打印成功或失败，最后汇总数量（同一文件上传到不同服务器分别计数）。
全部成功返回 0，存在失败返回 1。
远端账号需要目录和目标文件的写权限。
使用 OpenSSH 9.0+ 的 scp（默认 SFTP 模式），远端须启用 SFTP。
全程无交互：首次连接自动记录主机指纹，指纹变化则失败。
使用无口令私钥，或提前通过 ssh-add 将加密私钥加载到 ssh-agent。
认证失败直接报错，不询问密码或私钥口令。
EOF
}

die() {
    printf '[ERR ] %s\n' "$*" >&2
    exit 1
}

# 转义远端路径。
shell_quote() {
    local quote="'\"'\"'"
    printf "'%s'" "${1//\'/$quote}"
}

# 解析服务器地址。
parse_remote() {
    local target="$1" endpoint
    [[ "$target" == *@*:* ]] || die "服务器格式应为 用户名@服务器:端口：$target"
    user="${target%%@*}"
    endpoint="${target#*@}"
    host="${endpoint%:*}"
    port="${endpoint##*:}"
    if [[ "$host" == \[*\] ]]; then
        host="${host#\[}"
        host="${host%\]}"
    else
        [[ "$host" != *:* ]] || die "IPv6 地址必须使用方括号：$target"
    fi
    [[ -n "$host" && "$host" != -* && "$host" != *[[:space:]/@\[\]]* ]] \
        || die "服务器地址不合法：$target"
    [[ -n "$user" && "$user" != -* && "$user" != *[[:space:]/@:]* ]] \
        || die "SSH 用户名不合法：$target"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || die "端口必须是 1 到 65535 的整数：$target"
    port=$((10#$port))
    ((port >= 1 && port <= 65535)) || die "端口必须是 1 到 65535 的整数：$target"
}

# 配置目标主机路由。
prepare_route() {
    local target_ip="$1" current_route current_dev defaults gateway default_dev updated
    [[ "$AUTO_ROUTE" == true ]] || return 0
    [[ "$target_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0
    if ! current_route=$(ip -4 route get "$target_ip" 2>&1); then
        printf '[路由失败] %s：%s\n' "$target_ip" "$current_route" >&2
        return 1
    fi
    current_dev=$(printf '%s\n' "$current_route" | awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}')
    case "$current_dev" in
        docker0|br-*) ;;
        *) printf '[路由] %s：使用现有路由 %s\n' "$target_ip" "$current_route"; return 0 ;;
    esac
    if ! defaults=$(ip -o -4 route show default 2>&1); then
        printf '[路由失败] 无法读取默认路由：%s\n' "$defaults" >&2
        return 1
    fi
    if [[ -z "$defaults" || "$defaults" == *$'\n'* || "$defaults" == *nexthop* ]]; then
        printf '[路由失败] %s：需要唯一的默认网关，当前默认路由：%s\n' "$target_ip" "$defaults" >&2
        return 1
    fi
    gateway=$(printf '%s\n' "$defaults" | awk '{for(i=1;i<NF;i++) if($i=="via") {print $(i+1); exit}}')
    default_dev=$(printf '%s\n' "$defaults" | awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}')
    if [[ -z "$gateway" || -z "$default_dev" || "$default_dev" == docker0 || "$default_dev" == br-* ]]; then
        printf '[路由失败] %s：默认路由缺少网关/网卡，或仍指向容器网桥：%s\n' "$target_ip" "$defaults" >&2
        return 1
    fi
    printf '[路由] %s 命中 %s，添加 %s/32 via %s dev %s\n' \
        "$target_ip" "$current_dev" "$target_ip" "$gateway" "$default_dev"
    if ! ip -4 route add "$target_ip/32" via "$gateway" dev "$default_dev"; then
        printf '[路由失败] %s：添加失败，需 root/CAP_NET_ADMIN 且不能存在冲突的 /32 路由\n' "$target_ip" >&2
        return 1
    fi
    if updated=$(ip -4 route get "$target_ip" 2>&1) && \
        printf '%s\n' "$updated" | awk -v gw="$gateway" -v dev="$default_dev" \
            '{for(i=1;i<NF;i++) {if($i=="via" && $(i+1)==gw) v=1; if($i=="dev" && $(i+1)==dev) d=1}} END {exit !(v && d)}'; then
        printf '[路由成功] %s\n' "$updated"
        return 0
    fi
    printf '[路由失败] %s：添加后未走预期网关/网卡：%s\n' "$target_ip" "$updated" >&2
    # 撤销本次路由。
    ip -4 route del "$target_ip/32" via "$gateway" dev "$default_dev" \
        || printf '[路由失败] %s：撤销本次添加的路由失败\n' "$target_ip" >&2
    return 1
}

if [[ $# -eq 1 && ( "$1" == '-h' || "$1" == '--help' ) ]]; then
    usage
    exit 0
fi
[[ $# -eq 0 ]] || die '请直接修改脚本开头的配置，不接受命令行配置参数'
[[ -d "$LOCAL_DIR" ]] || die "本地目录不存在：$LOCAL_DIR"
[[ -n "$FILE_NAME" && "$FILE_NAME" != */* ]] || die 'FILE_NAME 必须是单个文件名或 "*"，不包含目录'
# 转换为绝对路径。
[[ "$LOCAL_DIR" == /* ]] || LOCAL_DIR="$PWD/$LOCAL_DIR"
local_files=()
if [[ "$FILE_NAME" == '*' ]]; then
    shopt -s nullglob dotglob
    for local_file in "${LOCAL_DIR%/}/"*; do
        [[ -f "$local_file" ]] || continue
        local_files+=("$local_file")
    done
    shopt -u nullglob dotglob
    [[ ${#local_files[@]} -gt 0 ]] || die "目录下没有可上传的文件：$LOCAL_DIR"
else
    local_files=("${LOCAL_DIR%/}/$FILE_NAME")
fi
for local_file in "${local_files[@]}"; do
    [[ -f "$local_file" && -r "$local_file" ]] || die "本地文件不存在或不可读：$local_file"
done
[[ -f "$SSH_PRIVATE_KEY" && -r "$SSH_PRIVATE_KEY" ]] || die "私钥不存在或不可读：$SSH_PRIVATE_KEY"
[[ "$REMOTE_DIR" == /* ]] || die 'REMOTE_DIR 必须是远端绝对路径，不能使用 ~'
[[ ${#TARGET_REMOTES[@]} -gt 0 ]] || die 'TARGET_REMOTES 不能为空'
command -v ssh >/dev/null || die '未找到 ssh，请安装 OpenSSH 客户端'
command -v scp >/dev/null || die '未找到 scp，请安装 OpenSSH 客户端'
[[ "$AUTO_ROUTE" == true || "$AUTO_ROUTE" == false ]] || die 'AUTO_ROUTE 必须为 true 或 false'
if [[ "$AUTO_ROUTE" == true ]]; then
    [[ "$(uname -s)" == Linux ]] || die 'AUTO_ROUTE 仅支持 Linux；其他系统请设置 AUTO_ROUTE=false'
    command -v ip >/dev/null || die '自动路由需要 ip 命令，请安装 iproute2'
fi

# 校验服务器配置。
for target in "${TARGET_REMOTES[@]}"; do
    parse_remote "$target"
done

[[ "$SSH_PRIVATE_KEY" == /* ]] || SSH_PRIVATE_KEY="$PWD/$SSH_PRIVATE_KEY"
ssh_options=(
    -i "$SSH_PRIVATE_KEY"
    -o IdentitiesOnly=yes
    -o PreferredAuthentications=publickey
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
)
destination="${REMOTE_DIR%/}/"
failed=0
success_count=0
failure_count=0

for target in "${TARGET_REMOTES[@]}"; do
    parse_remote "$target"
    scp_host="$host"
    [[ "$host" != *:* ]] || scp_host="[$host]"
    printf '[INFO] 正在上传到 %s\n' "$target"
    if ! prepare_route "$host"; then
        for local_file in "${local_files[@]}"; do
            printf '[失败] %s -> %s:%s%s：路由准备失败，未连接、未上传\n' \
                "$local_file" "$target" "$destination" "${local_file##*/}" >&2
        done
        failure_count=$((failure_count + ${#local_files[@]}))
        failed=1
        continue
    fi
    if ssh_output=$(LC_ALL=C ssh -n -T "${ssh_options[@]}" -p "$port" -l "$user" "$host" \
        "mkdir -p -- $(shell_quote "$REMOTE_DIR") || exit 73" 2>&1); then
        [[ -z "$ssh_output" ]] || printf '%s\n' "$ssh_output" >&2
    else
        ssh_status=$?
        case "$ssh_status" in
            255)
                failure_reason='SSH 连接或会话失败，目录状态未确认'
                case "$ssh_output" in
                    *'No route to host'*) failure_reason='SSH 网络不可达（No route to host），未执行目录创建' ;;
                    *'Connection refused'*) failure_reason='SSH 连接被拒绝（Connection refused），未执行目录创建' ;;
                    *'connect to host '*'Connection timed out'*|*'connect to host '*'Operation timed out'*)
                        failure_reason='SSH 连接超时，未执行目录创建' ;;
                    *'Could not resolve hostname'*) failure_reason='SSH 主机名解析失败，未执行目录创建' ;;
                    *'Permission denied'*) failure_reason='SSH 认证失败（Permission denied），未执行目录创建' ;;
                    *'REMOTE HOST IDENTIFICATION HAS CHANGED'*|*'Host key verification failed'*)
                        failure_reason='SSH 主机身份校验失败，未执行目录创建' ;;
                esac
                ;;
            73) failure_reason='远端目录创建失败（SSH 已连接）' ;;
            *) failure_reason='远端命令执行失败，目录状态未确认' ;;
        esac
        printf '[错误] %s：%s；退出码 %s\n' "$target" "$failure_reason" "$ssh_status" >&2
        [[ -z "$ssh_output" ]] || printf '[SSH 原始输出]\n%s\n' "$ssh_output" >&2
        for local_file in "${local_files[@]}"; do
            printf '[失败] %s -> %s:%s%s：%s，未上传\n' \
                "$local_file" "$target" "$destination" "${local_file##*/}" "$failure_reason" >&2
        done
        failure_count=$((failure_count + ${#local_files[@]}))
        failed=1
        continue
    fi
    for local_file in "${local_files[@]}"; do
        # 上传文件。
        if scp "${ssh_options[@]}" -P "$port" "$local_file" "$user@$scp_host:$destination"; then
            printf '[成功] %s -> %s:%s%s\n' "$local_file" "$target" "$destination" "${local_file##*/}"
            success_count=$((success_count + 1))
        else
            scp_status=$?
            printf '[失败] %s -> %s:%s%s：SCP 上传失败（退出码 %s），详见上述原始错误；目标文件可能被部分覆盖\n' \
                "$local_file" "$target" "$destination" "${local_file##*/}" "$scp_status" >&2
            failure_count=$((failure_count + 1))
            failed=1
        fi
    done
done

printf '[汇总] 成功：%s，失败：%s（文件 × 服务器）\n' "$success_count" "$failure_count"
exit "$failed"
