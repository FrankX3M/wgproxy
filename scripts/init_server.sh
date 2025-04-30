#!/bin/bash
# Скрипт инициализации WireGuard сервера в соответствии с angristan/wireguard-install

set -e

# Цвета для вывода
RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Инициализация WireGuard сервера...${NC}"

# Проверка на root
if [ "$EUID" -ne 0 ] && [ "$IN_DOCKER" != "true" ]; then
  echo -e "${RED}Скрипт должен быть запущен с правами root${NC}"
  exit 1
fi

# Параметры
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_SERVER_PORT="${WG_SERVER_PORT:-51820}"
WG_SERVER_IP="${WG_SERVER_IP:-10.66.66.1}"
WG_SERVER_IPV6="${WG_SERVER_IPV6:-fd42:42:42::1}"
CLIENT_DNS_1="${WG_DNS_1:-1.1.1.1}"
CLIENT_DNS_2="${WG_DNS_2:-1.0.0.1}"
ALLOWED_IPS="${ALLOWED_IPS:-0.0.0.0/0,::/0}"

# Определение сетевого интерфейса
SERVER_PUB_NIC=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
SERVER_PUB_IP=$(ip -4 addr show dev ${SERVER_PUB_NIC} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

if [[ -z ${SERVER_PUB_IP} ]]; then
    # Попытка получить IPv6 если нет IPv4
    SERVER_PUB_IP=$(ip -6 addr show dev ${SERVER_PUB_NIC} | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | head -1)
fi

echo -e "${GREEN}Определен интерфейс: ${SERVER_PUB_NIC}${NC}"
echo -e "${GREEN}Публичный IP: ${SERVER_PUB_IP}${NC}"

# Создание директорий
mkdir -p /etc/wireguard/clients
chmod 700 /etc/wireguard
chmod 700 /etc/wireguard/clients

# Генерация ключей сервера
echo -e "${GREEN}Генерация ключей...${NC}"
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

# Сохранение настроек WireGuard
echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${WG_INTERFACE}
SERVER_WG_IPV4=${WG_SERVER_IP}
SERVER_WG_IPV6=${WG_SERVER_IPV6}
SERVER_PORT=${WG_SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" >/etc/wireguard/params

# Создание серверного интерфейса
echo -e "${GREEN}Создание конфигурации сервера...${NC}"
echo "[Interface]
Address = ${WG_SERVER_IP}/24,${WG_SERVER_IPV6}/64
ListenPort = ${WG_SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${WG_INTERFACE}.conf"

# Добавление правил iptables
echo "PostUp = iptables -I INPUT -p udp --dport ${WG_SERVER_PORT} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${WG_INTERFACE} -j ACCEPT
PostUp = iptables -I FORWARD -i ${WG_INTERFACE} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostUp = ip6tables -I FORWARD -i ${WG_INTERFACE} -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${WG_SERVER_PORT} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${WG_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = ip6tables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >>"/etc/wireguard/${WG_INTERFACE}.conf"

# Установка правильных прав доступа
chmod 600 -R /etc/wireguard/

# Включение IP forwarding
echo -e "${GREEN}Включение IP forwarding...${NC}"
echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" >/etc/sysctl.d/wg.conf
sysctl --system

# Запуск WireGuard
echo -e "${GREEN}Запуск WireGuard...${NC}"
if [[ -f /etc/alpine-release ]]; then
    # Для Alpine
    wg-quick up ${WG_INTERFACE}
    rc-update add wg-quick.${WG_INTERFACE} default
else
    # Для Debian/Ubuntu/etc
    wg-quick up ${WG_INTERFACE}
    if command -v systemctl &>/dev/null; then
        systemctl enable wg-quick@${WG_INTERFACE}
    fi
fi

# Создание JSON файла с информацией о сервере
echo "{
  \"interface\": \"${WG_INTERFACE}\",
  \"public_key\": \"${SERVER_PUB_KEY}\",
  \"private_key\": \"${SERVER_PRIV_KEY}\",
  \"address\": \"${WG_SERVER_IP}/24,${WG_SERVER_IPV6}/64\",
  \"listen_port\": ${WG_SERVER_PORT},
  \"server_ip\": \"${SERVER_PUB_IP}\",
  \"dns\": [\"${CLIENT_DNS_1}\", \"${CLIENT_DNS_2}\"],
  \"allowed_ips\": \"${ALLOWED_IPS}\"
}" > /etc/wireguard/server_info.json

echo -e "${GREEN}WireGuard сервер успешно инициализирован!${NC}"
echo -e "${GREEN}Интерфейс: ${WG_INTERFACE}${NC}"
echo -e "${GREEN}IP сервера: ${WG_SERVER_IP}${NC}"
echo -e "${GREEN}Порт: ${WG_SERVER_PORT}${NC}"
echo -e "${GREEN}Публичный ключ: ${SERVER_PUB_KEY}${NC}"