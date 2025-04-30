#!/bin/bash
set -e

RED='\''\033[0;31m'\''
ORANGE='\''\033[0;33m'\''
GREEN='\''\033[0;32m'\''
NC='\''\033[0m'\''

SERVER_WG_NIC=${WG_INTERFACE:-wg0}
SERVER_WG_IPV4=${WG_SERVER_IP:-10.66.66.1}
SERVER_WG_IPV6=${WG_SERVER_IPV6:-fd42:42:42::1}
SERVER_PORT=${WG_SERVER_PORT:-51820}
CLIENT_DNS_1=${WG_DNS_1:-1.1.1.1}
CLIENT_DNS_2=${WG_DNS_2:-1.0.0.1}
ALLOWED_IPS=${ALLOWED_IPS:-"0.0.0.0/0,::/0"}

SERVER_PUB_NIC=$(ip -4 route ls | grep default | awk '\''{print $5}'\'' | head -1)
SERVER_PUB_IP=$(ip -4 addr show dev ${SERVER_PUB_NIC} | grep -oP '\''(?<=inet\s)\d+(\.\d+){3}'\'' | head -1)

if [[ -z ${SERVER_PUB_IP} ]]; then
    SERVER_PUB_IP=$(ip -6 addr show dev ${SERVER_PUB_NIC} | grep -oP '\''(?<=inet6\s)[0-9a-fA-F:]+'\'' | head -1)
fi

echo -e "${GREEN}Используется интерфейс: ${SERVER_PUB_NIC}${NC}"
echo -e "${GREEN}Публичный IP: ${SERVER_PUB_IP}${NC}"

if [[ ! -f /etc/wireguard/${SERVER_WG_NIC}.conf ]]; then
    echo -e "${GREEN}Инициализация WireGuard. Создание конфигурации...${NC}"

    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

    echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}" > /etc/wireguard/params

    echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" > "/etc/wireguard/${SERVER_WG_NIC}.conf"

    echo "PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostUp = ip6tables -I FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >> "/etc/wireguard/${SERVER_WG_NIC}.conf"

    chmod 600 -R /etc/wireguard/

    echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" > /etc/sysctl.d/wg.conf
    sysctl --system
fi

echo -e "${GREEN}Запуск WireGuard...${NC}"
wg-quick up ${SERVER_WG_NIC}

mkdir -p /etc/wireguard/clients

echo -e "${GREEN}Запуск API сервера...${NC}"
cd /app && python3 api/app.py &
API_PID=$!

function cleanup() {
    echo -e "${GREEN}Остановка API сервера...${NC}"
    kill $API_PID

    echo -e "${GREEN}Остановка WireGuard...${NC}"
    wg-quick down ${SERVER_WG_NIC}
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

echo -e "${GREEN}WireGuard и API сервер запущены. Ожидание запросов...${NC}"
tail -f /dev/null & wait $!