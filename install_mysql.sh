#!/usr/bin/env bash
set -euo pipefail

MYSQL_REPO=https://repo.mysql.com/apt
MYSQL_KEY_URL=https://repo.mysql.com/RPM-GPG-KEY-mysql-2025
MYSQL_KEY_FINGERPRINT=BCA43417C3B485DD128EC6D4B7B3B788A8D3785C
WORK_DIR=

die() { echo "[ERROR] $*" >&2; exit 1; }

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

download() {
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --retry 2 --connect-timeout 15 --max-time 120 "$1" -o "$2"
}

check_environment() {
    [[ "$(uname -s)" == Linux && -r /etc/os-release ]] || die "仅支持 Ubuntu / Debian Linux。"
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-}" in ubuntu|debian) ;; *) die "仅支持 Ubuntu / Debian，不自动套用其他发行版的源。" ;; esac
    DISTRO=$ID
    CODENAME=${VERSION_CODENAME:-}
    [[ "$CODENAME" =~ ^[a-z]+$ ]] || die "无法识别发行版代号。"
    [[ "$EUID" -eq 0 ]] || die "请使用 sudo bash $0。"
    [[ -t 0 ]] || die "请在交互终端运行，需要选择版本和配置 MySQL 认证。"
    [[ -d /run/systemd/system ]] || die "需要正在运行的 systemd。"
    ARCH=$(dpkg --print-architecture)

    local existing
    existing=$(dpkg-query -W -f='${binary:Package} ${db:Status-Status}\n' \
        'mysql-server*' 'mysql-community-*' 'mariadb-server*' 'percona-server*' 2>/dev/null || true)
    if printf '%s\n' "$existing" | awk 'NF == 2 && $2 != "not-installed" && $2 != "config-files" { found=1 } END { exit !found }'; then
        die "已存在数据库服务端软件包；本脚本仅用于新装，不执行升级、降级或替换。"
    fi
    if command -v mysqld >/dev/null || command -v mariadbd >/dev/null; then
        die "检测到已有数据库服务端程序，请先核对现有安装。"
    fi
    if [[ -d /var/lib/mysql ]] && [[ -n "$(find /var/lib/mysql -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        die "/var/lib/mysql 非空；不覆盖已有数据。"
    fi
    # 避免不同 MySQL 源混用或覆盖已有源配置。
    if grep -lE 'repo\.mysql\.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.list \
        /etc/apt/sources.list.d/*.sources 2>/dev/null; then
        die "已存在 MySQL 官方源，请先核对并整理上面列出的配置。"
    fi
    for existing in /etc/apt/sources.list.d/mysql-community.list \
        /etc/apt/preferences.d/mysql-community /usr/share/keyrings/mysql-community.gpg; do
        [[ ! -e "$existing" && ! -L "$existing" ]] || die "配置已存在，不覆盖：$existing"
    done
}

load_versions() {
    local fingerprint components component path hash version current best
    download "$MYSQL_KEY_URL" "$WORK_DIR/mysql.asc"
    fingerprint=$(gpg --homedir "$WORK_DIR/gnupg" --batch --show-keys --with-colons \
        "$WORK_DIR/mysql.asc" | awk -F: '$1 == "fpr" { print $10; exit }')
    [[ "$fingerprint" == "$MYSQL_KEY_FINGERPRINT" ]] || die "MySQL 签名公钥指纹不匹配。"
    gpg --homedir "$WORK_DIR/gnupg" --batch --yes --dearmor \
        --output "$WORK_DIR/mysql.gpg" "$WORK_DIR/mysql.asc"
    download "$MYSQL_REPO/$DISTRO/dists/$CODENAME/Release" "$WORK_DIR/Release"
    download "$MYSQL_REPO/$DISTRO/dists/$CODENAME/Release.gpg" "$WORK_DIR/Release.gpg"
    gpgv --homedir "$WORK_DIR/gnupg" --keyring "$WORK_DIR/mysql.gpg" \
        "$WORK_DIR/Release.gpg" "$WORK_DIR/Release"

    components=$(sed -n 's/^Components: //p' "$WORK_DIR/Release")
    SERIES=()
    VERSIONS=()
    for component in $components; do
        [[ "$component" == mysql-8.0 || "$component" =~ ^mysql-([89]|[1-9][0-9]+)\.[0-9]+-lts$ ]] || continue
        path="$component/binary-$ARCH/Packages"
        hash=$(awk -v path="$path" '
            /^SHA256:/ { active=1; next }
            /^[^ ]/ { active=0 }
            active && $3 == path { print $1 }
        ' "$WORK_DIR/Release")
        [[ -n "$hash" ]] || continue
        download "$MYSQL_REPO/$DISTRO/dists/$CODENAME/$path" "$WORK_DIR/Packages"
        printf '%s  %s\n' "$hash" "$WORK_DIR/Packages" | sha256sum --check --status || die "官方包索引校验失败，请稍后重试。"
        best=
        while IFS= read -r version; do
            [[ -n "$version" ]] || continue
            current=${version#*:}
            [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+- ]] || continue
            if [[ -z "$best" ]] || dpkg --compare-versions "$version" gt "$best"; then
                best=$version
            fi
        done < <(awk '/^Package: / { package=$2 } package == "mysql-community-server" && /^Version: / { print $2 }' "$WORK_DIR/Packages")
        [[ -n "$best" ]] || continue
        SERIES+=("$component")
        VERSIONS+=("$best")
    done
    [[ "${#SERIES[@]}" -gt 0 ]] || die "官方源没有适用于 $DISTRO $CODENAME / $ARCH 的 MySQL 8.0 或 LTS 服务端包。"
}

choose_version() {
    local index choice confirm
    echo
    echo "MySQL 官方 APT 源：$DISTRO $CODENAME / $ARCH"
    echo "选择版本系列（8.0 及 LTS；不包含 Innovation、测试版和 Cluster）："
    for index in "${!SERIES[@]}"; do
        printf '  %d) %s  最新补丁包：%s\n' "$((index + 1))" "${SERIES[$index]#mysql-}" "${VERSIONS[$index]}"
    done
    echo "  0) 退出"
    while true; do
        read -r -p "请选择编号：" choice || die "输入已结束。"
        [[ "$choice" != 0 ]] || exit 0
        if [[ "$choice" =~ ^[1-9][0-9]?$ ]] && (( choice <= ${#SERIES[@]} )); then
            break
        fi
        echo "请输入菜单中的编号。"
    done
    SELECTED=${SERIES[$((choice - 1))]}
    VERSION=${VERSIONS[$((choice - 1))]}
    echo "将配置官方源并安装 MySQL ${VERSION}，启用 mysql.service。"
    read -r -p "确认安装？[y/N] " confirm || die "输入已结束。"
    [[ "$confirm" == y || "$confirm" == Y ]] || exit 0
}

install_mysql() {
    local candidate installed actual expected
    install -m 0644 "$WORK_DIR/mysql.gpg" /usr/share/keyrings/mysql-community.gpg
    printf 'deb [arch=%s signed-by=/usr/share/keyrings/mysql-community.gpg] %s/%s/ %s %s\n' \
        "$ARCH" "$MYSQL_REPO" "$DISTRO" "$CODENAME" "$SELECTED" > "$WORK_DIR/mysql-community.list"
    install -m 0644 "$WORK_DIR/mysql-community.list" /etc/apt/sources.list.d/mysql-community.list
    printf 'Package: mysql-*\nPin: release o=MySQL,c=%s\nPin-Priority: 990\n' "$SELECTED" > "$WORK_DIR/mysql-community.pref"
    install -m 0644 "$WORK_DIR/mysql-community.pref" /etc/apt/preferences.d/mysql-community
    apt-get -o APT::Update::Error-Mode=any update
    candidate=$(apt-cache policy mysql-community-server | awk '/Candidate:/ { print $2 }')
    [[ "$candidate" == "$VERSION" ]] || die "APT 候选版本 $candidate 与选择的 $VERSION 不一致，停止安装。"
    DEBIAN_FRONTEND=readline apt-get --no-remove install "mysql-server=$VERSION" "mysql-community-server=$VERSION"
    installed=$(dpkg-query -W -f='${Version}' mysql-community-server)
    [[ "$installed" == "$VERSION" ]] || die "安装后的包版本不符合选择。"
    systemctl enable --now mysql.service
    systemctl is-active --quiet mysql.service || die "MySQL 服务未正常运行。"

    echo "连接本地 MySQL 并执行 SELECT VERSION() 验证；如需密码，请输入安装时设置的 root 密码。"
    if ! actual=$(mysql --no-defaults --connect-timeout=10 --protocol=socket -uroot -Nse 'SELECT VERSION()' 2>/dev/null); then
        actual=$(mysql --no-defaults --connect-timeout=10 --protocol=socket -uroot -p -Nse 'SELECT VERSION()') \
            || die "MySQL 已安装，但 SQL 登录验证失败，请检查认证配置。"
    fi
    expected=${VERSION#*:}
    expected=${expected%%-*}
    [[ "$actual" == "$expected" ]] || die "运行中版本 $actual 与已安装版本 $expected 不一致。"
    echo "[OK] MySQL $actual 已安装，服务运行中，SQL 查询验证通过。"
}

main() {
    case "${1:-}" in
        -h|--help)
            echo "用法：sudo bash $0"
            echo "通过 MySQL 官方 APT 源交互选择并新装 8.0 或 LTS 系列，仅支持 Ubuntu / Debian + systemd。"
            return ;;
        "") ;;
        *) die "不支持参数：$1；使用 --help 查看用法。" ;;
    esac
    [[ "$#" -le 1 ]] || die "不支持多余参数。"
    export LC_ALL=C
    check_environment
    apt-get -o APT::Update::Error-Mode=any update
    apt-get --no-remove install -y ca-certificates curl gnupg
    local script_dir
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    mkdir -p "$script_dir/tmp"
    WORK_DIR=$(mktemp -d "$script_dir/tmp/install-mysql.XXXXXX")
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir -m 0700 "$WORK_DIR/gnupg"
    load_versions
    choose_version
    install_mysql
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
