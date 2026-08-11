
#!/bin/bash
set -e

echo "=== VLESS-REALITY NAT 自动化一键脚本 ==="

# 1. 安装基础依赖与 Xray/qrencode
if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl jq qrencode
elif command -v yum &>/dev/null; then
    yum install -y curl jq qrencode
fi

bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# 2. 交互输入配置信息
echo ""
echo "请选择伪装域名 (SNI):"
echo "1) www.microsoft.com (推荐)"
echo "2) www.yandex.com"
read -p "请输入选项 [1-2, 默认1]: " DOMAIN_CHOICE

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
read -p "1. 请输入 VPS 内部监听端口 (例如 10022): " LISTEN_PORT
while [[ -z "$LISTEN_PORT" ]]; do
  read -p "端口不能为空，请重新输入: " LISTEN_PORT
done

read -p "2. 请输入 NAT 面板分配的外部公网端口 (若与内部端口一致直接回车): " PUBLIC_PORT
if [[ -z "$PUBLIC_PORT" ]]; then
  PUBLIC_PORT=$LISTEN_PORT
fi

# 3. 生成密钥与参数
UUID=$(/usr/local/bin/xray uuid)
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# 4. 写入 Xray 配置文件
cat << CONFIG > /usr/local/etc/xray/config.json
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

# 5. 重启服务
systemctl daemon-reload
systemctl restart xray
systemctl enable xray

# 6. 获取公网 IP 并生成分享链接
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
RAW_URL="vless://${UUID}@${PUBLIC_IP}:${PUBLIC_PORT}?type=tcp&security=reality&encryption=none&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#NAT-REALITY"

echo ""
echo "=================================================="
echo "          VLESS-REALITY 安装成功！"
echo "=================================================="
echo ""
echo "👉 可直接复制导入客户端的链接："
echo "${RAW_URL}"
echo ""
echo "=================================================="
echo "👉 客户端扫码连接（手机端使用）："
echo ""
qrencode -t ansiutf8 "${RAW_URL}"
echo "=================================================="
