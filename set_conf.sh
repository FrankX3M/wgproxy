# Получаем новый приватный ключ
NEW_PRIVATE_KEY=$(wg genkey)
# Генерируем публичный ключ на основе приватного
NEW_PUBLIC_KEY=$(echo $NEW_PRIVATE_KEY | wg pubkey)

# Создаем обновленный файл params
cp config/params config/params.backup
cat > config/params << EOF
SERVER_PUB_IP=$(grep SERVER_PUB_IP config/params.backup | cut -d= -f2)
SERVER_PUB_NIC=$(grep SERVER_PUB_NIC config/params.backup | cut -d= -f2)
SERVER_WG_NIC=wg0
SERVER_WG_IPV4=10.66.66.1
SERVER_WG_IPV6=fd42:42:42::1
SERVER_PORT=51820
SERVER_PRIV_KEY=$NEW_PRIVATE_KEY
SERVER_PUB_KEY=$NEW_PUBLIC_KEY
CLIENT_DNS_1=1.1.1.1
CLIENT_DNS_2=1.0.0.1
ALLOWED_IPS=0.0.0.0/0,::/0
EOF

chmod 600 config/params