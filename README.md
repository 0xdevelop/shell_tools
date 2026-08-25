<!-- TOC -->

- [shell\_tools](#shell_tools)
- [1. 系统初始化与账号](#1-系统初始化与账号)
  - [1.1. setup\_ubuntu20.sh —— Ubuntu 20+ 基线初始化](#11-setup_ubuntu20sh--ubuntu-20-基线初始化)
  - [1.2. ubuntu20+adduser\_to\_login.sh —— 添加可登录用户](#12-ubuntu20adduser_to_loginsh--添加可登录用户)
  - [1.3. create\_restricted\_user.sh —— 添加受限用户](#13-create_restricted_usersh--添加受限用户)
  - [1.4. optimize\_network.sh —— 系统网络调优（51200 并发）](#14-optimize_networksh--系统网络调优51200-并发)
  - [1.5. ubuntu\_cn\_dir\_to\_en\_dir.sh —— 中文用户目录改英文](#15-ubuntu_cn_dir_to_en_dirsh--中文用户目录改英文)
- [2. 软件安装](#2-软件安装)
  - [2.1. install\_softs.sh —— 常用软件一键聚合安装](#21-install_softssh--常用软件一键聚合安装)
  - [2.2. install\_docker.sh](#22-install_dockersh)
  - [2.3. install\_redis.sh](#23-install_redissh)
  - [2.4. install\_nginx.sh](#24-install_nginxsh)
  - [2.5. install\_nacos.sh](#25-install_nacossh)
- [3. Redis 生产配置](#3-redis-生产配置)
  - [3.1. redis\_persistence\_setup.sh —— 持久化与认证配置器](#31-redis_persistence_setupsh--持久化与认证配置器)
- [4. Nginx 调优](#4-nginx-调优)
  - [4.1. nginx\_optimize.sh](#41-nginx_optimizesh)
- [5. SSL/TLS 证书](#5-ssltls-证书)
  - [5.1. auto\_ssl.sh —— 证书自动签发与续期](#51-auto_sslsh--证书自动签发与续期)
  - [5.2. check\_cert.sh —— 证书到期检查](#52-check_certsh--证书到期检查)
- [6. GitHub 仓库版本工具](#6-github-仓库版本工具)
  - [6.1. github\_repo\_version\_scan.sh / .ps1 —— 公开仓](#61-github_repo_version_scansh--ps1--公开仓)
  - [6.2. private\_repo\_tools.sh —— 私有仓（需 PAT）](#62-private_repo_toolssh--私有仓需-pat)
- [7. 图像工具](#7-图像工具)
  - [7.1. imagemagick\_covert\_icons.sh —— Logo 转多尺寸图标](#71-imagemagick_covert_iconssh--logo-转多尺寸图标)

<!-- /TOC -->

# shell_tools

Linux 服务器初始化 / 软件安装 / 生产配置 / 证书 / 仓库版本 的 shell 工具集。
所有脚本一键调用形态统一（**分支段是 `main`**，本仓默认分支）：

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/<脚本名> && chmod a+x ./<脚本名> && ./<脚本名> [参数]
```

同族脚本的分工：**安装（第 2 节）管「装上」，配置 / 调优（第 3、4 节）管「配好」**——
如 `install_redis.sh` 负责从官方源装 Redis，`redis_persistence_setup.sh` 负责把装好的实例
配成生产形态，二者是上下游不是重复。

# 1. 系统初始化与账号

## 1.1. setup_ubuntu20.sh —— Ubuntu 20+ 基线初始化

装基础工具链（unzip / wget / logrotate / 证书链等）并串起网络调优，新机开荒第一步。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/setup_ubuntu20.sh && chmod a+x ./setup_ubuntu20.sh && ./setup_ubuntu20.sh
```

## 1.2. ubuntu20+adduser_to_login.sh —— 添加可登录用户

创建用户并写入 SSH 公钥。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/ubuntu20+adduser_to_login.sh && chmod a+x ./ubuntu20+adduser_to_login.sh && ./ubuntu20+adduser_to_login.sh <username> "<ssh_public_key>"
```

## 1.3. create_restricted_user.sh —— 添加受限用户

创建权限受限的用户（与 1.2 的区别：受限 shell / 最小权限形态）。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/create_restricted_user.sh && chmod a+x ./create_restricted_user.sh && ./create_restricted_user.sh <username> "<ssh_public_key>"
```

## 1.4. optimize_network.sh —— 系统网络调优（51200 并发）

文件句柄上限 + 内核网络参数，优化至承载 51200 并发。ipv6 因软件兼容性考虑默认关闭。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/optimize_network.sh && chmod a+x ./optimize_network.sh && ./optimize_network.sh
```

## 1.5. ubuntu_cn_dir_to_en_dir.sh —— 中文用户目录改英文

把中文 Ubuntu 桌面的 XDG 用户目录（桌面/下载/文档等）迁移为英文（Desktop/Downloads/Documents 等），
终端里 cd 不用再敲中文。内容先复制进英文目录，中文目录整体移入
`~/.xdg-user-dirs-cn-backup-<时间戳>/` 备份——不删任何数据，重复执行安全。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/ubuntu_cn_dir_to_en_dir.sh && chmod a+x ./ubuntu_cn_dir_to_en_dir.sh && ./ubuntu_cn_dir_to_en_dir.sh
```

- 以目标桌面用户身份直接执行，**不要 sudo**（sudo 后 HOME 指向 /root，脚本会直接拒绝）。
- 默认交互确认后才动目录；无人值守加 `-y`。
- 同名文件以中文目录一侧为准合并进英文目录；原件始终完整留在备份目录。
- 执行完注销重登（或 reboot）生效；确认英文目录内容无缺后可自行删除备份目录。

# 2. 软件安装

## 2.1. install_softs.sh —— 常用软件一键聚合安装

聚合入口：内部依次拉起本仓的 `install_redis.sh` / `install_docker.sh` /
`install_nginx.sh` / `optimize_network.sh`。只想装单件用 2.2-2.5。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_softs.sh && chmod a+x ./install_softs.sh && ./install_softs.sh
```

## 2.2. install_docker.sh

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_docker.sh && chmod a+x ./install_docker.sh && ./install_docker.sh
```

## 2.3. install_redis.sh

从 Redis 官方 apt 源安装。装完的生产配置（持久化 / ACL）见第 3 节。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_redis.sh && chmod a+x ./install_redis.sh && ./install_redis.sh
```

## 2.4. install_nginx.sh

从 Nginx 官方源安装到 Ubuntu。装完的并发调优见 4.1。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_nginx.sh && chmod a+x ./install_nginx.sh && ./install_nginx.sh
```

## 2.5. install_nacos.sh

安装 Nacos（固定配置写死在脚本内，不提供环境变量覆盖——改配置直接改脚本头部常量段）。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/install_nacos.sh && chmod a+x ./install_nacos.sh && ./install_nacos.sh
```

# 3. Redis 生产配置

## 3.1. redis_persistence_setup.sh —— 持久化与认证配置器

生产机 Redis（7/8）配置器：开启 RDB + AOF 双持久化、驱逐策略钉死 `noeviction`
（适配「不用 TTL、数据生命周期由程序显式管理」的存储型用法——任何 LRU 驱逐都等于
静默丢数据）、可选启用 ACL 命名用户并关闭 default。与 2.3 的分工：先 `install_redis.sh`
装上，再用本脚本配成生产形态。

交互式：全部变更先 diff 预览、确认后才写入，不适合无人值守。需要 root。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/redis_persistence_setup.sh && chmod a+x ./redis_persistence_setup.sh && sudo ./redis_persistence_setup.sh
```

不带参数自动找 `/etc/redis/redis.conf` 等常见路径，也可显式指定：

```
sudo ./redis_persistence_setup.sh /path/to/redis.conf
```

改参数只动脚本**头部「配置区」**，执行段不需要读：

| 变量 | 含义 |
| --- | --- |
| `REDIS_DIRECTIVES` | 持久化与内存目标值数组，`key\|目标行` 一行一项、行行带注释；加新指令往数组添一行即可 |
| `REDIS_DIRECTIVES_V7` | 仅 Redis >=7 生效的指令（multipart AOF 目录） |
| `REDIS_MAXMEMORY` | 空 = 不改机器现状；填值（如 `8gb`）才写。noeviction 下内存满表现为写报错，设了上限必须配容量告警 |
| `ACL_USER_RULES` | ACL 用户权限，默认 `~* &* +@all`；生产建议收窄：`~* &* +@all -flushall -flushdb -debug -shutdown` |
| `ACL_MIN_PASSWORD_LENGTH` | 密码最短长度，短于此值二次确认 |
| `AOF_WAIT_TIMEOUT_SECONDS` | 运行时开启 AOF 后等待 rewrite 收敛的超时 |
| `REDIS_MIN_MAJOR` | 支持的最低主版本 |

`appendfsync` 默认 `everysec`（掉电最多丢 1 秒已确认写）；账本级零窗口改 `always`，
吞吐降一个量级。

行为边界：

- 原配置硬备份 + cmp 校验（备份失败绝不动原文件）；原子替换 + 写后 SHA-256 复核。
- 对运行中的实例安全执行 RDB→AOF 切换（`CONFIG SET` 后等 rewrite 完成、带超时）——
  避免「只改配置就重启 → 空 AOF 把存量数据清零」。
- ACL：命名用户 + SHA-256 密码 hash（明文不落盘）、关 default、禁 requirepass；
  兼容外部 aclfile 与 conf 内 user（互斥检查）。
- 环境体检只警告不改值：bind 全接口 / protected-mode off / 副本实例关 default 会断主从认证。
- **不自动重启 Redis**；不改 `dir`、不递归改 `include`、相对路径 aclfile 直接拒绝。

# 4. Nginx 调优

## 4.1. nginx_optimize.sh

改写 `nginx.conf` 的并发相关参数（worker 连接数等）。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/nginx_optimize.sh && chmod a+x ./nginx_optimize.sh && ./nginx_optimize.sh
```

# 5. SSL/TLS 证书

## 5.1. auto_ssl.sh —— 证书自动签发与续期

签发证书并配置定时续期。

```
# 交互式一键
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/auto_ssl.sh && chmod a+x ./auto_ssl.sh && ./auto_ssl.sh

# 显式传参
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/auto_ssl.sh && chmod a+x ./auto_ssl.sh && ./auto_ssl.sh -nginx_web_root /testberoot -domain www.test.com -email testtest@gmail.com
```

## 5.2. check_cert.sh —— 证书到期检查

检查指定证书文件的到期时间（与 5.1 分工：签发续期归 auto_ssl，巡检归本脚本）。

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/check_cert.sh && chmod a+x ./check_cert.sh && ./check_cert.sh /path/to/your/certificate.crt && rm -rf ./check_cert.sh
```

# 6. GitHub 仓库版本工具

公开仓走 6.1（无凭据），私有仓走 6.2（需 GitHub PAT）——同一族能力按仓可见性分两个脚本，不重复。

## 6.1. github_repo_version_scan.sh / .ps1 —— 公开仓

仅支持公开 GitHub 仓。四个子命令（`$..._REPO_URI` 形如 `github.com/user/repo`）：

监测两个同步库是否需要更新：

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/github_repo_version_scan.sh && chmod a+x ./github_repo_version_scan.sh && ./github_repo_version_scan.sh --check_need_update $CURRENT_REPO_URI $REMOTE_REPO_URI
```

获取指定库 latest 版本名：

```
./github_repo_version_scan.sh --get_latest_version $REMOTE_REPO_URI
```

获取指定库 latest 版本 upload_url：

```
./github_repo_version_scan.sh --get_latest_upload_url github.com/user/repo
```

检查 latest assets 中是否存在指定文件：

```
./github_repo_version_scan.sh --check_file_exist_from_repo_latest github.com/user/repo testfile.zip
```

Windows（PowerShell，常用于 GitHub Actions）：

```
Invoke-WebRequest -Uri https://raw.githubusercontent.com/0xdevelop/shell_tools/main/github_repo_version_scan.ps1 -OutFile github_repo_version_scan.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$file_exist = Check-FileExistFromRepoLatest -Repo "github.com/$env:GITHUB_REPOSITORY" -FileName "$env:over_file_name"
echo "file_exist=$file_exist" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
```

## 6.2. private_repo_tools.sh —— 私有仓（需 PAT）

下载脚本本体：

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/shell_tools/main/private_repo_tools.sh && chmod a+x ./private_repo_tools.sh
```

四个子命令（`${GITHUB_PAT}` 为访问令牌）：

```
# latest 版本名
./private_repo_tools.sh -get_latest_releases_name ${GITHUB_PAT} owner/repo

# 指定 release 的 upload_url
./private_repo_tools.sh -get_releases_upload_url ${GITHUB_PAT} owner/repo ${release_name}

# 两库版本对比是否需更新
./private_repo_tools.sh -check_repo_need_update ${GITHUB_PAT} ${owner}/${repo} ${remote_owner}/${remote_repo}

# 下载指定 release 的 assets（文件名或 all）
./private_repo_tools.sh -download_private_repo_asstes ${GITHUB_PAT} ${owner}/${repo} ${release_name} ${assets_file_name}|all ${save_dir}
```

# 7. 图像工具

## 7.1. imagemagick_covert_icons.sh —— Logo 转多尺寸图标

用 ImageMagick 把一张 Logo 批量转出多平台图标尺寸。

```
# 默认路径
wget --no-check-certificate --secure-protocol=TLSv1_2 https://raw.githubusercontent.com/0xdevelop/shell_tools/main/imagemagick_covert_icons.sh && chmod a+x ./imagemagick_covert_icons.sh && ./imagemagick_covert_icons.sh

# 自定义 Logo 路径
./imagemagick_covert_icons.sh ./my_logo.png
```
