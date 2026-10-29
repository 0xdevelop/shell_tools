#!/bin/bash
# 契约
# 做：打印证书 notBefore / notAfter 与剩余天数
# 系统：有 openssl 与 GNU date 的 Linux
# 权限：能读证书文件
# 参数：$1 证书路径；缺则交互询问；-h/--help 查看用法
# 改：无
# 完：检查完成后删除脚本自身；失败或输入中断则保留
set -e

SCRIPT_NAME=$(basename -- "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "$#" -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then
    echo "用法：$0 [证书路径]"
    exit 0
fi

# 检查命令行参数
if [ "$#" -eq 1 ]; then
    CERT_FILE="$1"
else
    # 读取用户输入的证书文件路径
    read -p "请输入证书文件路径: " CERT_FILE
fi

# 检查文件是否存在
if [ ! -f "$CERT_FILE" ]; then
    echo "证书文件不存在: $CERT_FILE"
    exit 1
fi

# 获取SSL证书信息
CERT_INFO=$(openssl x509 -in "${CERT_FILE}" -dates -noout)

# 提取证书过期日期信息
START_DATE=$(echo "${CERT_INFO}" | grep "notBefore" | cut -d'=' -f 2)
END_DATE=$(echo "${CERT_INFO}" | grep "notAfter" | cut -d'=' -f 2)

# 将日期转换为Unix时间戳
START_TIMESTAMP=$(date -d "${START_DATE}" +%s)
END_TIMESTAMP=$(date -d "${END_DATE}" +%s)
CURRENT_TIMESTAMP=$(date +%s)

# 将日期转换为Unix时间戳，并格式化为UTC和北京时间
format_date() {
    local input_date="$1" utc_date beijing_date
    utc_date=$(date -u -d "$input_date" +"%Y-%m-%d %H:%M:%S UTC") || return
    beijing_date=$(TZ="Asia/Shanghai" date -d "$input_date" +"%Y-%m-%d %H:%M:%S Beijing") || return
    echo "$utc_date / $beijing_date"
}

START_DATE_FORMATTED=$(format_date "${START_DATE}")
END_DATE_FORMATTED=$(format_date "${END_DATE}")

# 计算剩余天数
DAYS_REMAINING=$(( (${END_TIMESTAMP} - ${CURRENT_TIMESTAMP}) / 86400 ))

# 输出结果
echo "SSL证书信息:"
echo " - 证书文件: ${CERT_FILE}"
echo " - 证书开始日期: ${START_DATE_FORMATTED}"
echo " - 证书过期日期: ${END_DATE_FORMATTED}"
echo " - 剩余天数: ${DAYS_REMAINING} 天"

# 检查是否过期
if [ ${CURRENT_TIMESTAMP} -gt ${END_TIMESTAMP} ]; then
    echo "证书已过期！"
else
    echo "证书在有效期内。"
fi

rm -rf -- "$SCRIPT_DIR/$SCRIPT_NAME"
