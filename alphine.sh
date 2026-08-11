#!/bin/sh
set -e

echo "=== Alpine Linux VLESS-REALITY 专属安装脚本 ==="

# 1. 安装 Alpine 依赖工具
apk update
apk add curl jq openssl qrencode

# 2. 安装 Xray 核心 (解压官方二进制文件)
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
echo "正在下载 Xray 核心: ${XRAY_VER}..."
curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip"

mkdir -p /usr/local/bin /etc/xray
unzip -o /tmp/xray.zip xray -d /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f /tmp/xray.zip

# 3. 交互输入网络参数
echo ""
echo "请选择伪装域名 (SNI):"
echo "1) www.microsoft.com (推荐)"
echo "2) www.yandex.com"
printf "请输入选项 [1-2, 默认1]: "
read DOMAIN_CHOICE

case "$DOMAIN_CHOICE" in
  2)
    SNI="www.yandex.com"
    DEST="www.yandex.com:443"
    ;;
  *)
    SNI="www.microsoft.com"
    DEST="www.microsoft.com:443"
    ;;
esac

echo ""
printf "1. 请输入 VPS 内部监听端口 (例如 10022): "
read LISTEN_PORT
while [ -z "$LISTEN_PORT" ]; do
  printf "端口不能为空，请重新输入: "
  read LISTEN_PORT
done

printf "2. 请输入 NAT 面板分配的外部公网端口 (若与内部端口一致直接回车): "
read PUBLIC_PORT
if [ -z "$PUBLIC_PORT" ]; then
  PUBLIC_PORT=$LISTEN_PORT
fi

# 4. 生成 Xray 密钥
UUID=$(/usr/local/bin/xray uuid)
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# 5. 生成配置文件
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
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
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

# 6. 配置 OpenRC 服务管理 (Alpine 专属)
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

# 7. 获取公网 IP 并打印导入链接与二维码
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
RAW_URL="vless://${UUID}@${PUBLIC_IP}:${PUBLIC_PORT}?type=tcp&security=reality&encryption=none&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#Alpine-REALITY"

echo ""
echo "=================================================="
echo "    Alpine Linux VLESS-REALITY 安装成功！"
echo "=================================================="
echo ""
echo "👉 复制导入客户端链接："
echo "${RAW_URL}"
echo ""
echo "=================================================="
echo "👉 手机客户端扫码直接添加："
echo ""
qrencode -t ansiutf8 "${RAW_URL}"
echo "=================================================="
