<!-- TOC -->

- [1. Tip](#1-tip)
- [2. 关闭ipv6](#2-关闭ipv6)
- [3. use`optimize_network`51200 concurrent](#3-useoptimize_network51200-concurrent)
- [4. use`install_docker`](#4-useinstall_docker)
- [5. use`install_redis`](#5-useinstall_redis)
- [6. use`github_repo_version_scan`（仅仅支持Github）](#6-usegithub_repo_version_scan仅仅支持github)
    - [6.1. 自动监测两个同步库是否需要更新](#61-自动监测两个同步库是否需要更新)
    - [6.2. 获取指定库的latest版本名称](#62-获取指定库的latest版本名称)
        - [6.2.1. Simple:](#621-simple)
    - [6.3. 获取指定库的latest版本upload_url](#63-获取指定库的latest版本upload_url)
        - [6.3.1. Simple:](#631-simple)
    - [6.4. 检查latest版本assets中是否存在指定文件](#64-检查latest版本assets中是否存在指定文件)
        - [6.4.1. Simple--Linux:](#641-simple--linux)
        - [6.4.2. Simple--Windows](#642-simple--windows)
- [7. `Nginx` install to `Ubuntu`](#7-nginx-install-to-ubuntu)
- [8. `nginx ` network `optimize`](#8-nginx--network-optimize)
- [9. `Ubuntu-20.0.4 LTS` Setup](#9-ubuntu-2004-lts-setup)
- [10. `auto_ssl` usege](#10-auto_ssl-usege)
- [11. `private_repo_tools` Private Repo Tools](#11-private_repo_tools-private-repo-tools)
    - [11.1. Get Latest Version Name](#111-get-latest-version-name)
    - [11.2. Get Release UPLoadURL WIth ReleaseName](#112-get-release-uploadurl-with-releasename)
    - [11.3. checke version](#113-checke-version)
    - [11.4. Download Appoint Release Assets](#114-download-appoint-release-assets)
- [12. Checke ssl/tls cert express date](#12-checke-ssltls-cert-express-date)
- [Ubuntu20+ add user](#ubuntu20-add-user)
- [use`redis_persistence_setup` 生产 Redis 持久化与认证配置](#useredis_persistence_setup-生产-redis-持久化与认证配置)
- [use`imagemagick_covert_icons` Logo 转多尺寸图标](#useimagemagick_covert_icons-logo-转多尺寸图标)

<!-- /TOC -->

# 1. Tip
* 2. 仅支持`public` Gtihub Repo

# 2. 关闭ipv6
```
ipv6的现有软件兼容性考虑
```

# 3. use`optimize_network`51200 concurrent
* Optimized to carry 51200 concurrency(优化至承载51200并发)
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/optimize_network.sh && chmod a+x ./optimize_network.sh && ./optimize_network.sh
```

# 4. use`install_docker`
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/install_docker.sh && chmod a+x ./install_docker.sh && ./install_docker.sh
```

# 5. use`install_redis`
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/install_redis.sh && chmod a+x ./install_redis.sh && ./install_redis.sh
```

# 6. use`github_repo_version_scan`（仅仅支持Github）
## 6.1. 自动监测两个同步库是否需要更新
*   plase edit `$CURRENT_REPO_URI` `$REMOTE_REPO_URI`

```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/github_repo_version_scan.sh && chmod a+x ./github_repo_version_scan.sh && ./github_repo_version_scan.sh --check_need_update $CURRENT_REPO_URI $REMOTE_REPO_URI
```

## 6.2. 获取指定库的latest版本名称
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/github_repo_version_scan.sh && chmod a+x ./github_repo_version_scan.sh && ./github_repo_version_scan.sh --get_latest_version $REMOTE_REPO_URI
```
### 6.2.1. Simple:
*   simple: `$CURRENT_REPO_URI` = `github.com/currenttuser/current_repo`
*   simple: `$CURRENT_REPO_URI` = `github.com/remoteuser/remote_repo`
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/github_repo_version_scan.sh && chmod a+x ./github_repo_version_scan.sh && ./github_repo_version_scan.sh --check_need_update github.com/currenttuser/current_repo github.com/remoteuser/remote_repo
```

## 6.3. 获取指定库的latest版本upload_url
### 6.3.1. Simple:
*   simple: `$CURRENT_REPO_URI` = `github.com/currenttuser/current_repo`
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/github_repo_version_scan.sh && chmod a+x ./github_repo_version_scan.sh && ./github_repo_version_scan.sh --get_latest_upload_url github.com/currenttuser/current_repo
```

## 6.4. 检查latest版本assets中是否存在指定文件
### 6.4.1. Simple--Linux:
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/github_repo_version_scan.sh && chmod a+x ./github_repo_version_scan.sh && ./github_repo_version_scan.sh --check_file_exist_from_repo_latest github.com/currenttuser/current_repo testfile.zip
```
### 6.4.2. Simple--Windows
```
Invoke-WebRequest -Uri https://raw.githubusercontent.com/george012/gt_script/master/github_repo_version_scan.ps1 -OutFile github_repo_version_scan.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$file_exist = Check-FileExistFromRepoLatest -Repo "github.com/$env:GITHUB_REPOSITORY" -FileName "$env:over_file_name"
echo "file_exist=$file_exist" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
```

# 7. `Nginx` install to `Ubuntu`
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/install_nginx.sh && chmod a+x ./install_nginx.sh && ./install_nginx.sh
```

# 8. `nginx ` network `optimize`
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/nginx_optimize.sh && chmod a+x ./nginx_optimize.sh && ./nginx_optimize.sh
```


# 9. `Ubuntu-20.0.4 LTS` Setup
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/setup_ubuntu20.sh && chmod a+x ./setup_ubuntu20.sh && ./setup_ubuntu20.sh
```

# 10. `auto_ssl` usege
```
# one key
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/auto_ssl.sh && chmod a+x ./auto_ssl.sh && ./auto_ssl.sh

# scrpit transfrom pramars
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/auto_ssl.sh && chmod a+x ./auto_ssl.sh && ./auto_ssl.sh -nginx_web_root /testberoot -domain www.test.com -email testtest@gmail.com
```

# 11. `private_repo_tools` Private Repo Tools

## 11.1. Get Latest Version Name
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/private_repo_tools.sh && chmod a+x ./private_repo_tools.sh && ./private_repo_tools.sh -get_latest_releases_name ${GITHUB_PAT} owner/repo
```

## 11.2. Get Release UPLoadURL WIth ReleaseName
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/private_repo_tools.sh && chmod a+x ./private_repo_tools.sh && ./private_repo_tools.sh -get_releases_upload_url ${GITHUB_PAT} owner/repo ${relase_name}
```

## 11.3. checke version
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/private_repo_tools.sh && chmod a+x ./private_repo_tools.sh && ./private_repo_tools.sh -check_repo_need_update ${GITHUB_PAT} ${owner}/${repo} ${remote_owner}/${remote_repo}
```

## 11.4. Download Appoint Release Assets
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/private_repo_tools.sh && chmod a+x ./private_repo_tools.sh && ./private_repo_tools.sh -download_private_repo_asstes ${GITHUB_PAT} ${owner}/${repo} ${relase_name} ${assets_file_name}|all ${save_dir}
```

# 12. Checke ssl/tls cert express date
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/check_cert.sh && chmod a+x ./check_cert.sh && ./check_cert.sh ${/path/to/your/certificate.crt} && rm -rf ./check_cert.sh
```

# Ubuntu20+ add user
```wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/ubuntu20+adduser_to_login.sh && chmod a+x ./ubuntu20+adduser_to_login.sh && ./ubuntu20+adduser_to_login.sh <username> "<ssh_public_key>"```

# Ubuntu20+ add restricted user
```
wget --no-check-certificate https://raw.githubusercontent.com/george012/gt_script/master/create_restricted_user.sh && chmod a+x ./create_restricted_user.sh && ./create_restricted_user.sh <username> "<ssh_public_key>"
```
# use`redis_persistence_setup` 生产 Redis 持久化与认证配置

生产机 Redis（7/8）持久化配置器：开启 RDB + AOF 双持久化、驱逐策略钉死 `noeviction`
（适配「不用 TTL、数据生命周期由程序显式管理」的存储型用法——任何 LRU 驱逐都等于静默丢数据）、
可选启用 ACL 命名用户并关闭 default。交互式：全部变更先 diff 预览、确认后才写入，不适合无人值守。

## 一键调用（root；不带参数自动找 /etc/redis/redis.conf 等常见路径，或显式传 conf 路径）

```
wget --no-check-certificate https://raw.githubusercontent.com/0xdevelop/gt_script/main/redis_persistence_setup.sh && chmod a+x ./redis_persistence_setup.sh && sudo ./redis_persistence_setup.sh
```

```
sudo ./redis_persistence_setup.sh /path/to/redis.conf
```

## 改参数只动脚本头部「配置区」，执行段不需要读

| 变量 | 含义 |
| --- | --- |
| `REDIS_DIRECTIVES` | 持久化与内存目标值数组，`key\|目标行` 一行一项、行行带注释；加新指令往数组添一行即可 |
| `REDIS_DIRECTIVES_V7` | 仅 Redis >=7 生效的指令（multipart AOF 目录） |
| `REDIS_MAXMEMORY` | 空 = 不改机器现状；填值（如 `8gb`）才写。noeviction 下内存满表现为写报错，设了上限必须配容量告警 |
| `ACL_USER_RULES` | ACL 用户权限，默认 `~* &* +@all`；生产建议收窄：`~* &* +@all -flushall -flushdb -debug -shutdown` |
| `ACL_MIN_PASSWORD_LENGTH` | 密码最短长度，短于此值二次确认 |
| `AOF_WAIT_TIMEOUT_SECONDS` | 运行时开启 AOF 后等待 rewrite 收敛的超时 |
| `REDIS_MIN_MAJOR` | 支持的最低主版本 |

`appendfsync` 默认 `everysec`（掉电最多丢 1 秒已确认写）；账本级零窗口改 `always`，吞吐降一个量级。

## 行为边界

- 原配置硬备份 + cmp 校验（备份失败绝不动原文件）；原子替换 + 写后 SHA-256 复核。
- 对运行中的实例安全执行 RDB→AOF 切换（CONFIG SET 后等 rewrite 完成、带超时）——
  避免「只改配置就重启 → 空 AOF 把存量数据清零」。
- ACL：命名用户 + SHA-256 密码 hash（明文不落盘）、关 default、禁 requirepass；兼容外部 aclfile 与 conf 内 user（互斥检查）。
- 环境体检只警告不改值：bind 全接口 / protected-mode off / 副本实例关 default 会断主从认证。
- **不自动重启 Redis**；不改 `dir`、不递归改 `include`、相对路径 aclfile 直接拒绝。

# use`imagemagick_covert_icons` Logo 转多尺寸图标

## 一键调用命令
```
wget --no-check-certificate --secure-protocol=TLSv1_2 https://raw.githubusercontent.com/0xdevelop/shell_tools/main/imagemagick_covert_icons.sh && chmod a+x ./imagemagick_covert_icons.sh && ./imagemagick_covert_icons.sh
```

## 支持自定义 Logo 路径
```
wget --no-check-certificate --secure-protocol=TLSv1_2 https://raw.githubusercontent.com/0xdevelop/shell_tools/main/imagemagick_covert_icons.sh && chmod a+x ./imagemagick_covert_icons.sh && ./imagemagick_covert_icons.sh ./my_logo.png
```
