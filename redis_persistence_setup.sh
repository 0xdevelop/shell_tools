#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================================
# 配置区 —— 要改的参数都在这一段，往下的执行逻辑不需要读。
#
# 使用模型（本生态拍板）：Redis 是带持久化的高速存储，不用 TTL 过期；
# 数据生命周期（灌入 / 消费 / 清理）全由程序显式管理，状态靠数据字段强控。
# 因此驱逐策略必须 noeviction —— 任何 LRU 驱逐都等于静默丢数据。
# ============================================================================

# ---- 持久化与内存目标值（key 与 redis.conf 指令同名；改值只动引号内右半段）----
REDIS_DIRECTIVES=(
  # RDB 快照：三档任一满足即落盘（1小时1改 / 5分钟100改 / 1分钟1万改）
  'save|save 3600 1 300 100 60 10000'
  # 落盘失败拒绝写入——宁可报错，不静默吞写（对齐「修改失败=保持未修改状态」）
  'stop-writes-on-bgsave-error|stop-writes-on-bgsave-error yes'
  'rdbcompression|rdbcompression yes'
  'rdbchecksum|rdbchecksum yes'
  'dbfilename|dbfilename dump.rdb'
  # AOF 追加日志：与 RDB 双开，重启恢复到最后一次完好状态
  'appendonly|appendonly yes'
  'appendfilename|appendfilename "appendonly.aof"'
  # everysec = 掉电最多丢 1 秒已确认写（业界均衡点；账本级零窗口改 always，吞吐降一个量级）
  'appendfsync|appendfsync everysec'
  # rewrite 期间照常 fsync：用尖峰延迟换安全
  'no-appendfsync-on-rewrite|no-appendfsync-on-rewrite no'
  'auto-aof-rewrite-percentage|auto-aof-rewrite-percentage 100'
  'auto-aof-rewrite-min-size|auto-aof-rewrite-min-size 64mb'
  # 崩溃截尾的 AOF 自动加载到截断点 = 恢复最后一次完好状态
  'aof-load-truncated|aof-load-truncated yes'
  'aof-use-rdb-preamble|aof-use-rdb-preamble yes'
  # 驱逐策略：必须 noeviction。内存满 = 写报错（正确行为：拒写保数据），
  # 绝不允许 Redis 自己挑 key 删——那会击穿「精准 / 唯一 / 只有显式处理完才删」。
  'maxmemory-policy|maxmemory-policy noeviction'
)

# 仅 Redis >= 7 生效的指令（multipart AOF 目录）
REDIS_DIRECTIVES_V7=(
  'appenddirname|appenddirname "appendonlydir"'
)

# maxmemory：空 = 不改现有配置（保持机器现状）；要设就填如 '8gb'。
# 注意 noeviction 下内存满表现为业务写报错——设了上限就必须配容量告警。
REDIS_MAXMEMORY=''

# ACL 命名用户的权限规则（启用 ACL 时套在用户名与密码 hash 之后）。
# 默认全量权限；生产建议收窄危险命令，示例：
#   ACL_USER_RULES='~* &* +@all -flushall -flushdb -debug -shutdown'
ACL_USER_RULES='~* &* +@all'

# 密码最短长度（短于此值会二次确认）
ACL_MIN_PASSWORD_LENGTH=16

# 运行时开启 AOF 后等待 rewrite 完成的超时（秒）；超时报错退出，不无限等
AOF_WAIT_TIMEOUT_SECONDS=300

# 支持的 Redis 主版本下限（低于它直接拒绝）
REDIS_MIN_MAJOR=7

# ============================================================================
# 执行逻辑 —— 以下不需要为改参数而阅读
# ============================================================================

