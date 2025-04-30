#!/bin/bash
set -e

# Убираем цветовую схему, которая вызывает проблемы
echo "Инициализация WireGuard API сервера..."

# Параметры
SERVER_WG_NIC=${WG_INTERFACE:-wg0}
SERVER_WG_IPV4=${WG_SERVER_IP:-10.66.66.1}
SERVER_WG_IPV6=${WG_SERVER_IPV6:-fd42:42:42::1}
SERVER_PORT=${WG_SERVER_PORT:-51820}
CLIENT_DNS_1=${WG_DNS_1:-1.1.1.1}
CLIENT_DNS_2=${WG_DNS_2:-1.0.0.1}
ALLOWED_IPS=${ALLOWED_IPS:-"0.0.0.0/0,::/0"}

# Определение интерфейса и IP
SERVER_PUB_NIC=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
SERVER_PUB_IP=$(ip -4 addr show dev ${SERVER_PUB_NIC} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

if [ -z "$SERVER_PUB_IP" ]; then
    SERVER_PUB_IP=$(ip -6 addr show dev ${SERVER_PUB_NIC} | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' | head -1)
fi

echo "Используется интерфейс: ${SERVER_PUB_NIC}"
echo "Публичный IP: ${SERVER_PUB_IP}"

# Создание директорий
mkdir -p /etc/wireguard/clients
chmod 700 /etc/wireguard
chmod 700 /etc/wireguard/clients

# Инициализация WireGuard, если нет конфигурации
if [ ! -f "/etc/wireguard/${SERVER_WG_NIC}.conf" ]; then
    echo "Инициализация WireGuard. Создание конфигурации..."

    # Генерация ключей через временные файлы
    TEMP_PRIV_KEY_FILE=$(mktemp)
    TEMP_PUB_KEY_FILE=$(mktemp)
    
    wg genkey > "$TEMP_PRIV_KEY_FILE"
    cat "$TEMP_PRIV_KEY_FILE" | wg pubkey > "$TEMP_PUB_KEY_FILE"
    
    SERVER_PRIV_KEY=$(cat "$TEMP_PRIV_KEY_FILE")
    SERVER_PUB_KEY=$(cat "$TEMP_PUB_KEY_FILE")
    
    rm -f "$TEMP_PRIV_KEY_FILE" "$TEMP_PUB_KEY_FILE"

    # Проверка ключей
    echo "Сгенерированы ключи:"
    echo "Приватный ключ: $SERVER_PRIV_KEY"
    echo "Публичный ключ: $SERVER_PUB_KEY"

    # Сохранение параметров
    cat > /etc/wireguard/params << EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}
EOF

    # Создание конфигурации WireGuard
    cat > "/etc/wireguard/${SERVER_WG_NIC}.conf" << EOF
[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = iptables -I INPUT -p udp --dport ${SERVER_PORT} -j ACCEPT
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
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
EOF

    chmod 600 -R /etc/wireguard/
fi

# Проверка конфигурации на проблемы
echo "Проверка конфигурации WireGuard..."
CONFIG_FILE="/etc/wireguard/${SERVER_WG_NIC}.conf"
PARAMS_FILE="/etc/wireguard/params"

# Функция для обработки дублированных ключей
fix_duplicated_keys() {
    local file=$1
    local pattern=$2
    local key_name=$3
    
    if grep -q "$pattern.*=.*=.*=" "$file"; then
        echo "Обнаружен дублированный $key_name в $file"
        
        # Извлечение первого ключа (первая половина дублированного ключа)
        local first_key=$(grep "$pattern" "$file" | sed -E "s/$pattern *= *([a-zA-Z0-9+\/=]+).*/\1/" | cut -d'=' -f1)
        
        if [ -n "$first_key" ]; then
            echo "Исправление дублированного $key_name..."
            sed -i "s/$pattern *=.*$/$pattern = $first_key/" "$file"
            echo "$key_name исправлен в $file"
        fi
    fi
}

# Проверка на дублированные ключи
if [ -f "$CONFIG_FILE" ]; then
    # Исправление дублированных ключей в конфигурации
    fix_duplicated_keys "$CONFIG_FILE" "PrivateKey" "приватный ключ"
    
    # Для пиров
    PEER_SECTIONS=$(grep -n "\[Peer\]" "$CONFIG_FILE" | cut -d ":" -f1)
    
    for LINE_NUM in $PEER_SECTIONS; do
        # Находим блок текущего пира
        NEXT_PEER=$(grep -n "\[Peer\]" "$CONFIG_FILE" | awk -v line="$LINE_NUM" '$1 > line {print $1; exit}')
        
        if [ -z "$NEXT_PEER" ]; then
            END_LINE=$(wc -l "$CONFIG_FILE" | awk '{print $1}')
        else
            END_LINE=$((NEXT_PEER - 1))
        fi
        
        # Создаем временный файл для блока пира
        TMP_PEER_FILE=$(mktemp)
        sed -n "${LINE_NUM},${END_LINE}p" "$CONFIG_FILE" > "$TMP_PEER_FILE"
        
        # Исправляем дублированные ключи в блоке пира
        fix_duplicated_keys "$TMP_PEER_FILE" "PublicKey" "публичный ключ"
        fix_duplicated_keys "$TMP_PEER_FILE" "PresharedKey" "предварительно разделяемый ключ"
        
        # Заменяем блок пира в основной конфигурации
        sed -i "${LINE_NUM},${END_LINE}d" "$CONFIG_FILE"
        sed -i "${LINE_NUM}r $TMP_PEER_FILE" "$CONFIG_FILE"
        
        # Удаляем временный файл
        rm -f "$TMP_PEER_FILE"
    done
fi

# Проверка и исправление пустого приватного ключа
if [ -f "$CONFIG_FILE" ]; then
    # Проверка пустого приватного ключа
    if grep -q "PrivateKey = $" "$CONFIG_FILE" || grep -q "PrivateKey =$" "$CONFIG_FILE" || ! grep -q "PrivateKey" "$CONFIG_FILE"; then
        echo "ОШИБКА: Приватный ключ не установлен или пуст в $CONFIG_FILE"
        
        # Генерация нового ключа
        echo "Генерация нового приватного ключа..."
        NEW_PRIVATE_KEY=$(wg genkey)
        NEW_PUBLIC_KEY=$(echo "$NEW_PRIVATE_KEY" | wg pubkey)
        
        # Обновление файла конфигурации
        if grep -q "PrivateKey = $" "$CONFIG_FILE" || grep -q "PrivateKey =$" "$CONFIG_FILE"; then
            sed -i "s|PrivateKey *=.*$|PrivateKey = $NEW_PRIVATE_KEY|" "$CONFIG_FILE"
        else
            # Если строки нет, добавляем ее
            sed -i "/\[Interface\]/a PrivateKey = $NEW_PRIVATE_KEY" "$CONFIG_FILE"
        fi
        
        # Обновление файла params
        if [ -f "$PARAMS_FILE" ]; then
            if grep -q "SERVER_PRIV_KEY" "$PARAMS_FILE"; then
                sed -i "s|SERVER_PRIV_KEY=.*$|SERVER_PRIV_KEY=$NEW_PRIVATE_KEY|" "$PARAMS_FILE"
                sed -i "s|SERVER_PUB_KEY=.*$|SERVER_PUB_KEY=$NEW_PUBLIC_KEY|" "$PARAMS_FILE"
            else
                # Если строк нет, добавляем их
                echo "SERVER_PRIV_KEY=$NEW_PRIVATE_KEY" >> "$PARAMS_FILE"
                echo "SERVER_PUB_KEY=$NEW_PUBLIC_KEY" >> "$PARAMS_FILE"
            fi
        else
            # Создание файла params если он не существует
            cat > "$PARAMS_FILE" << EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${NEW_PRIVATE_KEY}
SERVER_PUB_KEY=${NEW_PUBLIC_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
ALLOWED_IPS=${ALLOWED_IPS}
EOF
        fi
        
        echo "Приватный и публичный ключи обновлены"
    fi
fi

# Проверка и загрузка модуля WireGuard
if ! lsmod | grep -q wireguard; then
    echo "Модуль WireGuard не загружен, попытка загрузить..."
    modprobe wireguard || echo "Не удалось загрузить модуль WireGuard. Убедитесь, что он доступен в хост-системе."
fi

# Запуск WireGuard
echo "Запуск WireGuard..."
wg-quick up ${SERVER_WG_NIC}

# Запуск API сервера
echo "Запуск API сервера..."
cd /app && python3 api/app.py &
API_PID=$!

# Обработка завершения
cleanup() {
    echo "Остановка API сервера..."
    kill $API_PID

    echo "Остановка WireGuard..."
    wg-quick down ${SERVER_WG_NIC}
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

echo "WireGuard и API сервер запущены. Ожидание запросов..."
tail -f /dev/null & wait $!