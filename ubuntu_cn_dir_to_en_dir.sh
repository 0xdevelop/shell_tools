#!/usr/bin/env bash
# 把 Ubuntu 中文 XDG 用户目录（桌面/下载/…）迁移为英文（Desktop/Downloads/…）。
# 先把内容复制进英文目录，再把中文目录整体移入带时间戳的备份目录——不删除任何数据。
# 用法: ./ubuntu_cn_dir_to_en_dir.sh [-y]   （-y 跳过交互确认，供无人值守使用）
set -Eeuo pipefail

# sudo 提权后 HOME 指向 /root，会把目录和配置建错对象；必须以目标桌面用户身份直接执行
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  echo "错误: 请以目标用户身份直接执行（不要 sudo），否则 HOME 指向 /root" >&2
  exit 1
fi

ASSUME_YES=0
if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then
  ASSUME_YES=1
fi

BACKUP_DIR="$HOME/.xdg-user-dirs-cn-backup-$(date +%Y%m%d-%H%M%S)"

# 迁移映射: 中文目录名|英文目录名|xdg-user-dirs 键名
DIR_PAIRS=(
  "桌面|Desktop|DESKTOP"
  "下载|Downloads|DOWNLOAD"
  "模板|Templates|TEMPLATES"
  "公共|Public|PUBLICSHARE"
  "文档|Documents|DOCUMENTS"
  "音乐|Music|MUSIC"
  "图片|Pictures|PICTURES"
  "视频|Videos|VIDEOS"
)

echo "==> 当前用户: $(whoami)"
echo "==> HOME: $HOME"
echo "本脚本将: 创建英文 XDG 目录 → 复制中文目录内容 → 中文目录整体移入备份 → 重写 ~/.config/user-dirs.dirs"
echo "备份目录: $BACKUP_DIR"

if [ "$ASSUME_YES" -ne 1 ]; then
  if [ -t 0 ]; then
    read -r -p "继续? [y/N] " answer
    case "$answer" in
      y | Y | yes | YES) ;;
      *)
        echo "已取消，未做任何修改"
        exit 0
        ;;
    esac
  else
    echo "错误: 非交互执行须显式加 -y 确认（脚本会移动 HOME 下的中文目录）" >&2
    exit 1
  fi
fi

mkdir -p "$HOME/.config"

# 迁移一个中文目录: 内容复制进英文目录，中文目录本体移入备份。重复执行安全（已迁走则跳过）。
migrate_dir() {
  local cn_name="$1"
  local en_name="$2"
  local cn_path
  cn_path="$HOME/$cn_name"
  local en_path
  en_path="$HOME/$en_name"

  mkdir -p "$en_path"

  # 中文路径是符号链接（如有人手工 ln -s 过英文目录）: 只收走链接，复制会变成自拷贝
  if [ -L "$cn_path" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$cn_path" "$BACKUP_DIR/$cn_name"
    echo "  $cn_name 是符号链接，已收入备份，未复制内容"
    return 0
  fi

  if [ ! -d "$cn_path" ]; then
    return 0
  fi

  # 复制失败不静默: 原件仍完整留在备份目录，但要让用户看到
  if ! cp -a "$cn_path/." "$en_path/"; then
    echo "警告: $cn_name 有内容未复制成功（原件完整保留在备份目录，可手工补齐）" >&2
  fi
  mkdir -p "$BACKUP_DIR"
  mv "$cn_path" "$BACKUP_DIR/$cn_name"
  echo "  $cn_name → $en_name 完成"
}

echo "==> 创建英文目录并迁移中文目录内容"

for pair in "${DIR_PAIRS[@]}"; do
  IFS='|' read -r cn_name en_name _xdg_key <<<"$pair"
  migrate_dir "$cn_name" "$en_name"
done

echo "==> 写入 XDG 用户目录配置"

cat >"$HOME/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF

# 锁定英文 locale，防止桌面环境下次登录按系统语言把目录名改回中文
echo "en_US" >"$HOME/.config/user-dirs.locale"

echo "==> 应用 xdg-user-dirs 配置"

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  for pair in "${DIR_PAIRS[@]}"; do
    IFS='|' read -r _cn_name en_name xdg_key <<<"$pair"
    xdg-user-dirs-update --set "$xdg_key" "$HOME/$en_name"
  done
else
  echo "警告: xdg-user-dirs-update 命令不存在，已手动写入配置文件，注销重登后生效"
fi

echo "==> 当前配置:"
cat "$HOME/.config/user-dirs.dirs"

echo
if [ -d "$BACKUP_DIR" ]; then
  echo "完成。中文目录原始副本已移动到:"
  echo "$BACKUP_DIR"
  echo "确认英文目录内容无缺后，可自行删除该备份目录。"
else
  echo "完成。未发现中文目录，仅写入了 XDG 配置，未产生备份。"
fi
echo
echo "建议注销重新登录（或 reboot）使文件管理器与应用生效。"
