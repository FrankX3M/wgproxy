#!/bin/bash
# Простой скрипт инициализации WireGuard с максимально надежной генерацией ключей

set -e

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

echo "Определен интерфейс: ${SERVER_PUB_NIC}"
echo "Публичный IP: ${SERVER_PUB_IP}"

# Создание директорий
mkdir -p /etc/wireguard/clients
chmod 700 /etc/wireguard
chmod 700 /etc/wireguard/clients

# Генерация ключей сервера через файлы
echo "Генерация ключей..."
TEMP_PRIV_KEY_FILE=$(mktemp)
TEMP_PUB_KEY_FILE=$(mktemp)

wg genkey > "$TEMP_PRIV_KEY_FILE"
cat "$TEMP_PRIV_KEY_FILE" | wg pubkey > "$TEMP_PUB_KEY_FILE"

SERVER_PRIV_KEY=$(cat "$TEMP_PRIV_KEY_FILE")
SERVER_PUB_KEY=$(cat "$TEMP_PUB_KEY_FILE")

# Удаляем временные файлы
rm -f "$TEMP_PRIV_KEY_FILE" "$TEMP_PUB_KEY_FILE"

# Вывод проверки ключей
echo "Сгенерированы ключи:"
echo "Приватный ключ: $SERVER_PRIV_KEY"
echo "Публичный ключ: $SERVER_PUB_KEY"

# Сохранение настроек WireGuard
cat > /etc/wireguard/params << EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${WG_INTERFACE}
SERVER_WG_IPV4=${WG_SERVER_IP}
SERVER_WG_IPV6=${WG_SERVER_IPV6}
SERVER_PORT=${WG_SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}
EOF

# Создание серверного интерфейса
echo "Создание конфигурации сервера..."
cat > "/etc/wireguard/${WG_INTERFACE}.conf" << EOF
[Interface]
Address = ${WG_SERVER_IP}/24,${WG_SERVER_IPV6}/64
ListenPort = ${WG_SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = iptables -I INPUT -p udp --dport ${WG_SERVER_PORT} -j ACCEPT
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
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
EOF

# Установка правильных прав доступа
chmod 600 -R /etc/wireguard/

# Включение IP forwarding
echo "Включение IP forwarding..."
echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" > /etc/sysctl.d/wg.conf

# Применение параметров sysctl (если возможно в контейнере)
sysctl --system || echo "Невозможно применить параметры sysctl в контейнере, убедитесь, что это сделано на хосте"

echo "WireGuard сервер успешно инициализирован!"
echo "Интерфейс: ${WG_INTERFACE}"
echo "IP сервера: ${WG_SERVER_IP}"
echo "Порт: ${WG_SERVER_PORT}"
echo "Публичный ключ: ${SERVER_PUB_KEY}"