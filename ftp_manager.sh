#!/usr/bin/env bash

set -Eeuo pipefail

CONF="/etc/vsftpd.conf"
ALLOW_FILE="/etc/vsftpd.allowed_users"

PASV_MIN="30000"
PASV_MAX="30100"

MANAGED_MARK="# managed-by: ftp_manager.sh"

C_RESET='\033[0m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_CYAN='\033[36m'

info() {
    printf "%b[INFO]%b %s\n" \
        "$C_CYAN" "$C_RESET" "$*"
}

ok() {
    printf "%b[ OK ]%b %s\n" \
        "$C_GREEN" "$C_RESET" "$*"
}

warn() {
    printf "%b[WARN]%b %s\n" \
        "$C_YELLOW" "$C_RESET" "$*"
}

err() {
    printf "%b[ERR ]%b %s\n" \
        "$C_RED" "$C_RESET" "$*" >&2
}

die() {
    err "$*"
    exit 1
}

# 检查管理员权限。
require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        info "需要 root 权限，使用 sudo 重新执行..."
        exec sudo -E bash "$0" "$@"
    fi
}

# 检查系统类型。
check_ubuntu_debian() {

    [[ -r /etc/os-release ]] || \
        die "无法读取 /etc/os-release"

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" \
        && "${ID:-}" != "debian" \
        && "${ID_LIKE:-}" != *debian* ]]; then

        die "当前脚本仅支持 Ubuntu / Debian 系统。当前 ID=${ID:-unknown}"
    fi
}

# 生成 UTC 时间戳。
utc_stamp() {
    date -u '+%Y%m%d_%H%M%S_utc'
}

# 备份文件。
backup_file() {

    local file="$1"
    local backup

    [[ -e "$file" ]] || return 0

    backup="${file}.backup_$(utc_stamp)"

    cp -a -- "$file" "$backup"

    printf '%s\n' "$backup"
}

# 查找 nologin。
get_nologin_shell() {

    if [[ -x /usr/sbin/nologin ]]; then

        printf '%s\n' "/usr/sbin/nologin"

    elif [[ -x /sbin/nologin ]]; then

        printf '%s\n' "/sbin/nologin"

    else

        die "找不到 nologin shell"

    fi
}

# 注册 nologin。
ensure_nologin_in_shells() {

    local shell_path="$1"

    if grep -Fxq "$shell_path" /etc/shells 2>/dev/null; then

        ok "$shell_path 已存在于 /etc/shells"
        return 0

    fi

    local backup

    backup="$(backup_file /etc/shells)"

    if [[ -n "$backup" ]]; then
        ok "已备份 /etc/shells -> $backup"
    fi

    printf '%s\n' "$shell_path" >> /etc/shells

    ok "已将 $shell_path 加入 /etc/shells"
}

