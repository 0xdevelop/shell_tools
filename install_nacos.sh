#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# 固定配置（最终定稿：写死，不提供环境变量覆盖）
# =========================================================
NACOS_VERSION="3.1.0"
INSTALL_DIR="/opt/nacos"
NACOS_USER="nacos"
NACOS_GROUP="nacos"

# Temurin JDK17 固定 tag（只固定 tag，资产文件名动态解析）
# 注意：URL 中 + 必须编码为 %2B
JDK_TAG_ENC="jdk-17.0.17%2B10"

JAVA_DIR="${INSTALL_DIR}/jdk"
NACOS_DIR="${INSTALL_DIR}/nacos"
SYSTEMD_UNIT="/etc/systemd/system/nacos.service"

TUNA_BASE="https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk"
ADOPTIUM_TAG_PAGE="https://github.com/adoptium/temurin17-binaries/releases/tag/${JDK_TAG_ENC}"
NACOS_URL="https://github.com/alibaba/nacos/releases/download/${NACOS_VERSION}/nacos-server-${NACOS_VERSION}.tar.gz"

# =========================================================
# 基础函数
# =========================================================
need_root() { [ "$(id -u)" -eq 0 ] || { echo "❌ 请使用 root 执行（sudo）"; exit 1; }; }
need_cmd()  { command -v "$1" >/dev/null 2>&1 || { echo "❌ 缺少命令: $1（请先安装）"; exit 1; }; }

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "x64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "❌ 不支持的架构: $(uname -m)（仅支持 x86_64 / aarch64）"; exit 1 ;;
  esac
}

detect_country() {
  # Cloudflare trace：返回 CN/SG/US 等；失败则 UNKNOWN
  curl -fsSL --max-time 2 https://www.cloudflare.com/cdn-cgi/trace \
    | sed -n 's/^loc=//p' | head -n1 || echo "UNKNOWN"
}

ensure_user() {
  # 存在则复用；不存在才创建，不修改已有用户
  if id "${NACOS_USER}" >/dev/null 2>&1; then
    echo "✔ 用户已存在：${NACOS_USER}（复用，不修改）"
  else
    echo "📌 创建系统用户：${NACOS_USER}"
    useradd -r -s /usr/sbin/nologin -d "${INSTALL_DIR}" "${NACOS_USER}"
  fi
}

download() {
  curl -fL --retry 3 --retry-delay 1 "$1" -o "$2"
}

extract_strip1() {
  mkdir -p "$2"
  tar -xzf "$1" -C "$2" --strip-components=1
}

# =========================================================
# 动态解析 JDK URL（不写死文件名）
# =========================================================
fetch_latest_tuna_jdk_url() {
  local arch="$1"
  local dir="${TUNA_BASE}/${arch}/linux/"

  echo "📡 解析清华 TUNA 目录: ${dir}"
  local file
  file="$(curl -fsSL "${dir}" \
    | grep -oE 'OpenJDK17U-jdk_'${arch}'_linux_hotspot_[^"]+\.tar\.gz' \
    | sort -V | tail -n1)"

  [ -n "$file" ] || { echo "❌ TUNA 目录未解析到 JDK17 包"; return 1; }
  echo "${dir}${file}"
}

fetch_github_jdk_url_from_tag_page() {
  local arch="$1"

  echo "📡 解析 Adoptium tag 页面: ${ADOPTIUM_TAG_PAGE}"
  local file
  file="$(curl -fsSL "${ADOPTIUM_TAG_PAGE}" \
    | grep -oE 'OpenJDK17U-jdk_'${arch}'_linux_hotspot_[0-9]+\.[0-9]+\.[0-9]+_[0-9]+\.tar\.gz' \
    | head -n1)"

  [ -n "$file" ] || { echo "❌ 未能从 GitHub tag 页面解析到 JDK17 资产文件名"; return 1; }

  # download URL 中 tag 需要用 +（不是 %2B）
  local tag_decoded="${JDK_TAG_ENC//%2B/+}"
  echo "https://github.com/adoptium/temurin17-binaries/releases/download/${tag_decoded}/${file}"
}

