#!/usr/bin/env bash
# 契约
# 做：停 GNOME 远程桌面，安装 xrdp + XFCE，放行 3389/tcp
# 系统：Ubuntu 22.04+，需要 sudo 与运行中的 systemd
# 权限：普通用户执行（不要包 sudo）；提权只在脚本内
# 参数：无
# 改：停 gnome-remote-desktop、装 xrdp/xfce、写当前用户 ~/.xsession、xrdp 加 ssl-cert 组并重启、防火墙 3389
# 完：成功后删除脚本自身；3389 未监听则保留并非零退出
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

XSESSION_TMP=

die() { echo "[ERROR] $*" >&2; exit 1; }

cleanup() {
    if [[ -n "${XSESSION_TMP}" && -f "${XSESSION_TMP}" ]]; then
        rm -f -- "${XSESSION_TMP}"
    fi
}
trap cleanup EXIT

# $1 >= $2 时成功。sort -C 读完整输入，避免管道提前关闭。
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

check_environment() {
    echo "=== 检查运行环境 ==="
    [[ "$#" -eq 0 ]] || die "没有参数。用法: $(basename "$0")"
    [[ "$(uname -s)" == Linux && -r /etc/os-release ]] || die "仅支持 Ubuntu Linux。"
    # shellcheck source=/dev/null
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "仅支持 Ubuntu。"
    [[ -n "${VERSION_ID:-}" ]] || die "无法识别 Ubuntu 版本。"
    version_ge "${VERSION_ID}" "22.04" || die "需要 Ubuntu 22.04 或更高版本，当前是 ${VERSION_ID}。"
    [[ "${EUID}" -ne 0 ]] || die "请勿用 root 直接运行，用要登录远程桌面的普通用户执行。"
    [[ -n "${HOME:-}" && -d "${HOME}" && -w "${HOME}" ]] || die "HOME 不可写。"
    command -v sudo >/dev/null 2>&1 || die "未找到 sudo，请先安装。"
    [[ -d /run/systemd/system ]] || die "需要正在运行的 systemd。"
    command -v systemctl >/dev/null 2>&1 || die "未找到 systemctl。"
    sudo -v || die "sudo 验证失败。"
}

stop_gnome_remote_desktop() {
    local sys_unit="" user_unit="" uid runtime found=0

    echo "=== 停掉自带远程桌面 ==="
    sys_unit=$(systemctl list-unit-files --no-legend --no-pager 'gnome-remote-desktop.service' 2>/dev/null || true)
    if [[ "${sys_unit}" == gnome-remote-desktop.service* ]]; then
        found=1
        sudo systemctl disable --now gnome-remote-desktop.service \
            || echo "警告：系统级 gnome-remote-desktop 未能停用" >&2
    fi

    uid=$(id -u)
    runtime="/run/user/${uid}"
    if [[ -S "${runtime}/systemd/private" ]]; then
        user_unit=$(XDG_RUNTIME_DIR="${runtime}" systemctl --user list-unit-files --no-legend --no-pager 'gnome-remote-desktop.service' 2>/dev/null || true)
        if [[ "${user_unit}" == gnome-remote-desktop.service* ]]; then
            found=1
            XDG_RUNTIME_DIR="${runtime}" systemctl --user disable --now gnome-remote-desktop.service \
                || echo "警告：用户级 gnome-remote-desktop 未能停用" >&2
        fi
    fi

    if [[ "${found}" -eq 0 ]]; then
        echo "未发现自带远程桌面服务，跳过"
    fi
}

install_packages() {
    echo "=== 安装 xrdp + XFCE ==="
    sudo DEBIAN_FRONTEND=noninteractive apt-get update \
        || die "apt-get update 失败，请检查网络或软件源。"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        xrdp xorgxrdp xfce4 xfce4-goodies \
        || die "安装失败，请检查网络或软件源。"
    id xrdp >/dev/null 2>&1 || die "安装后未找到 xrdp 用户。"
    getent group ssl-cert >/dev/null 2>&1 || die "未找到 ssl-cert 组。"
}

write_xsession() {
    local session="${HOME}/.xsession"

    [[ ! -e "${session}" || -f "${session}" ]] || die "${session} 已存在且不是普通文件。"
    XSESSION_TMP=$(mktemp "${HOME}/.xsession.tmp.XXXXXX")
    cat >"${XSESSION_TMP}" <<'EOF'
#!/bin/sh
exec /usr/bin/startxfce4
EOF
    chmod 755 "${XSESSION_TMP}"
    if [[ -f "${session}" ]] && ! cmp -s "${XSESSION_TMP}" "${session}"; then
        local backup="${session}.bak-$(date +%Y%m%d-%H%M%S)"
        [[ ! -e "${backup}" ]] || die "备份已存在: ${backup}"
        cp -a -- "${session}" "${backup}"
        echo "已备份原 ${session}"
    fi
    mv -f -- "${XSESSION_TMP}" "${session}"
    XSESSION_TMP=
}

