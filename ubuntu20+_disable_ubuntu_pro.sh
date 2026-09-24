cat >/root/disable-ubuntu-pro.sh <<'EOF'
#!/usr/bin/env bash
set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] 请使用 root 执行"
    exit 1
fi

echo "============================================================"
echo " Disable Ubuntu Pro / ESM background checks"
echo " Ubuntu normal APT update mechanism will NOT be disabled"
echo "============================================================"

echo
echo "[1/8] Detach Ubuntu Pro subscription if attached..."

if command -v pro >/dev/null 2>&1; then
    pro detach --assume-yes >/dev/null 2>&1 || true

    # 官方支持的 APT News 关闭方式
    pro config set apt_news=false >/dev/null 2>&1 || true
else
    echo "[INFO] pro command not found, skip detach."
fi


echo
echo "[2/8] Disable and mask Ubuntu Pro systemd units..."

PRO_UNITS=(
    ua-timer.timer
    ua-timer.service
    apt-news.service
    esm-cache.service
    ubuntu-advantage.service
    ua-reboot-cmds.service
)

for unit in "${PRO_UNITS[@]}"; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        echo "[DISABLE] $unit"
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    fi
done


echo
echo "[3/8] Disable Ubuntu Pro APT hooks..."

ESM_HOOK="/etc/apt/apt.conf.d/20apt-esm-hook.conf"
ESM_HOOK_DIVERT="/etc/apt/apt.conf.d/20apt-esm-hook.conf.disabled-by-admin"

if [ -e "$ESM_HOOK" ] && [ ! -L "$ESM_HOOK" ]; then
    if ! dpkg-divert --list "$ESM_HOOK" 2>/dev/null | grep -q .; then
        dpkg-divert \
            --local \
            --rename \
            --add \
            --divert "$ESM_HOOK_DIVERT" \
            "$ESM_HOOK"
    fi
fi

# 确保 apt 不再加载该 hook
rm -f "$ESM_HOOK"
touch "$ESM_HOOK"
chmod 0644 "$ESM_HOOK"


echo
echo "[4/8] Disable ESM repositories..."

# Ubuntu Pro 可能生成 .list 或 .sources
for f in \
    /etc/apt/sources.list.d/ubuntu-esm-*.list \
    /etc/apt/sources.list.d/ubuntu-esm-*.sources \
    /etc/apt/sources.list.d/*esm*.list \
    /etc/apt/sources.list.d/*esm*.sources
do
    [ -e "$f" ] || continue

    echo "[DISABLE SOURCE] $f"

    case "$f" in
        *.list)
            sed -Ei \
                's|^[[:space:]]*deb([[:space:]])|# DISABLED-UBUNTU-PRO deb\1|' \
                "$f" || true
            ;;
        *.sources)
            if ! grep -q '^Enabled:[[:space:]]*no' "$f"; then
                printf '\nEnabled: no\n' >> "$f"
            fi
            ;;
    esac
done


echo
echo "[5/8] Disable ESM APT preference files..."

for f in \
    /etc/apt/preferences.d/ubuntu-pro-esm-apps \
    /etc/apt/preferences.d/ubuntu-pro-esm-infra
do
    if [ -e "$f" ]; then
        echo "[DISABLE PREF] $f"
        mv -f "$f" "${f}.disabled-by-admin"
    fi
done


echo
echo "[6/8] Disable Ubuntu Pro MOTD component..."

MOTD="/etc/update-motd.d/91-contract-ua-esm-status"

if [ -e "$MOTD" ]; then
    chmod -x "$MOTD" || true
fi

# 官方/客户端使用该标记隐藏 ESM MOTD
mkdir -p /var/lib/update-notifier
touch /var/lib/update-notifier/hide-esm-in-motd


echo
echo "[7/8] Remove cached Ubuntu Pro / APT News data..."

rm -rf \
    /var/lib/ubuntu-advantage/messages \
    /var/lib/ubuntu-advantage/apt-news* \
    /var/cache/ubuntu-advantage/apt-news* \
    2>/dev/null || true


echo
echo "[8/8] Reload systemd..."

systemctl daemon-reload || true
systemctl reset-failed \
    ua-timer.service \
    apt-news.service \
    esm-cache.service \
    ubuntu-advantage.service \
    ua-reboot-cmds.service \
    >/dev/null 2>&1 || true


echo
echo "============================================================"
echo " VERIFY"
echo "============================================================"

echo
echo "--- Ubuntu Pro timer ---"
systemctl is-enabled ua-timer.timer 2>/dev/null || true
systemctl is-active ua-timer.timer 2>/dev/null || true

echo
echo "--- Pro related units ---"
for unit in "${PRO_UNITS[@]}"; do
    printf '%-30s ' "$unit"
    systemctl is-enabled "$unit" 2>/dev/null || true
done

echo
echo "--- APT ESM hook ---"
ls -l \
    /etc/apt/apt.conf.d/20apt-esm-hook.conf \
    /etc/apt/apt.conf.d/20apt-esm-hook.conf.disabled-by-admin \
    2>/dev/null || true

echo
echo "--- ESM sources ---"
grep -RniE \
    'esm\.ubuntu\.com|ubuntu-pro|noble-(apps|infra)' \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d \
    2>/dev/null || true

echo
echo "--- Normal Ubuntu APT timers (should remain enabled) ---"
systemctl is-enabled apt-daily.timer 2>/dev/null || true
systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null || true

echo
echo "============================================================"
echo " Ubuntu Pro / ESM disabled."
echo
echo " Normal commands still work:"
echo "   apt update"
echo "   apt upgrade"
echo
echo " Normal Ubuntu apt-daily timers were NOT disabled."
echo "============================================================"
EOF

chmod +x /root/disable-ubuntu-pro.sh
/root/disable-ubuntu-pro.sh