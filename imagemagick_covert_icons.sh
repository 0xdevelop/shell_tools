#!/bin/bash
set -eo pipefail

# =========================
# 基础配置
# =========================
SCRIPT_NAME=$(basename "$0")
INPUT=${1:-"Logo.png"}
OUT="icons"

# =========================
# 工具函数封装
# =========================
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    exit 1
}

check_imagemagick() {
    if ! command -v magick &> /dev/null; then
        info "未检测到 ImageMagick，是否安装？(Y/n)"
        read -r ans
        [[ "$ans" == "n" || "$ans" == "N" ]] && exit 0

        case "$OSTYPE" in
            darwin*)
                info "🍎 macOS 使用 brew 安装..."
                brew install imagemagick
                ;;
            linux-gnu*)
                info "🐧 Linux 使用 apt 安装..."
                sudo apt update && sudo apt install -y imagemagick
                ;;
            msys* | cygwin*)
                error "🪟 Windows GitBash 请手动安装：https://imagemagick.org/script/download.php#windows"
                ;;
            *)
                error "⚠️ 未知系统，請手动安装 imagemagick"
                ;;
        esac
    fi
    info "✅ ImageMagick 环境正常"
}

check_input_image() {
    [[ ! -f "$INPUT" ]] && error "图标文件不存在：$INPUT"
    SIZE=$(magick identify -format "%wx%h" "$INPUT")
    [[ "$SIZE" != "1024x1024" ]] && error "图片必须是 1024x1024，当前：$SIZE"
    info "✅ 输入文件校验完成：$INPUT"
}

create_output_dirs() {
    mkdir -p "$OUT"/{android,iphone,ipad,macos,watchos,tvos,windows,web,linux,flutter,miniapp,binary}
}

generate_android() {
    local d="$OUT/android"
    magick "$INPUT" -resize 48x48 "$d"/mipmap-mdpi.png
    magick "$INPUT" -resize 72x72 "$d"/mipmap-hdpi.png
    magick "$INPUT" -resize 96x96 "$d"/mipmap-xhdpi.png
    magick "$INPUT" -resize 144x144 "$d"/mipmap-xxhdpi.png
    magick "$INPUT" -resize 192x192 "$d"/mipmap-xxxhdpi.png
    magick "$INPUT" -resize 512x512 "$d"/play_store_512.png
}

generate_iphone() {
    local d="$OUT/iphone"
    magick "$INPUT" -resize 20x20 "$d"/Icon-20x20.png
    magick "$INPUT" -resize 29x29 "$d"/Icon-29x29.png
    magick "$INPUT" -resize 40x40 "$d"/Icon-40x40.png
    magick "$INPUT" -resize 60x60 "$d"/Icon-60x60.png
    magick "$INPUT" -resize 58x58 "$d"/Icon-29x29@2x.png
    magick "$INPUT" -resize 80x80 "$d"/Icon-40x40@2x.png
    magick "$INPUT" -resize 87x87 "$d"/Icon-29x29@3x.png
    magick "$INPUT" -resize 120x120 "$d"/Icon-40x40@3x.png
    magick "$INPUT" -resize 180x180 "$d"/Icon-60x60@3x.png
}

generate_ipad() {
    local d="$OUT/ipad"
    magick "$INPUT" -resize 20x20 "$d"/Icon-20x20-iPad.png
    magick "$INPUT" -resize 40x40 "$d"/Icon-40x40-iPad.png
    magick "$INPUT" -resize 76x76 "$d"/Icon-76x76-iPad.png
    magick "$INPUT" -resize 152x152 "$d"/Icon-76x76-iPad@2x.png
    magick "$INPUT" -resize 167x167 "$d"/Icon-83.5x83.5@2x.png
    magick "$INPUT" -resize 1024x1024 "$d"/AppStore.png
}

generate_macos() {
    local d="$OUT/macos"
    magick "$INPUT" -resize 16x16 "$d"/icon_16x16.png
    magick "$INPUT" -resize 32x32 "$d"/icon_32x32.png
    magick "$INPUT" -resize 128x128 "$d"/icon_128x128.png
    magick "$INPUT" -resize 256x256 "$d"/icon_256x256.png
    magick "$INPUT" -resize 512x512 "$d"/icon_512x512.png
    magick "$INPUT" -resize 1024x1024 "$d"/icon_1024x1024.png

    if [[ "$OSTYPE" == "darwin"* ]]; then
        mkdir -p "$d"/tmp.iconset
        magick "$INPUT" -resize 16x16 "$d"/tmp.iconset/icon_16x16.png
        magick "$INPUT" -resize 32x32 "$d"/tmp.iconset/icon_16x16@2x.png
        magick "$INPUT" -resize 32x32 "$d"/tmp.iconset/icon_32x32.png
        magick "$INPUT" -resize 64x64 "$d"/tmp.iconset/icon_32x32@2x.png
        magick "$INPUT" -resize 128x128 "$d"/tmp.iconset/icon_128x128.png
        magick "$INPUT" -resize 256x256 "$d"/tmp.iconset/icon_128x128@2x.png
        magick "$INPUT" -resize 256x256 "$d"/tmp.iconset/icon_256x256.png
        magick "$INPUT" -resize 512x512 "$d"/tmp.iconset/icon_256x256@2x.png
        magick "$INPUT" -resize 512x512 "$d"/tmp.iconset/icon_512x512.png
        magick "$INPUT" -resize 1024x1024 "$d"/tmp.iconset/icon_512x512@2x.png
        iconutil -c icns "$d"/tmp.iconset -o "$d"/AppIcon.icns
        rm -rf "$d"/tmp.iconset
    fi
}

