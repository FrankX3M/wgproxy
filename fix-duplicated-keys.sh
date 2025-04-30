#!/bin/bash
# Скрипт для полного пересоздания конфигурации WireGuard

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Пересоздание конфигурации WireGuard...${NC}"

# Останавливаем контейнер
echo -e "${YELLOW}Останавливаем контейнер wireguard-server...${NC}"
docker stop wireguard-server

# Резервное копирование существующей конфигурации
echo -e "${YELLOW}Создание резервных копий конфигурации...${NC}"
mkdir -p ./config-backup
cp -r ./config/* ./config-backup/
echo -e "${GREEN}Резервные копии сохранены в ./config-backup/${NC}"

# Генерация новых ключей
echo -e "${YELLOW}Генерация новых ключей WireGuard...${NC}"
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

echo -e "${GREEN}Сгенерированы новые ключи:${NC}"
echo -e "Приватный ключ: $PRIVATE_KEY"
echo -e "Публичный ключ: $PUBLIC_KEY"

# Определение сетевого интерфейса
SERVER_PUB_NIC=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
SERVER_PUB_IP=$(ip -4 addr show dev "$SERVER_PUB_NIC" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

# Создание новой конфигурации
echo -e "${YELLOW}Создание новой конфигурации WireGuard...${NC}"

cat > ./config/wg0.conf << EOF
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -I INPUT -p udp --dport 51820 -j ACCEPT
PostUp = iptables -I FORWARD -i $SERVER_PUB_NIC -o wg0 -j ACCEPT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
PostUp = ip6tables -I FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT
PostDown = iptables -D FORWARD -i $SERVER_PUB_NIC -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o $SERVER_PUB_NIC -j MASQUERADE
EOF

echo -e "${GREEN}Создан новый файл конфигурации ./config/wg0.conf${NC}"

# Создание файла params
echo -e "${YELLOW}Создание нового файла params...${NC}"

cat > ./config/params << EOF
SERVER_PUB_IP=$SERVER_PUB_IP
SERVER_PUB_NIC=$SERVER_PUB_NIC
SERVER_WG_NIC=wg0
SERVER_WG_IPV4=10.66.66.1
SERVER_WG_IPV6=fd42:42:42::1
SERVER_PORT=51820
SERVER_PRIV_KEY=$PRIVATE_KEY
SERVER_PUB_KEY=$PUBLIC_KEY
CLIENT_DNS_1=1.1.1.1
CLIENT_DNS_2=1.0.0.1
ALLOWED_IPS=0.0.0.0/0,::/0
EOF

echo -e "${GREEN}Создан новый файл ./config/params${NC}"

# Установка правильных прав доступа
echo -e "${YELLOW}Установка правильных прав доступа...${NC}"
chmod 600 ./config/wg0.conf
chmod 600 ./config/params

# Копирование существующих клиентских конфигураций
if [ -d "./config-backup/clients" ] && [ "$(ls -A ./config-backup/clients 2>/dev/null)" ]; then
    echo -e "${YELLOW}Копирование клиентских конфигураций...${NC}"
    mkdir -p ./config/clients
    chmod 700 ./config/clients
    
    # Копируем только нужные файлы, не копируя конфигурации
    cp ./config-backup/clients/*.png ./config/clients/ 2>/dev/null || true
    
    echo -e "${GREEN}Клиентские QR-коды скопированы${NC}"
    echo -e "${YELLOW}Клиентские конфигурации будут созданы заново после запуска сервера${NC}"
fi

# Запуск контейнера
echo -e "${YELLOW}Запуск контейнера wireguard-server...${NC}"
docker start wireguard-server

# Ожидание запуска контейнера
echo -e "${YELLOW}Ожидание запуска контейнера...${NC}"
sleep 5

# Проверка логов контейнера
echo -e "${YELLOW}Проверка логов контейнера...${NC}"
docker logs --tail 20 wireguard-server

echo -e "${GREEN}Операция завершена.${NC}"
echo -e "${YELLOW}Проверьте состояние WireGuard:${NC} docker exec -it wireguard-server wg show"
echo -e "${YELLOW}Клиенты должны быть пересозданы через API или веб-интерфейс.${NC}"