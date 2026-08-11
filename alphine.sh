#!/bin/sh
set -e

echo "=== Alpine Linux - Cloudflare CDN + Origin Rules 专属脚本 ==="

# 1. 停止老服务与清理旧配置
echo "--> 检查并清理旧服务与配置..."
if [ -f /etc/init.d/xray ]; then
    rc-service xray stop 2>/dev/null || true
fi
pkill -9 xray 2>/dev/null || true
rm -f /etc/xray/config.json
rm -f /etc/xray/server.crt /etc/xray/server.key

# 2. 安装/更新 Alpine 基础依赖工具
apk update
apk add curl jq openssl unzip

# 3. 下载/更新 Xray 核心
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
echo "--> 正在下载 Xray 核心: ${XRAY_VER}..."
curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip"

mkdir -p /usr/local/bin /etc/xray
unzip -o /tmp/xray.zip xray -d /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f /tmp/xray.zip

# 4. 交互输入网络参数
echo ""
printf "1. 请输入你准备托管在 CF 上的翻墙域名 (例如 vless.你的域名.com): "
read CF_DOMAIN < /dev/tty
while [ -z "$CF_DOMAIN" ]; do
  printf "域名不能为空，请重新输入: "
  read CF_DOMAIN < /dev/tty
done

printf "2. 请输入 VPS 内部监听端口 (例如 10022): "
read LISTEN_PORT < /dev/tty
while [ -z "$LISTEN_PORT" ]; do
  printf "端口不能为空，请重新输入: "
  read LISTEN_PORT < /dev/tty
done

printf "3. 请输入 NAT 面板分配的外部公网端口 (如 35462): "
read PUBLIC_PORT < /dev/tty
while [ -z "$PUBLIC_PORT" ]; do
  printf "端口不能为空，请重新输入: "
  read PUBLIC_PORT < /dev/tty
done

# 5. 生成 Xray 参数与自签证书
UUID=$(/usr/local/bin/xray uuid)
WS_PATH="/$(openssl rand -hex 4)"

echo "--> 正在生成自签 TLS 证书..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/xray/server.key -out /etc/xray/server.crt \
  -subj "/CN=${CF_DOMAIN}" 2>/dev/null

# 6. 生成新配置文件 (VLESS-WS-TLS)
cat << CONFIG > /etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/server.crt",
              "keyFile": "/etc/xray/server.key"
            }
          ]
        },
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
CONFIG

# 7. 配置 OpenRC 服务管理并启动
cat << 'SERVICE' > /etc/init.d/xray
#!/sbin/openrc-run

name="Xray Service"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -config /etc/xray/config.json"
command_background="yes"
pidfile="/run/xray.pid"

depend() {
    need net
    after firewall
}
SERVICE

chmod +x /etc/init.d/xray
rc-update add xray default
rc-service xray restart

# 8. 导出标准 CDN 链接
# 注意：生成的链接端口是 443，IP是你的域名，因为流量首先交给 Cloudflare
RAW_URL="vless://${UUID}@${CF_DOMAIN}:443?encryption=none&security=tls&type=ws&host=${CF_DOMAIN}&sni=${CF_DOMAIN}&path=${WS_PATH}#CF-CDN-NAT"

echo ""
echo "=================================================="
echo "    VPS 端 VLESS-WS-TLS 安装成功！"
echo "=================================================="
echo "👉 复制导入客户端的链接 (现在还连不上，请完成第二步)："
echo "${RAW_URL}"
echo "=================================================="