generate_watchos() {
    local d="$OUT/watchos"
    magick "$INPUT" -resize 44x44 "$d"/Icon-44.png
    magick "$INPUT" -resize 50x50 "$d"/Icon-50.png
    magick "$INPUT" -resize 98x98 "$d"/Icon-98.png
    magick "$INPUT" -resize 108x108 "$d"/Icon-108.png
    magick "$INPUT" -resize 172x172 "$d"/Icon-172.png
    magick "$INPUT" -resize 196x196 "$d"/Icon-196.png
}

generate_tvos() {
    local d="$OUT/tvos"
    magick "$INPUT" -resize 128x128 "$d"/Icon-128.png
    magick "$INPUT" -resize 256x256 "$d"/Icon-256.png
    magick "$INPUT" -resize 512x512 "$d"/Icon-512.png
}

generate_windows() {
    local d="$OUT/windows"
    magick "$INPUT" -resize 256x256 -resize 128x128 -resize 64x64 -resize 48x48 -resize 32x32 -resize 16x16 -colors 256 "$d"/App.ico
}

generate_web() {
    local d="$OUT/web"
    magick "$INPUT" -resize 16x16 "$d"/favicon-16x16.png
    magick "$INPUT" -resize 32x32 "$d"/favicon-32x32.png
    magick "$INPUT" -resize 192x192 "$d"/icon-192.png
    magick "$INPUT" -resize 512x512 "$d"/icon-512.png
    magick "$INPUT" -resize 512x512 "$d"/icon-512.webp
    magick "$INPUT" -resize 16x16 -resize 32x32 -resize 48x48 "$d"/favicon.ico
}

generate_linux() {
    local d="$OUT/linux"
    magick "$INPUT" -resize 16x16 "$d"/icon16.png
    magick "$INPUT" -resize 32x32 "$d"/icon32.png
    magick "$INPUT" -resize 48x48 "$d"/icon48.png
    magick "$INPUT" -resize 64x64 "$d"/icon64.png
    magick "$INPUT" -resize 128x128 "$d"/icon128.png
    magick "$INPUT" -resize 256x256 "$d"/icon256.png
    magick "$INPUT" -resize 512x512 "$d"/icon512.png
}

generate_flutter() {
    local d="$OUT/flutter"
    magick "$INPUT" -resize 180x180 "$d"/ic_launcher_android.png
    magick "$INPUT" -resize 180x180 "$d"/ic_launcher_ios.png
    magick "$INPUT" -resize 512x512 "$d"/icon_512.png
}

generate_miniapp() {
    local d="$OUT/miniapp"
    magick "$INPUT" -resize 120x120 "$d"/mini_app_120.png
    magick "$INPUT" -resize 144x144 "$d"/mini_app_144.png
    magick "$INPUT" -resize 200x200 "$d"/mini_app_200.png
}

generate_binary() {
    local d="$OUT/binary"
    magick "$INPUT" "$d"/icon.bmp
    magick "$INPUT" "$d"/icon.tiff
    magick "$INPUT" "$d"/icon.raw
}

write_bridge_report() {
    if [[ -f "BRIDGE.md" ]]; then
        cat > BRIDGE.md << EOF
## 回报
✅ 全平台图标生成完成
源文件：$INPUT
尺寸校验：1024x1024 ✅
输出目录：icons/
覆盖平台：Android / iPhone / iPad / macOS / WatchOS / TVOS / Windows / Web / Linux / Flutter / 小程序
EOF
        info "✅ 已自动更新 BRIDGE.md"
    fi
}

# =========================
# 主执行流程
# =========================
main() {
    info "🚀 启动全平台图标生成工具"
    check_imagemagick
    check_input_image
    create_output_dirs

    generate_android
    generate_iphone
    generate_ipad
    generate_macos
    generate_watchos
    generate_tvos
    generate_windows
    generate_web
    generate_linux
    generate_flutter
    generate_miniapp
    generate_binary

    write_bridge_report
    info "🎉 所有平台图标生成完成！输出目录：$OUT"
}

# 运行
main && wait && rm -rf $SCRIPT_NAME && exit 0