configure_xrdp() {
    echo "=== 配置 xrdp ==="
    if [[ " $(id -nG xrdp) " != *" ssl-cert "* ]]; then
        sudo adduser xrdp ssl-cert
    fi
    write_xsession

    echo "=== 启动服务 ==="
    sudo systemctl enable xrdp || die "xrdp 启动失败。"
    # 重新启动后 xrdp 才具备 ssl-cert 组权限；已有会话会断开。
    sudo systemctl restart xrdp || die "xrdp 启动失败。"
}

line_present() {
    local pattern="$1"
    awk -v pattern="${pattern}" '$0 == pattern { found=1 } END { exit !found }'
}

open_firewall() {
    local ufw_status="" fw_state="" iptables_input=""

    echo "=== 检测并放行防火墙 ==="
    if command -v ufw >/dev/null 2>&1; then
        if ! ufw_status=$(LANG=C sudo ufw status 2>/dev/null); then
            die "无法读取 ufw 状态。"
        fi
        if printf '%s\n' "${ufw_status}" | line_present "Status: active"; then
            echo "检测到 ufw 已启用，放行 3389/tcp"
            if printf '%s\n' "${ufw_status}" | awk '$1 == "3389/tcp" && $2 == "ALLOW" { found=1 } END { exit !found }'; then
                echo "ufw 已放行 3389/tcp"
                return 0
            fi
            sudo ufw allow 3389/tcp
            return 0
        fi
    fi

    if command -v firewall-cmd >/dev/null 2>&1; then
        fw_state=$(LANG=C sudo firewall-cmd --state 2>/dev/null || true)
        if [[ "${fw_state}" == "running" ]]; then
            echo "检测到 firewalld 已启用，放行 3389/tcp"
            if sudo firewall-cmd --query-port=3389/tcp >/dev/null 2>&1; then
                echo "firewalld 已放行 3389/tcp"
                return 0
            fi
            if ! sudo firewall-cmd --permanent --add-port=3389/tcp; then
                sudo firewall-cmd --permanent --query-port=3389/tcp >/dev/null 2>&1 \
                    || die "firewalld 放行 3389/tcp 失败。"
            fi
            sudo firewall-cmd --reload || die "firewalld 重载失败。"
            return 0
        fi
    fi

    if command -v iptables >/dev/null 2>&1; then
        if ! iptables_input=$(LANG=C sudo iptables -L INPUT -n 2>/dev/null); then
            die "无法读取 iptables INPUT。"
        fi
        if printf '%s\n' "${iptables_input}" | awk '/DROP|REJECT/ { found=1 } END { exit !found }'; then
            echo "检测到 iptables 有拒绝规则，放行 3389/tcp"
            if sudo iptables -C INPUT -p tcp --dport 3389 -j ACCEPT >/dev/null 2>&1; then
                echo "iptables 已放行 3389/tcp"
                return 0
            fi
            sudo iptables -I INPUT -p tcp --dport 3389 -j ACCEPT
            echo "iptables 规则只在本次运行有效，重启后不保留"
            return 0
        fi
    fi

    echo "未检测到活跃防火墙，跳过放行"
}

port_listening() {
    sudo ss -H -ltn 'sport = :3389' | awk 'NF { found=1 } END { exit !found }'
}

verify_listen() {
    local attempt

    echo "=== 验证 ==="
    command -v ss >/dev/null 2>&1 || die "未找到 ss，无法验证 3389。"
    for attempt in 1 2 3 4 5; do
        if port_listening; then
            echo "端口 3389 已监听"
            return 0
        fi
        sleep 1
    done
    echo "警告：端口 3389 未监听，请检查 xrdp 服务" >&2
    systemctl is-active xrdp >&2 || true
    return 1
}

print_result() {
    local addr

    echo "用 Windows App 连接: 局域网IP:3389"
    if command -v ip >/dev/null 2>&1; then
        while read -r addr; do
            [[ -n "${addr}" ]] && echo "  ${addr}:3389"
        done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
    fi
    echo "Session 选: Xorg"
    echo "用户名: $(id -un)"
    echo "密码: 系统登录密码"
}

main() {
    local listen_ok=0

    check_environment "$@"
    stop_gnome_remote_desktop
    install_packages
    configure_xrdp
    open_firewall
    if verify_listen; then
        listen_ok=1
    fi
    if [[ ! -f /etc/xrdp/xrdp.ini ]] || ! grep -q '^\[Xorg\]' /etc/xrdp/xrdp.ini; then
        echo "警告：未找到 [Xorg] 会话，客户端里可能没有 Xorg 选项" >&2
    fi
    if [[ "${listen_ok}" -eq 1 ]]; then
        echo "=== 完成 ==="
    else
        echo "=== 未完成：3389 未监听 ==="
    fi
    print_result
    [[ "${listen_ok}" -eq 1 ]]
}

main "$@"
rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
