#!/usr/bin/env bash

set -Eeuo pipefail

INTERFACE="any"
INCLUDE_SSH=0
LIST_INTERFACES=0

declare -a FILTER_PARTS=()

info() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERR ] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
用法：
  network_flow_watch.sh [选项] [--] [tcpdump 过滤表达式]

选项：
  -i, --interface <网卡>  只监控指定网卡；默认 any，即全部常规网卡
      --include-ssh       包含当前 SSH 会话流量
      --list-interfaces   列出 tcpdump 可用的抓包接口后退出
  -h, --help              显示帮助

示例：
  ./network_flow_watch.sh
  ./network_flow_watch.sh -i wg0
  ./network_flow_watch.sh -- 'host 10.0.0.8 and port 443'
  ./network_flow_watch.sh -i wg0 -- 'net 10.8.0.0/24'

运行期间按 Ctrl+C 退出。
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interface)
                [[ $# -ge 2 ]] || die "$1 缺少网卡名称"
                INTERFACE="$2"
                shift 2
                ;;
            --include-ssh)
                INCLUDE_SSH=1
                shift
                ;;
            --list-interfaces)
                LIST_INTERFACES=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                FILTER_PARTS+=("$@")
                break
                ;;
            -*)
                die "未知选项：$1"
                ;;
            *)
                FILTER_PARTS+=("$1")
                shift
                ;;
        esac
    done
}

require_linux() {
    [[ "$(uname -s)" == "Linux" ]] \
        || die "当前脚本仅支持 Linux"
}

find_tcpdump() {
    local tcpdump_bin

    tcpdump_bin="$(command -v tcpdump || true)"

    [[ -n "$tcpdump_bin" ]] \
        || die "未安装 tcpdump。Ubuntu / Debian：sudo apt-get update && sudo apt-get install -y tcpdump"

    printf '%s\n' "$tcpdump_bin"
}

validate_interface() {
    if [[ "$INTERFACE" == "any" ]]; then
        return 0
    fi

    [[ "$INTERFACE" != */* ]] \
        || die "网卡名称不合法：$INTERFACE"

    [[ -e "/sys/class/net/$INTERFACE" ]] \
        || die "网卡不存在：$INTERFACE"
}

build_filter() {
    local user_filter=""
    local ssh_filter=""
    local client_ip=""
    local client_port=""
    local server_ip=""
    local server_port=""

    if [[ ${#FILTER_PARTS[@]} -gt 0 ]]; then
        user_filter="${FILTER_PARTS[*]}"
    fi

    if [[ $INCLUDE_SSH -eq 0 && -n "${SSH_CONNECTION:-}" ]]; then
        read -r \
            client_ip \
            client_port \
            server_ip \
            server_port \
            <<< "$SSH_CONNECTION"

        if [[ "$client_ip" =~ ^[0-9A-Fa-f:.]+$ \
            && "$server_port" =~ ^[0-9]+$ ]]; then

            ssh_filter="not (tcp and host ${client_ip} and port ${server_port})"
            info "已排除当前 SSH 会话：${client_ip} -> ${server_ip}:${server_port}" >&2
        else
            warn "SSH_CONNECTION 格式异常，未自动排除当前 SSH 会话"
        fi
    fi

    if [[ -n "$user_filter" && -n "$ssh_filter" ]]; then
        printf '(%s) and (%s)\n' "$user_filter" "$ssh_filter"
    elif [[ -n "$user_filter" ]]; then
        printf '%s\n' "$user_filter"
    else
        printf '%s\n' "$ssh_filter"
    fi
}

run_capture() {
    local tcpdump_bin="$1"
    local capture_filter="$2"

    local -a tcpdump_args=(
        -i "$INTERFACE"
        -nn
        -tttt
        -l
        -e
        -q
        -s 128
        -Q inout
    )

    if [[ -n "$capture_filter" ]]; then
        tcpdump_args+=("$capture_filter")
    fi

    echo
    info "监控接口：$INTERFACE"
    info "输出内容：接口、收发方向、源地址、目标地址、协议和长度"
    info "按 Ctrl+C 退出；不会启动后台进程"

    if [[ "$INTERFACE" == "any" ]]; then
        warn "隧道流量可能同时出现在虚拟接口和承载接口，这是封装前后两层流量"
    fi

    if [[ $INCLUDE_SSH -eq 1 && -n "${SSH_CONNECTION:-}" ]]; then
        warn "已包含当前 SSH 会话，抓包输出可能持续制造新的 SSH 流量"
    fi

    echo

    if [[ ${EUID} -eq 0 ]]; then
        exec "$tcpdump_bin" "${tcpdump_args[@]}"
    fi

    info "抓包需要 root 权限，调用 sudo..."
    exec sudo -- "$tcpdump_bin" "${tcpdump_args[@]}"
}

main() {
    parse_args "$@"
    require_linux

    local tcpdump_bin
    tcpdump_bin="$(find_tcpdump)"

    if [[ $LIST_INTERFACES -eq 1 ]]; then
        exec "$tcpdump_bin" -D
    fi

    validate_interface

    local capture_filter
    capture_filter="$(build_filter)"

    run_capture \
        "$tcpdump_bin" \
        "$capture_filter"
}

main "$@"