install_jdk17() {
  local arch="$1"
  local country="$2"

  if [ -x "${JAVA_DIR}/bin/java" ]; then
    echo "✔ 已存在内置 JDK：${JAVA_DIR}"
    "${JAVA_DIR}/bin/java" -version || true
    return 0
  fi

  echo "📦 安装内置 JDK17 到: ${JAVA_DIR}"
  mkdir -p "${JAVA_DIR}"

  local url=""
  if [ "${country}" = "CN" ]; then
    echo "🚀 CN 网络：优先 TUNA 动态解析文件名"
    url="$(fetch_latest_tuna_jdk_url "${arch}")" || {
      echo "⚠️  TUNA 解析失败，回退到 GitHub tag 页面解析"
      url="$(fetch_github_jdk_url_from_tag_page "${arch}")" || exit 1
    }
  else
    echo "🌍 非 CN 网络：优先 GitHub tag 页面动态解析文件名"
    url="$(fetch_github_jdk_url_from_tag_page "${arch}")" || {
      echo "⚠️  GitHub 解析失败，回退到 TUNA 解析"
      url="$(fetch_latest_tuna_jdk_url "${arch}")" || exit 1
    }
  fi

  echo "⬇️  下载 JDK: ${url}"
  download "${url}" /tmp/jdk17.tar.gz
  extract_strip1 /tmp/jdk17.tar.gz "${JAVA_DIR}"
  rm -f /tmp/jdk17.tar.gz

  echo "🔍 验证 Java："
  "${JAVA_DIR}/bin/java" -version
}

install_nacos() {
  if [ -x "${NACOS_DIR}/bin/startup.sh" ]; then
    echo "✔ 已存在 Nacos：${NACOS_DIR}"
    return 0
  fi

  echo "📦 安装 Nacos ${NACOS_VERSION} 到: ${NACOS_DIR}"
  mkdir -p "${NACOS_DIR}"

  echo "⬇️  下载 Nacos: ${NACOS_URL}"
  download "${NACOS_URL}" /tmp/nacos.tar.gz
  extract_strip1 /tmp/nacos.tar.gz "${NACOS_DIR}"
  rm -f /tmp/nacos.tar.gz
}

# =========================================================
# systemd（0 侵入：不写 /etc/default，不依赖外部 env）
# =========================================================
write_systemd_unit_overwrite() {
  if [ -f "${SYSTEMD_UNIT}" ]; then
    echo "⚠️  ${SYSTEMD_UNIT} 已存在：将覆盖"
  else
    echo "📝 创建 ${SYSTEMD_UNIT}"
  fi

  cat > "${SYSTEMD_UNIT}" <<EOF
[Unit]
Description=Nacos Server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=${NACOS_USER}
Group=${NACOS_GROUP}

# 关键：保证 logs/ data/ 都归集到安装目录
WorkingDirectory=${NACOS_DIR}

# 明确使用内置 JDK，不依赖系统环境
Environment="JAVA_HOME=${JAVA_DIR}"
Environment="PATH=${JAVA_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 参数写死：可审计可复现
ExecStart=${NACOS_DIR}/bin/startup.sh -m standalone
ExecStop=${NACOS_DIR}/bin/shutdown.sh

Restart=on-failure
RestartSec=5
TimeoutStartSec=180
TimeoutStopSec=60
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
  systemctl daemon-reload
  systemctl enable nacos >/dev/null 2>&1 || true
  systemctl restart nacos || systemctl start nacos
  systemctl status nacos --no-pager -l || true
}

# =========================================================
# 主流程
# =========================================================
need_root
need_cmd curl
need_cmd tar
need_cmd systemctl

ARCH="$(detect_arch)"
COUNTRY="$(detect_country)"

echo "✔ 架构: ${ARCH}"
echo "✔ 公网归属: ${COUNTRY}"
echo "✔ 固定安装目录: ${INSTALL_DIR}"
echo "✔ 固定 Nacos 版本: ${NACOS_VERSION}"
echo "✔ 固定 JDK tag: ${JDK_TAG_ENC}"

ensure_user
mkdir -p "${INSTALL_DIR}"

install_jdk17 "${ARCH}" "${COUNTRY}"
install_nacos

write_systemd_unit_overwrite

# 权限修正：确保 logs/ data 可写
chown -R "${NACOS_USER}:${NACOS_GROUP}" "${INSTALL_DIR}"

start_service

echo "======================================"
echo "✅ 安装完成（最终定稿 / 0 侵入）"
echo "控制台: http://<IP>:8848/nacos"
echo "默认账号: nacos / nacos"
echo "文件日志: ${NACOS_DIR}/logs/ （start.out / nacos.log）"
echo "systemd 日志: journalctl -u nacos -f"
echo "======================================"