info()  { printf '[INFO]  %s\n' "$*"; }
ok()    { printf '[OK]    %s\n' "$*"; }
add()   { printf '[ADD]   %s\n' "$*"; }
update(){ printf '[UPDATE] %s\n' "$*"; }
warn()  { printf '[WARN]  %s\n' "$*" >&2; }
die()   { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 执行。"

for cmd in awk grep cp cmp date diff mv sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || die "缺少命令: $cmd"
done
command -v redis-server >/dev/null 2>&1 || die "找不到 redis-server"

# ---------- Redis 版本识别 ----------
VERSION_RAW="$(redis-server --version 2>&1 || true)"
if [[ "$VERSION_RAW" =~ v=([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  REDIS_MAJOR="${BASH_REMATCH[1]}"
  REDIS_MINOR="${BASH_REMATCH[2]}"
  REDIS_PATCH="${BASH_REMATCH[3]}"
else
  die "无法解析 Redis 版本: $VERSION_RAW"
fi

if (( REDIS_MAJOR < REDIS_MIN_MAJOR )); then
  die "当前脚本面向 Redis >= ${REDIS_MIN_MAJOR}；检测到 Redis ${REDIS_MAJOR}.${REDIS_MINOR}.${REDIS_PATCH}。"
elif (( REDIS_MAJOR <= 8 )); then
  ok "检测到 Redis ${REDIS_MAJOR}.${REDIS_MINOR}.${REDIS_PATCH}，按 Redis 7/8 配置处理。"
else
  warn "检测到 Redis ${REDIS_MAJOR}.${REDIS_MINOR}.${REDIS_PATCH}，高于已明确适配的 7/8；将按 >=7 兼容逻辑处理。"
fi

# ---------- redis.conf 定位 ----------
CONF="${1:-}"
if [[ -z "$CONF" ]]; then
  for candidate in /etc/redis/redis.conf /etc/redis.conf /usr/local/etc/redis.conf; do
    if [[ -f "$candidate" ]]; then
      CONF="$candidate"
      break
    fi
  done
fi

[[ -n "$CONF" ]] || die "未自动找到 redis.conf。用法: $0 /path/to/redis.conf"
[[ -f "$CONF" ]] || die "配置文件不存在: $CONF"
[[ -r "$CONF" && -w "$CONF" ]] || die "配置文件不可读写: $CONF"
CONF="$(readlink -f "$CONF")"
info "Redis 配置文件: $CONF"

# ---------- 原配置硬备份：失败则绝不修改 ----------
UTC_TS="$(date -u '+%Y%m%d_%H%M%S')"
CONF_BACKUP="${CONF}_backup_${UTC_TS}_utc"
if [[ -e "$CONF_BACKUP" ]]; then
  CONF_BACKUP="${CONF_BACKUP}_$$"
  warn "同秒备份文件已存在，使用防冲突文件名: $CONF_BACKUP"
fi

cp -a -- "$CONF" "$CONF_BACKUP" || die "redis.conf 备份失败，已中止；原配置未修改。"
cmp -s -- "$CONF" "$CONF_BACKUP" || die "redis.conf 备份校验失败，已中止；原配置未修改。"
(sync -f "$CONF_BACKUP" 2>/dev/null || true)
ok "原配置备份完成并通过 cmp 校验: $CONF_BACKUP"

WORK="${CONF}.redis-setup.$$"
ACL_WORK=""
ACL_PATH=""
ACL_BACKUP=""
ACL_CREATED_NEW=0
cleanup() {
  [[ -n "${WORK:-}" && -e "${WORK:-}" ]] && rm -f -- "$WORK"
  [[ -n "${ACL_WORK:-}" && -e "${ACL_WORK:-}" && "${ACL_WORK:-}" != "${WORK:-}" ]] && rm -f -- "$ACL_WORK"
}
trap cleanup EXIT
cp -a -- "$CONF" "$WORK" || die "创建工作副本失败。"

count_active_key() {
  local file="$1" key="$2"
  awk -v k="$key" '
    {
      s=$0
      sub(/^[[:space:]]*/, "", s)
      if (s == "" || s ~ /^#/) next
      split(s, a, /[[:space:]]+/)
      if (a[1] == k) c++
    }
    END { print c+0 }
  ' "$file"
}

count_commented_key() {
  local file="$1" key="$2"
  awk -v k="$key" '
    {
      s=$0
      sub(/^[[:space:]]*/, "", s)
      if (s !~ /^#/) next
      sub(/^#[[:space:]]*/, "", s)
      split(s, a, /[[:space:]]+/)
      if (a[1] == k) c++
    }
    END { print c+0 }
  ' "$file"
}

first_active_line() {
  local file="$1" key="$2"
  awk -v k="$key" '
    {
      s=$0
      sub(/^[[:space:]]*/, "", s)
      if (s == "" || s ~ /^#/) next
      split(s, a, /[[:space:]]+/)
      if (a[1] == k) { print s; exit }
    }
  ' "$file"
}

rewrite_directive() {
  local file="$1" key="$2" replacement="$3" tmp="${file}.rewrite.$$"
  awk -v k="$key" -v repl="$replacement" '
    function active_key(raw, key, s, a) {
      s=raw
      sub(/^[[:space:]]*/, "", s)
      if (s == "" || s ~ /^#/) return 0
      split(s, a, /[[:space:]]+/)
      return a[1] == key
    }
    {
      if (active_key($0, k)) {
        if (!done) {
          print repl
          done=1
        }
        next
      }
      print
    }
    END {
      if (!done) print repl
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

set_directive() {
  local file="$1" key="$2" desired="$3"
  local active commented current
  active="$(count_active_key "$file" "$key")"
  commented="$(count_commented_key "$file" "$key")"
  current="$(first_active_line "$file" "$key" || true)"

  if [[ "$active" -eq 1 && "$current" == "$desired" ]]; then
    ok "$key 已是目标值: $desired"
    return 0
  fi

  if [[ "$active" -gt 0 ]]; then
    if [[ "$active" -gt 1 ]]; then
      warn "$key 检测到 ${active} 条生效配置；将合并为唯一一条，避免重复配置。"
    fi
    update "$key: ${current:-<unknown>}  ->  $desired"
  elif [[ "$commented" -gt 0 ]]; then
    add "$key: 没有生效字段，但发现 ${commented} 条注释模板；新增生效配置: $desired"
  else
    warn "$key: 配置文件中完全不存在该字段。"
    add "$key: 新增: $desired"
  fi

  rewrite_directive "$file" "$key" "$desired" || die "修改字段 $key 失败。"
}

comment_out_directive() {
  local file="$1" key="$2" active tmp="${file}.rewrite.$$"
  active="$(count_active_key "$file" "$key")"
  if [[ "$active" -eq 0 ]]; then
    info "$key: 没有生效配置，无需处理。"
    return 0
  fi

  warn "$key: 检测到 ${active} 条生效配置；启用命名 ACL 用户时将禁用它，避免与 default 用户密码语义混用。"
  awk -v k="$key" '
    function active_key(raw, key, s, a) {
      s=raw
      sub(/^[[:space:]]*/, "", s)
      if (s == "" || s ~ /^#/) return 0
      split(s, a, /[[:space:]]+/)
      return a[1] == key
    }
    {
      if (active_key($0, k)) print "# disabled-by-redis-setup: " $0
      else print
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; die "禁用 $key 失败。"; }
  cat "$tmp" > "$file"
  rm -f "$tmp"
  update "$key 已注释禁用。"
}

apply_directive_list() {
  local entry key desired
  for entry in "$@"; do
    key="${entry%%|*}"
    desired="${entry#*|}"
    set_directive "$WORK" "$key" "$desired"
  done
}

# ---------- 按配置区应用持久化与内存目标值 ----------
info "开始按配置区目标值写入（RDB + AOF + 驱逐策略）。"
apply_directive_list "${REDIS_DIRECTIVES[@]}"

if (( REDIS_MAJOR >= 7 )); then
  apply_directive_list "${REDIS_DIRECTIVES_V7[@]}"
else
  warn "Redis <7 不使用 multipart AOF appenddirname；已跳过。"
fi

if [[ -n "$REDIS_MAXMEMORY" ]]; then
  set_directive "$WORK" maxmemory "maxmemory ${REDIS_MAXMEMORY}"
  warn "已设 maxmemory ${REDIS_MAXMEMORY}：noeviction 下内存满表现为业务写报错，务必配容量告警。"
else
  info "配置区 REDIS_MAXMEMORY 为空：不改动现有 maxmemory 配置。"
fi

if [[ "$(count_active_key "$WORK" dir)" -gt 0 ]]; then
  info "保留现有数据目录配置: $(first_active_line "$WORK" dir)"
else
  warn "redis.conf 中没有生效的 dir 字段；脚本不会擅自改变数据目录。请确认 Redis 当前工作目录符合你的预期。"
fi

# ---------- 环境体检（只警告，不改值）----------
BIND_LINE="$(first_active_line "$WORK" bind || true)"
PROTECTED_LINE="$(first_active_line "$WORK" protected-mode || true)"
REPLICAOF_LINE="$(first_active_line "$WORK" replicaof || true)"
[[ -z "$REPLICAOF_LINE" ]] && REPLICAOF_LINE="$(first_active_line "$WORK" slaveof || true)"

if [[ -z "$BIND_LINE" ]] || grep -qE '(^|[[:space:]])0\.0\.0\.0([[:space:]]|$)' <<< "${BIND_LINE:-}"; then
  warn "bind 现状: ${BIND_LINE:-<未配置，默认全接口>}——实例对所有网卡开放，公网机器必须有防火墙 / 安全组收口。"
fi
if [[ "$PROTECTED_LINE" == "protected-mode no" ]]; then
  warn "protected-mode 为 no：无认证时任意来源可连。确认 ACL / requirepass 与网络收口已到位。"
fi
if [[ -n "$REPLICAOF_LINE" ]]; then
  warn "检测到副本配置（${REPLICAOF_LINE}）：若本次启用 ACL 并关闭 default 用户，主从认证（masterauth/masteruser）需要同步调整，否则复制会断。"
fi

# ---------- 可选 ACL 用户名 + 密码 ----------
printf '\n'
read -r -p '是否启用 ACL 用户名 + 密码登录，并关闭 default 用户？ [y/N]: ' ENABLE_ACL
ENABLE_ACL="${ENABLE_ACL:-N}"
ACL_ENABLED=0
ACL_USERNAME=""

if [[ "$ENABLE_ACL" =~ ^[Yy]$ ]]; then
  ACL_ENABLED=1

  while :; do
    read -r -p '请输入 ACL 用户名（不能是 default，允许字母/数字/._-）: ' ACL_USERNAME
    if [[ "$ACL_USERNAME" == "default" ]]; then
      warn "用户名不能使用 default；脚本需要关闭 default 用户来强制用户名认证。"
      continue
    fi
    if [[ "$ACL_USERNAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
      break
    fi
    warn "用户名格式不合法。"
  done

  while :; do
    read -r -s -p "请输入用户 ${ACL_USERNAME} 的密码: " ACL_PASSWORD
    printf '\n'
    read -r -s -p '请再次输入密码: ' ACL_PASSWORD_2
    printf '\n'
    if [[ "$ACL_PASSWORD" != "$ACL_PASSWORD_2" ]]; then
      warn "两次密码不一致，请重新输入。"
      continue
    fi
    if [[ -z "$ACL_PASSWORD" ]]; then
      warn "密码不能为空。"
      continue
    fi
    if (( ${#ACL_PASSWORD} < ACL_MIN_PASSWORD_LENGTH )); then
      warn "密码少于 ${ACL_MIN_PASSWORD_LENGTH} 个字符。"
      read -r -p '仍然继续使用这个密码？ [y/N]: ' SHORT_OK
      [[ "${SHORT_OK:-N}" =~ ^[Yy]$ ]] || continue
    fi
    break
  done

  ACL_HASH="$(printf '%s' "$ACL_PASSWORD" | sha256sum | awk '{print $1}')"
  unset ACL_PASSWORD ACL_PASSWORD_2
  [[ "$ACL_HASH" =~ ^[0-9a-f]{64}$ ]] || die "密码 SHA-256 计算失败。"
  ok "密码已转换为 SHA-256 ACL hash；不会把明文密码写入配置文件。"

  # requirepass 是 default 用户的兼容密码机制；命名 ACL 模式下禁用。
  comment_out_directive "$WORK" requirepass

  # redis.conf 与外部 aclfile 两种用户定义方式互斥。
  ACLFILE_LINE="$(first_active_line "$WORK" aclfile || true)"
  if [[ -n "$ACLFILE_LINE" ]]; then
    ACL_PATH="${ACLFILE_LINE#aclfile}"
    ACL_PATH="${ACL_PATH#${ACL_PATH%%[![:space:]]*}}"
    ACL_PATH="${ACL_PATH%${ACL_PATH##*[![:space:]]}}"
    if [[ "$ACL_PATH" == \"*\" && "$ACL_PATH" == *\" ]]; then
      ACL_PATH="${ACL_PATH:1:${#ACL_PATH}-2}"
    elif [[ "$ACL_PATH" == \'*\' && "$ACL_PATH" == *\' ]]; then
      ACL_PATH="${ACL_PATH:1:${#ACL_PATH}-2}"
    fi

    [[ "$ACL_PATH" = /* ]] || die "检测到相对路径 aclfile: $ACL_PATH。为避免错误解析路径，脚本拒绝猜测；请改为绝对路径后重试。"
    info "检测到外部 ACL 文件: $ACL_PATH"

    if [[ "$(count_active_key "$WORK" user)" -gt 0 ]]; then
      die "redis.conf 同时存在生效的 user 指令和 aclfile。Redis 不允许两种用户定义方式混用；请先整理现有 ACL 配置。"
    fi

    if [[ -e "$ACL_PATH" ]]; then
      ACL_BACKUP="${ACL_PATH}_backup_${UTC_TS}_utc"
      if [[ -e "$ACL_BACKUP" ]]; then
        ACL_BACKUP="${ACL_BACKUP}_$$"
        warn "ACL 同秒备份文件已存在，使用防冲突文件名: $ACL_BACKUP"
      fi
      cp -a -- "$ACL_PATH" "$ACL_BACKUP" || die "ACL 文件备份失败；未应用任何修改。"
      cmp -s -- "$ACL_PATH" "$ACL_BACKUP" || die "ACL 文件备份校验失败；未应用任何修改。"
      (sync -f "$ACL_BACKUP" 2>/dev/null || true)
      ok "ACL 原文件备份完成并通过 cmp 校验: $ACL_BACKUP"
      ACL_WORK="${ACL_PATH}.redis-setup.$$"
      cp -a -- "$ACL_PATH" "$ACL_WORK" || die "创建 ACL 工作副本失败。"
    else
      warn "aclfile 指向的文件当前不存在，将创建新文件: $ACL_PATH"
      ACL_CREATED_NEW=1
      ACL_WORK="${ACL_PATH}.redis-setup.$$"
      : > "$ACL_WORK"
      chmod 600 "$ACL_WORK"
    fi
  else
    ACL_WORK="$WORK"
  fi

  count_acl_user() {
    local file="$1" user="$2"
    awk -v u="$user" '
      {
        s=$0
        sub(/^[[:space:]]*/, "", s)
        if (s == "" || s ~ /^#/) next
        split(s, a, /[[:space:]]+/)
        if (a[1] == "user" && a[2] == u) c++
      }
      END { print c+0 }
    ' "$file"
  }

  first_acl_user_line() {
    local file="$1" user="$2"
    awk -v u="$user" '
      {
        s=$0
        sub(/^[[:space:]]*/, "", s)
        if (s == "" || s ~ /^#/) next
        split(s, a, /[[:space:]]+/)
        if (a[1] == "user" && a[2] == u) { print s; exit }
      }
    ' "$file"
  }

  set_acl_user() {
    local file="$1" user="$2" desired="$3" count current tmp="${file}.rewrite.$$"
    count="$(count_acl_user "$file" "$user")"
    current="$(first_acl_user_line "$file" "$user" || true)"

    if [[ "$count" -eq 1 && "$current" == "$desired" ]]; then
      ok "ACL 用户 $user 已是目标配置。"
      return 0
    elif [[ "$count" -gt 0 ]]; then
      [[ "$count" -gt 1 ]] && warn "ACL 用户 $user 出现 ${count} 条重复定义；将合并为一条。"
      update "ACL 用户 $user: ${current:-<unknown>} -> $desired"
    else
      add "ACL 用户 $user 不存在；新增。"
    fi

    awk -v u="$user" -v repl="$desired" '
      function is_user(raw, name, s, a) {
        s=raw
        sub(/^[[:space:]]*/, "", s)
        if (s == "" || s ~ /^#/) return 0
        split(s, a, /[[:space:]]+/)
        return a[1] == "user" && a[2] == name
      }
      {
        if (is_user($0, u)) {
          if (!done) {
            print repl
            done=1
          }
          next
        }
        print
      }
      END {
        if (!done) print repl
      }
    ' "$file" > "$tmp" || { rm -f "$tmp"; die "修改 ACL 用户 $user 失败。"; }
    cat "$tmp" > "$file"
    rm -f "$tmp"
  }

  # reset 先清空旧规则；再明确关闭 default / 开启命名用户。
  set_acl_user "$ACL_WORK" default      'user default reset off'
  set_acl_user "$ACL_WORK" "$ACL_USERNAME" "user ${ACL_USERNAME} reset on #${ACL_HASH} ${ACL_USER_RULES}"

  if [[ "$(count_active_key "$WORK" include)" -gt 0 ]]; then
    warn "redis.conf 存在 include 指令。脚本不会递归修改 include 文件；请确认 include 中没有重复定义 default 或 ${ACL_USERNAME} 用户。"
  fi
fi

# ---------- 展示 diff，最后确认 ----------
printf '\n===== redis.conf 变更预览 =====\n'
diff -u --label "${CONF} (current)" --label "${CONF} (new)" "$CONF" "$WORK" || true

if [[ "$ACL_ENABLED" -eq 1 && -n "$ACL_PATH" ]]; then
  printf '\n===== ACL 文件变更预览 =====\n'
  if [[ -e "$ACL_PATH" ]]; then
    diff -u --label "${ACL_PATH} (current)" --label "${ACL_PATH} (new)" "$ACL_PATH" "$ACL_WORK" || true
  else
    diff -u --label '/dev/null' --label "${ACL_PATH} (new)" /dev/null "$ACL_WORK" || true
  fi
fi

printf '\n'
read -r -p '确认写入以上配置？ [y/N]: ' APPLY
if [[ ! "${APPLY:-N}" =~ ^[Yy]$ ]]; then
  warn "用户取消。原 redis.conf 未修改；备份文件保留: $CONF_BACKUP"
  exit 0
fi

# ---------- 原子替换并校验 ----------
NEW_CONF_SHA="$(sha256sum "$WORK" | awk '{print $1}')"

if [[ "$ACL_ENABLED" -eq 1 && -n "$ACL_PATH" ]]; then
  mkdir -p "$(dirname "$ACL_PATH")"
  mv -f -- "$ACL_WORK" "$ACL_PATH" || die "写入 ACL 文件失败；redis.conf 尚未修改。"
  ACL_WORK=""
fi

if ! mv -f -- "$WORK" "$CONF"; then
  # 如果外部 ACL 已经写入，尽力回滚。
  if [[ "$ACL_ENABLED" -eq 1 && -n "$ACL_PATH" ]]; then
    if [[ -n "$ACL_BACKUP" && -f "$ACL_BACKUP" ]]; then
      cp -a -- "$ACL_BACKUP" "$ACL_PATH" || warn "ACL 自动回滚失败，请手工从 $ACL_BACKUP 恢复。"
    elif [[ "$ACL_CREATED_NEW" -eq 1 ]]; then
      rm -f -- "$ACL_PATH" || true
    fi
  fi
  die "写入 redis.conf 失败；已尽力回滚外部 ACL。"
fi
WORK=""

FINAL_CONF_SHA="$(sha256sum "$CONF" | awk '{print $1}')"
[[ "$NEW_CONF_SHA" == "$FINAL_CONF_SHA" ]] || die "redis.conf 写入后 SHA-256 校验不一致！请立即从备份恢复: $CONF_BACKUP"
ok "redis.conf 写入并校验成功。"

if [[ "$ACL_ENABLED" -eq 1 ]]; then
  ok "ACL 已配置：default 用户关闭；命名用户 ${ACL_USERNAME} 开启。"
  info "${ACL_USERNAME} 当前被授予规则: ${ACL_USER_RULES}"
fi

# ---------- 安全处理“当前正在运行”的 RDB -> AOF 切换 ----------
printf '\n'
if command -v redis-cli >/dev/null 2>&1; then
  PING_OUT="$(redis-cli --raw PING 2>&1 || true)"
  if [[ "$PING_OUT" == "PONG" ]]; then
    AOF_ENABLED_NOW="$(redis-cli --raw INFO persistence 2>/dev/null | awk -F: '/^aof_enabled:/{gsub(/\r/,"",$2); print $2; exit}')"
    if [[ "$AOF_ENABLED_NOW" == "0" ]]; then
      warn "当前运行中的 Redis 仍是 aof_enabled:0。已有数据时，不建议只改配置后直接重启。"
      read -r -p '是否现在同步对运行中的 Redis 开启 AOF（appendfsync everysec + appendonly yes）？ [Y/n]: ' LIVE_AOF
      LIVE_AOF="${LIVE_AOF:-Y}"
      if [[ "$LIVE_AOF" =~ ^[Yy]$ ]]; then
        redis-cli CONFIG SET appendfsync everysec >/dev/null || die "运行时设置 appendfsync everysec 失败。"
        redis-cli CONFIG SET appendonly yes >/dev/null || die "运行时开启 appendonly 失败。"
        ok "已向运行中的 Redis 提交 AOF 开启命令。"

        WAITED=0
        while :; do
          PERSISTENCE="$(redis-cli --raw INFO persistence 2>/dev/null || true)"
          AE="$(awk -F: '/^aof_enabled:/{gsub(/\r/,"",$2);print $2;exit}' <<< "$PERSISTENCE")"
          RIP="$(awk -F: '/^aof_rewrite_in_progress:/{gsub(/\r/,"",$2);print $2;exit}' <<< "$PERSISTENCE")"
          RS="$(awk -F: '/^aof_rewrite_scheduled:/{gsub(/\r/,"",$2);print $2;exit}' <<< "$PERSISTENCE")"
          ST="$(awk -F: '/^aof_last_bgrewrite_status:/{gsub(/\r/,"",$2);print $2;exit}' <<< "$PERSISTENCE")"
          printf '[INFO]  AOF state: enabled=%s rewrite_in_progress=%s scheduled=%s last_status=%s\n' "${AE:-?}" "${RIP:-?}" "${RS:-?}" "${ST:-?}"
          if [[ "$AE" == "1" && "$RIP" == "0" && "$RS" == "0" && "$ST" == "ok" ]]; then
            ok "运行中 Redis 的 AOF 初始化/重写状态已完成且正常。"
            break
          fi
          (( WAITED++ ))
          if (( WAITED >= AOF_WAIT_TIMEOUT_SECONDS )); then
            die "等待 AOF rewrite 完成超过 ${AOF_WAIT_TIMEOUT_SECONDS} 秒（last_status=${ST:-?}）。配置文件已写好，但运行中实例的 AOF 状态未收敛——排查后再决定是否重启，切勿在 aof 状态异常时直接重启。"
          fi
          sleep 1
        done
      else
        warn "已跳过运行时 AOF 开启。不要直接重启一个已有数据且 aof_enabled:0 的实例；请先手工安全切换 AOF。"
      fi
    elif [[ "$AOF_ENABLED_NOW" == "1" ]]; then
      ok "当前运行中的 Redis 已经是 aof_enabled:1。"
    else
      warn "无法识别当前运行 Redis 的 aof_enabled 状态。"
    fi
  else
    if grep -qi 'NOAUTH' <<< "$PING_OUT"; then
      warn "当前 Redis 已要求认证，脚本无法无凭据执行运行时 AOF 切换。配置文件已写好，但重启前请使用当前有效凭据执行 CONFIG SET appendfsync everysec / appendonly yes，并等待 AOF rewrite 完成。"
    else
      warn "本机 redis-cli PING 未得到 PONG（${PING_OUT:-无输出}）；跳过运行时 AOF 切换。"
    fi
  fi
else
  warn "找不到 redis-cli；跳过运行时 AOF 检查。"
fi

printf '\n===== 完成 =====\n'
ok "原配置备份: $CONF_BACKUP"
[[ -n "$ACL_BACKUP" ]] && ok "ACL 原文件备份: $ACL_BACKUP"
info "脚本不会自动 restart Redis。确认运行时 AOF 状态正常后，再由你决定是否重启服务。"
if [[ "$ACL_ENABLED" -eq 1 ]]; then
  info "重启/加载新 ACL 后，连接必须使用用户名 ${ACL_USERNAME} + 你刚才输入的密码。"
fi