# 校验用户名。
validate_username() {

    local username="$1"

    [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# 规范化目录路径。
normalize_dir() {

    local dir="$1"

    [[ -n "$dir" ]] || return 1

    [[ "$dir" = /* ]] || return 1

    realpath -m -- "$dir"
}

# 检查 FTP 配置。
check_managed_config() {

    [[ -f "$CONF" ]] || return 1

    grep -Fqx "$MANAGED_MARK" "$CONF" || return 1

    grep -Fqx \
        'local_enable=YES' \
        "$CONF" || return 1

    grep -Fqx \
        'write_enable=YES' \
        "$CONF" || return 1

    grep -Fqx \
        'chroot_local_user=YES' \
        "$CONF" || return 1

    grep -Fqx \
        'allow_writeable_chroot=YES' \
        "$CONF" || return 1

    grep -Fqx \
        "userlist_file=${ALLOW_FILE}" \
        "$CONF" || return 1

    grep -Fqx \
        'userlist_deny=NO' \
        "$CONF" || return 1

    return 0
}

# 安装并配置 VSFTPD。
install_vsftpd() {

    echo
    echo "============================================================"
    echo "  1) 安装 / 初始化 vsftpd"
    echo "============================================================"
    echo

    info "此入口只安装和配置 vsftpd。"
    info "不会创建 FTP 用户。"
    info "不会要求设置公共 FTP 根目录。"

    info "更新 apt 索引..."

    apt-get update

    info "安装 vsftpd、acl..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        vsftpd \
        acl

    ok "软件安装完成"

    if command -v vsftpd >/dev/null 2>&1; then
        info "vsftpd 版本："
        vsftpd -v 2>&1 || true
    fi

    local nologin_shell

    nologin_shell="$(get_nologin_shell)"

    ensure_nologin_in_shells \
        "$nologin_shell"

    install -d \
        -m 0755 \
        /var/run/vsftpd/empty

    touch "$ALLOW_FILE"

    chmod 0600 \
        "$ALLOW_FILE"

    ok "FTP 用户白名单：$ALLOW_FILE"

    local backup=""

    if [[ -f "$CONF" ]]; then

        backup="$(backup_file "$CONF")"

        ok "原配置已备份："
        echo "  $backup"

    fi

    info "写入 $CONF ..."

    cat > "$CONF" <<EOF
${MANAGED_MARK}

listen=YES
listen_ipv6=NO

listen_port=21

connect_from_port_20=YES

anonymous_enable=NO

local_enable=YES

pam_service_name=vsftpd

userlist_enable=YES

userlist_deny=NO

userlist_file=${ALLOW_FILE}

write_enable=YES

file_open_mode=0666

local_umask=022

chroot_local_user=YES

allow_writeable_chroot=YES

secure_chroot_dir=/var/run/vsftpd/empty

pasv_enable=YES

pasv_min_port=${PASV_MIN}

pasv_max_port=${PASV_MAX}

xferlog_enable=YES

xferlog_std_format=NO

log_ftp_protocol=YES

vsftpd_log_file=/var/log/vsftpd.log

dirmessage_enable=YES

dirlist_enable=YES

download_enable=YES

hide_ids=YES

use_localtime=NO

ssl_enable=NO
EOF

    chmod 0644 \
        "$CONF"

    ok "vsftpd 主配置写入成功"

    systemctl enable \
        vsftpd \
        >/dev/null 2>&1 || true

    info "重启 vsftpd 验证配置..."

    if ! systemctl restart vsftpd; then

        err "vsftpd 启动失败"

        echo
        journalctl \
            -u vsftpd \
            -n 50 \
            --no-pager || true

        if [[ -n "$backup" && -f "$backup" ]]; then

            warn "恢复原配置："
            echo "  $backup"

            cp -a \
                -- "$backup" \
                "$CONF"

            systemctl restart \
                vsftpd || true

        fi

        die "初始化失败，已尽量恢复原配置。"
    fi

    ok "vsftpd 已启动"

    if command -v ufw >/dev/null 2>&1 \
        && ufw status 2>/dev/null \
            | grep -q '^Status: active'; then

        info "检测到 UFW 已启用"

        info "开放 21/tcp..."

        ufw allow \
            21/tcp \
            >/dev/null

        ok "21/tcp 已开放"

        info "开放 PASV ${PASV_MIN}-${PASV_MAX}/tcp..."

        ufw allow \
            "${PASV_MIN}:${PASV_MAX}/tcp" \
            >/dev/null

        ok "${PASV_MIN}-${PASV_MAX}/tcp 已开放"

    else

        warn "UFW 未启用或未安装，不修改防火墙"

    fi

    echo
    echo "============================================================"
    echo "  VSFTPD 初始化完成"
    echo "============================================================"
    echo
    echo "配置文件："
    echo "  $CONF"
    echo
    echo "FTP 用户白名单："
    echo "  $ALLOW_FILE"
    echo
    echo "FTP 控制端口："
    echo "  21/tcp"
    echo
    echo "PASV："
    echo "  ${PASV_MIN}-${PASV_MAX}/tcp"
    echo
    echo "公共 FTP 根目录："
    echo "  无"
    echo

    info "监听检查："

    if ss -lntp 2>/dev/null \
        | grep -E 'LISTEN.+:21([[:space:]]|$)'; then

        ok "FTP 21 端口已监听"

    else

        warn "没有从 ss 中匹配到 :21"
        warn "请执行：systemctl status vsftpd"

    fi

    echo

    warn "如果服务器位于 NAT / 云公网后面："
    warn "还需要在云安全组 / 路由器开放 21 和 PASV 端口。"
    warn "某些 NAT 环境还需要设置 pasv_address。"
}

# 设置用户密码。
prompt_password() {

    local username="$1"

    local p1
    local p2

    while true; do

        read -rsp \
            "请输入 FTP 密码: " \
            p1

        echo

        if [[ -z "$p1" ]]; then
            warn "密码不能为空"
            continue
        fi

        read -rsp \
            "再次输入 FTP 密码: " \
            p2

        echo

        if [[ "$p1" != "$p2" ]]; then

            warn "两次密码不一致，请重新输入"
            continue

        fi

        if ! printf '%s:%s\n' \
            "$username" \
            "$p1" \
            | chpasswd; then

            unset p1
            unset p2

            return 1
        fi

        unset p1
        unset p2

        ok "密码设置成功"

        return 0
    done
}

# 授予目录访问权限。
grant_acl() {

    local username="$1"
    local dir="$2"

    info "为 $username 设置现有目录/文件 ACL..."

    if ! setfacl \
        -R \
        -m "u:${username}:rwX" \
        -- "$dir"; then

        return 1
    fi

    ok "现有文件/目录 ACL 设置完成"

    info "设置 default ACL..."

    if ! find "$dir" \
        -type d \
        -exec setfacl \
            -m "d:u:${username}:rwx" \
            -- {} +; then

        return 1
    fi

    ok "default ACL 设置完成"

    local acl_line
    local effective

    acl_line="$(
        getfacl \
            -cp \
            -- "$dir" \
            2>/dev/null \
        | awk \
            -v u="$username" \
            '$0 ~ ("^user:" u ":") {
                print
                exit
            }'
    )"

    if [[ "$acl_line" == *"#effective:"* ]]; then

        effective="${acl_line##*#effective:}"

        effective="$(
            printf '%s' "$effective" \
            | tr -d '[:space:]'
        )"

    else

        effective="$(
            printf '%s\n' "$acl_line" \
            | cut -d: -f3 \
            | tr -d '[:space:]'
        )"

    fi

    if [[ "$effective" != *r* \
        || "$effective" != *w* \
        || "$effective" != *x* ]]; then

        warn "根目录 ACL effective 权限异常："
        warn "${effective:-unknown}"

        echo

        getfacl \
            -p \
            -- "$dir" || true

        return 1
    fi

    ok "ACL 验证通过：${username} -> rwx"
}

# 添加允许登录的用户。
add_allowed_user() {

    local username="$1"

    touch "$ALLOW_FILE"

    chmod 0600 \
        "$ALLOW_FILE"

    if grep -Fxq \
        "$username" \
        "$ALLOW_FILE"; then

        warn "$username 已存在于 FTP 白名单"

    else

        printf '%s\n' \
            "$username" \
            >> "$ALLOW_FILE"

        ok "$username 已加入 FTP 白名单"

    fi
}

# 创建 FTP 用户。
add_ftp_user() {

    echo
    echo "============================================================"
    echo "  2) 添加 FTP 用户并绑定目录"
    echo "============================================================"
    echo

    command -v vsftpd \
        >/dev/null 2>&1 \
        || die "vsftpd 未安装，请先执行菜单 1"

    command -v setfacl \
        >/dev/null 2>&1 \
        || die "setfacl 不存在，请先执行菜单 1"

    check_managed_config \
        || die "vsftpd 尚未由本脚本初始化，请先执行菜单 1"

    local username

    while true; do

        read -rp \
            "FTP 用户名: " \
            username

        if ! validate_username "$username"; then

            warn "用户名不合法"
            warn "只允许："
            warn "  a-z"
            warn "  0-9"
            warn "  _"
            warn "  -"
            warn "必须以小写字母或 _ 开头"
            warn "最长 32 字符"

            continue
        fi

        if getent passwd \
            "$username" \
            >/dev/null; then

            warn "系统用户 '$username' 已存在"
            warn "为避免误开放真实 Linux 用户，请使用 FTP 专用用户名"

            continue
        fi

        break
    done

    local raw_dir
    local ftp_dir

    while true; do

        read -rp \
            "绑定目录（绝对路径，例如 /data/project-a）: " \
            raw_dir

        if ! ftp_dir="$(normalize_dir "$raw_dir")"; then

            warn "请输入绝对路径，例如："
            warn "  /data/project-a"

            continue
        fi

        if [[ "$ftp_dir" == "/" ]]; then

            warn "禁止把系统根目录 / 作为 FTP 根目录"

            continue
        fi

        break
    done

    echo
    echo "即将创建："
    echo
    echo "  FTP 用户    : $username"
    echo "  绑定目录    : $ftp_dir"
    echo "  FTP 中的 /  : $ftp_dir"
    echo "  Linux HOME  : $ftp_dir"
    echo "  隔离方式    : chroot"
    echo "  权限方式    : POSIX ACL"
    echo "  owner/group : 保持原样"
    echo

    local confirm

    read -rp \
        "确认继续？[Y/n]: " \
        confirm

    confirm="${confirm:-Y}"

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

        warn "已取消"
        return 0

    fi

    if [[ ! -d "$ftp_dir" ]]; then

        info "目录不存在"

        info "执行："
        echo "  mkdir -p -- '$ftp_dir'"

        mkdir -p \
            -- "$ftp_dir"

        ok "目录创建成功"

    else

        ok "目录已存在"

        info "不会修改原 owner/group"

    fi

    local nologin_shell

    nologin_shell="$(get_nologin_shell)"

    ensure_nologin_in_shells \
        "$nologin_shell"

    info "创建 FTP 专用 Linux 用户..."

    useradd \
        -M \
        -d "$ftp_dir" \
        -s "$nologin_shell" \
        "$username"

    ok "用户创建成功"

    echo "  HOME : $ftp_dir"
    echo "  SHELL: $nologin_shell"

    if ! prompt_password "$username"; then

        err "密码设置失败"

        warn "删除刚创建的系统用户"
        warn "不会删除绑定目录"

        userdel \
            "$username" || true

        return 1
    fi

    if ! grant_acl \
        "$username" \
        "$ftp_dir"; then

        err "ACL 设置失败"

        err "FTP 用户不会加入白名单"

        warn "请检查："
        warn "  1. 文件系统是否支持 POSIX ACL"
        warn "  2. 是否存在特殊 ACL mask"
        warn "  3. 是否为只读挂载"

        return 1
    fi

    add_allowed_user \
        "$username"

    info "重启 vsftpd 使用户白名单立即生效..."

    if ! systemctl restart vsftpd; then

        err "vsftpd 重启失败"

        err "检查："
        echo
        echo "  journalctl -u vsftpd -n 50 --no-pager"
        echo

        return 1
    fi

    ok "vsftpd 已重启"

    echo
    echo "============================================================"
    echo "  FTP 用户创建完成"
    echo "============================================================"
    echo
    echo "用户名："
    echo "  $username"
    echo
    echo "Linux HOME："
    echo "  $ftp_dir"
    echo
    echo "FTP 根目录 /："
    echo "  $ftp_dir"
    echo
    echo "Shell："
    echo "  $nologin_shell"
    echo
    echo "FTP："
    echo "  port 21"
    echo
    echo "权限："
    echo "  ✓ 查看目录"
    echo "  ✓ 下载文件"
    echo "  ✓ 上传文件"
    echo "  ✓ 覆盖文件"
    echo "  ✓ 新建文件"
    echo "  ✓ 新建目录"
    echo "  ✓ 删除文件"
    echo "  ✓ 删除目录"
    echo "  ✓ 重命名"
    echo "  ✓ 修改已有文件"
    echo "  ✓ 访问现有全部子目录"
    echo "  ✓ 新内容自动继承 ACL"
    echo
    echo "原目录："
    echo "  ✓ owner 不改变"
    echo "  ✓ group 不改变"
    echo
    echo "隔离："
    echo "  ✓ $ftp_dir = FTP /"
    echo "  ✓ 无法 cd .. 离开"
    echo "  ✓ 无法浏览 jail 外的 /etc"
    echo "  ✓ 无法浏览 jail 外的 /root"
    echo "  ✓ 无法浏览 jail 外的 /home"
    echo

    info "根目录 ACL："

    getfacl \
        -cp \
        -- "$ftp_dir" \
        2>/dev/null \
        | sed -n '1,20p' \
        || true
}

# 显示菜单。
show_menu() {

    echo
    echo "============================================================"
    echo "              Ubuntu VSFTPD 管理工具"
    echo "============================================================"
    echo
    echo "  1) 安装 / 初始化 vsftpd"
    echo
    echo "     - 不创建用户"
    echo "     - 不设置公共 FTP 根目录"
    echo
    echo "  2) 添加 FTP 用户并绑定目录"
    echo
    echo "     - 目录不存在自动 mkdir -p"
    echo "     - HOME = FTP 根目录"
    echo "     - chroot 禁止越界"
    echo "     - ACL 递归完整读写"
    echo
    echo "  0) 退出"
    echo
}

# 运行管理菜单。
main() {

    require_root "$@"

    check_ubuntu_debian

    while true; do

        show_menu

        read -rp \
            "请选择 [0-2]: " \
            choice

        case "$choice" in

            1)
                install_vsftpd
                ;;

            2)
                add_ftp_user
                ;;

            0)
                exit 0
                ;;

            *)
                warn "无效选择：$choice"
                ;;
        esac
    done
}

main "$@"
