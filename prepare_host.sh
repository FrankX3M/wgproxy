#!/bin/bash
# Скрипт для настройки хоста перед запуском WireGuard в Docker

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Проверка root прав
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Скрипт должен быть запущен с правами root${NC}"
  echo -e "Используйте: sudo $0"
  exit 1
fi

echo -e "${GREEN}Настройка системы для работы WireGuard в Docker...${NC}"

# Включение IP forwarding
echo -e "${YELLOW}Включение IP forwarding...${NC}"
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

# Сохранение настроек для загрузки после перезагрузки
echo -e "${YELLOW}Сохранение настроек IP forwarding...${NC}"
cat > /etc/sysctl.d/99-wireguard.conf << EOF
# Настройки для WireGuard VPN
net.ipv4.ip_forward = 1
net.ipv4.conf.all.src_valid_mark = 1
net.ipv6.conf.all.forwarding = 1
EOF

# Применение настроек sysctl
sysctl -p /etc/sysctl.d/99-wireguard.conf

# Проверка модуля ядра WireGuard
echo -e "${YELLOW}Проверка модуля ядра WireGuard...${NC}"
if ! lsmod | grep -q wireguard; then
  echo -e "${YELLOW}Модуль WireGuard не загружен, попытка загрузки...${NC}"
  modprobe wireguard
  
  if ! lsmod | grep -q wireguard; then
    echo -e "${RED}Не удалось загрузить модуль WireGuard.${NC}"
    echo -e "${YELLOW}Проверьте установку WireGuard на хосте:${NC}"
    echo -e "  - Для Debian/Ubuntu: sudo apt install wireguard"
    echo -e "  - Для CentOS/RHEL: sudo dnf install wireguard-tools"
    echo -e "  - Или проверьте, что модуль включен в ядро${NC}"
  else
    echo -e "${GREEN}Модуль WireGuard успешно загружен${NC}"
  fi
else
  echo -e "${GREEN}Модуль WireGuard уже загружен${NC}"
fi

# Проверка, установлен ли Docker и Docker Compose
echo -e "${YELLOW}Проверка установки Docker...${NC}"
if ! command -v docker &> /dev/null; then
  echo -e "${RED}Docker не установлен. Установите Docker перед запуском.${NC}"
  echo -e "${YELLOW}Инструкции: https://docs.docker.com/engine/install/${NC}"
else
  echo -e "${GREEN}Docker установлен${NC}"
fi

if ! command -v docker compose &> /dev/null; then
  echo -e "${RED}Docker Compose не установлен. Установите Docker Compose перед запуском.${NC}"
  echo -e "${YELLOW}Инструкции: https://docs.docker.com/compose/install/${NC}"
else
  echo -e "${GREEN}Docker Compose установлен${NC}"
fi

# Проверка наличия папки для конфигурации WireGuard
echo -e "${YELLOW}Создание директории для конфигурации WireGuard...${NC}"
mkdir -p ./config
mkdir -p ./config/clients
chmod 700 ./config
chmod 700 ./config/clients

# Создание скрипта для быстрого анализа конфигурации
echo -e "${YELLOW}Создание вспомогательных скриптов...${NC}"
cat > ./analyze-config.sh << 'EOF'
#!/bin/bash
# Скрипт для анализа конфигурации WireGuard

CONTAINER="wireguard-server"

echo "Анализ конфигурации WireGuard в контейнере $CONTAINER..."

# Проверка существования контейнера
if ! docker ps -q -f name=$CONTAINER | grep -q .; then
    echo "Ошибка: Контейнер $CONTAINER не запущен"
    exit 1
fi

# Проверка модуля ядра на хосте
echo "Проверка модуля ядра WireGuard на хосте:"
lsmod | grep wireguard || echo "Модуль WireGuard не загружен на хосте"

# Проверка IP forwarding на хосте
echo "Проверка IP forwarding на хосте:"
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding

# Выполнение проверки конфигурации в контейнере
echo "Выполнение проверки в контейнере:"
docker exec $CONTAINER bash -c "cat /etc/wireguard/wg0.conf"
echo "----"
docker exec $CONTAINER bash -c "grep -v '^#' /etc/wireguard/wg0.conf | grep -v '^$'"
echo "----"
docker exec $CONTAINER bash -c "test -s /etc/wireguard/params && echo 'Файл params существует и не пустой' || echo 'Файл params не существует или пустой'"
echo "----"
docker exec $CONTAINER bash -c "test -f /etc/wireguard/params && cat /etc/wireguard/params"
echo "----"
docker exec $CONTAINER bash -c "wg show || echo 'Ошибка при выполнении wg show'"

echo "Анализ завершен."
EOF

chmod +x ./analyze-config.sh

# Создание скрипта check-client-config.sh
echo -e "${YELLOW}Создание скрипта для проверки клиентских конфигураций...${NC}"
cat > ./check-client-config.sh << 'EOF'
#!/bin/bash
# Скрипт для проверки и исправления конфигурации клиента WireGuard

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Проверка параметров
if [ "$#" -lt 1 ]; then
    echo -e "${YELLOW}Использование: $0 <имя_пира>${NC}"
    echo -e "Пример: $0 my-device2"
    exit 1
fi

PEER_NAME="$1"
CONFIG_DIR="./config/clients"
CONFIG_FILE="${CONFIG_DIR}/wg0-client-${PEER_NAME}.conf"

echo -e "${GREEN}Проверка и исправление конфигурации клиента ${PEER_NAME}${NC}"

# Проверка существования файла
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Ошибка: Файл конфигурации '$CONFIG_FILE' не найден.${NC}"
    echo -e "${YELLOW}Доступные файлы конфигураций:${NC}"
    ls -la "$CONFIG_DIR"
    exit 1
fi

# Получение публичного IP сервера
PUBLIC_IP=$(curl -s ifconfig.me)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s icanhazip.com)
fi

if [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}Не удалось определить публичный IP сервера${NC}"
    PUBLIC_IP="ВВЕДИТЕ_ВАШ_ПУБЛИЧНЫЙ_IP"
else
    echo -e "${GREEN}Публичный IP сервера: ${PUBLIC_IP}${NC}"
fi

# Создание бэкапа конфигурации
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
echo -e "${GREEN}Создан бэкап конфигурации: ${CONFIG_FILE}.bak${NC}"

# Проверка и изменение Endpoint
CURRENT_ENDPOINT=$(grep "Endpoint" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
echo -e "${YELLOW}Текущий Endpoint: ${CURRENT_ENDPOINT}${NC}"

# Запрос у пользователя, изменять ли Endpoint
read -p "Изменить Endpoint на ${PUBLIC_IP}:51820? (y/n): " CHANGE_ENDPOINT
if [ "$CHANGE_ENDPOINT" = "y" ] || [ "$CHANGE_ENDPOINT" = "Y" ]; then
    # Изменение Endpoint
    sed -i "s|Endpoint = .*|Endpoint = ${PUBLIC_IP}:51820|" "$CONFIG_FILE"
    echo -e "${GREEN}Endpoint обновлен на ${PUBLIC_IP}:51820${NC}"
else
    echo -e "${YELLOW}Endpoint не изменен${NC}"
fi

# Проверка MTU
if ! grep -q "MTU" "$CONFIG_FILE"; then
    # Добавление MTU если его нет
    sed -i "/\[Interface\]/a MTU = 1420" "$CONFIG_FILE"
    echo -e "${GREEN}Добавлен параметр MTU = 1420${NC}"
else
    echo -e "${GREEN}Параметр MTU уже установлен${NC}"
fi

# Проверка DNS
CURRENT_DNS=$(grep "DNS" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
echo -e "${YELLOW}Текущий DNS: ${CURRENT_DNS}${NC}"

# Запрос у пользователя, изменять ли DNS
read -p "Изменить DNS на 8.8.8.8,8.8.4.4? (y/n): " CHANGE_DNS
if [ "$CHANGE_DNS" = "y" ] || [ "$CHANGE_DNS" = "Y" ]; then
    # Изменение DNS
    sed -i "s|DNS = .*|DNS = 8.8.8.8,8.8.4.4|" "$CONFIG_FILE"
    echo -e "${GREEN}DNS обновлен на 8.8.8.8,8.8.4.4${NC}"
else
    echo -e "${YELLOW}DNS не изменен${NC}"
fi

# Проверка PersistentKeepalive
if ! grep -q "PersistentKeepalive" "$CONFIG_FILE"; then
    # Добавление PersistentKeepalive если его нет
    sed -i "/\[Peer\]/a PersistentKeepalive = 25" "$CONFIG_FILE"
    echo -e "${GREEN}Добавлен параметр PersistentKeepalive = 25${NC}"
else
    echo -e "${GREEN}Параметр PersistentKeepalive уже установлен${NC}"
fi

echo -e "${GREEN}Конфигурация обновлена. Генерация нового QR-кода...${NC}"

# Генерация QR-кода
qrencode -t png -o "${CONFIG_DIR}/${PEER_NAME}_qr.png" < "$CONFIG_FILE"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}QR-код успешно сгенерирован: ${CONFIG_DIR}/${PEER_NAME}_qr.png${NC}"
    echo -e "${YELLOW}Отсканируйте этот QR-код в мобильном приложении WireGuard${NC}"
else
    echo -e "${RED}Ошибка при генерации QR-кода${NC}"
fi

echo -e "${GREEN}Итоговая конфигурация:${NC}"
cat "$CONFIG_FILE"

echo -e "\n${YELLOW}Обратите внимание:${NC}"
echo -e "1. Endpoint должен указывать на публичный IP вашего сервера"
echo -e "2. MTU 1420 оптимально для большинства соединений"
echo -e "3. PersistentKeepalive=25 поддерживает соединение активным"
echo -e "4. Скачайте новый QR-код или конфигурацию и используйте в клиенте"
EOF

chmod +x ./check-client-config.sh

# Создание скрипта fix-forwarding.sh
echo -e "${YELLOW}Создание скрипта для исправления форвардинга...${NC}"
cat > ./fix-forwarding.sh << 'EOF'
#!/bin/bash
# Скрипт для исправления проблем с маршрутизацией и форвардингом для WireGuard

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Проверка root прав
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Скрипт должен быть запущен с правами root${NC}"
  echo -e "Используйте: sudo $0"
  exit 1
fi

echo -e "${GREEN}Настройка файрвола и форвардинга для WireGuard VPN${NC}"

# 1. Проверка и включение IP forwarding
echo -e "${YELLOW}Проверка IP forwarding...${NC}"
if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    echo -e "${RED}IP forwarding отключен! Включение...${NC}"
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf
else
    echo -e "${GREEN}IP forwarding уже включен.${NC}"
fi

# 2. Настройка файрвола UFW для разрешения форвардинга
echo -e "${YELLOW}Настройка UFW для разрешения форвардинга...${NC}"

# Проверка наличия UFW
if command -v ufw &> /dev/null; then
    # Разрешение форвардинга в UFW
    grep -q "DEFAULT_FORWARD_POLICY=\"ACCEPT\"" /etc/default/ufw || \
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
    
    # Разрешение маскарадинга
    grep -q "net/ipv4/ip_forward=1" /etc/ufw/sysctl.conf || \
    echo "net/ipv4/ip_forward=1" >> /etc/ufw/sysctl.conf
    
    # Перезапуск UFW
    echo -e "${YELLOW}Перезапуск UFW...${NC}"
    ufw disable
    ufw enable
    
    # Добавление правил для WireGuard
    ufw allow 51820/udp
    ufw route allow in on wg0 out on eth0
    ufw reload
else
    echo -e "${YELLOW}UFW не установлен. Пропускаем настройку UFW.${NC}"
fi

# 3. Добавление прямых правил iptables (будут работать даже без UFW)
echo -e "${YELLOW}Добавление правил iptables для форвардинга...${NC}"

# Удаление старых правил если они существуют
iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null
iptables -t nat -D POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE 2>/dev/null

# Добавление новых правил
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE

# 4. Настройка внутри Docker-контейнера
echo -e "${YELLOW}Настройка внутри Docker-контейнера...${NC}"
docker exec wireguard-server bash -c '
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
iptables -I FORWARD -i wg0 -j ACCEPT
iptables -I FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE
'

# 5. Сохранение правил iptables
echo -e "${YELLOW}Сохранение правил iptables...${NC}"
if command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4 || iptables-save > /etc/iptables.rules
    echo -e "${GREEN}Правила iptables сохранены.${NC}"
else
    echo -e "${YELLOW}Невозможно сохранить правила iptables. Эти изменения будут потеряны после перезагрузки.${NC}"
    echo -e "${YELLOW}Для сохранения правил установите пакет iptables-persistent.${NC}"
fi

# 6. Перезапуск WireGuard
echo -e "${YELLOW}Перезапуск WireGuard...${NC}"
docker exec wireguard-server wg-quick down wg0
docker exec wireguard-server wg-quick up wg0

echo -e "${GREEN}Настройка завершена!${NC}"
echo -e "${YELLOW}Проверьте подключение и трафик снова.${NC}"
echo -e "${YELLOW}Если проблемы сохраняются, проверьте настройки клиента.${NC}"
EOF

chmod +x ./fix-forwarding.sh

# Создание скрипта update-config.sh для исправления пустого приватного ключа
echo -e "${YELLOW}Создание скрипта для исправления конфигурации...${NC}"
cat > ./update-config.sh << 'EOF'
#!/bin/bash
# Скрипт для исправления и обновления конфигурации WireGuard

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Проверка root прав
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Скрипт должен быть запущен с правами root${NC}"
  echo -e "Используйте: sudo $0"
  exit 1
fi

echo -e "${GREEN}Исправление конфигурации WireGuard...${NC}"

# Базовые переменные
CONFIG_DIR="./config"
WG_CONF="${CONFIG_DIR}/wg0.conf"
PARAMS_FILE="${CONFIG_DIR}/params"

# Создаем резервные копии
echo -e "${YELLOW}Создание резервных копий...${NC}"
if [ -f "$WG_CONF" ]; then
    cp "$WG_CONF" "${WG_CONF}.backup"
    echo -e "${GREEN}Создана резервная копия файла конфигурации WireGuard${NC}"
fi

if [ -f "$PARAMS_FILE" ]; then
    cp "$PARAMS_FILE" "${PARAMS_FILE}.backup"
    echo -e "${GREEN}Создана резервная копия файла params${NC}"
fi

# Проверка наличия приватного ключа
echo -e "${YELLOW}Проверка приватного ключа...${NC}"
if [ -f "$WG_CONF" ]; then
    # Проверка пустого приватного ключа
    if grep -q "PrivateKey = $" "$WG_CONF" || grep -q "PrivateKey =$" "$WG_CONF"; then
        echo -e "${RED}Обнаружен пустой приватный ключ в файле конфигурации${NC}"
        
        # Генерация нового ключа
        echo -e "${YELLOW}Генерация нового приватного ключа...${NC}"
        NEW_PRIVATE_KEY=$(wg genkey)
        NEW_PUBLIC_KEY=$(echo "$NEW_PRIVATE_KEY" | wg pubkey)
        
        # Обновление конфигурации
        sed -i "s|PrivateKey = $|PrivateKey = $NEW_PRIVATE_KEY|" "$WG_CONF"
        sed -i "s|PrivateKey =$|PrivateKey = $NEW_PRIVATE_KEY|" "$WG_CONF"
        
        echo -e "${GREEN}Приватный ключ обновлен в $WG_CONF${NC}"
        
        # Обновление файла params
        if [ -f "$PARAMS_FILE" ]; then
            sed -i "s|SERVER_PRIV_KEY=|SERVER_PRIV_KEY=$NEW_PRIVATE_KEY|" "$PARAMS_FILE"
            sed -i "s|SERVER_PUB_KEY=|SERVER_PUB_KEY=$NEW_PUBLIC_KEY|" "$PARAMS_FILE"
            echo -e "${GREEN}Ключи обновлены в $PARAMS_FILE${NC}"
        else
            echo -e "${YELLOW}Файл $PARAMS_FILE не найден, создание нового...${NC}"
            
            # Получение информации о сети
            SERVER_PUB_NIC=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
            SERVER_PUB_IP=$(ip -4 addr show dev ${SERVER_PUB_NIC} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            
            # Создание файла params
            cat > "$PARAMS_FILE" << EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=wg0
SERVER_WG_IPV4=10.66.66.1
SERVER_WG_IPV6=fd42:42:42::1
SERVER_PORT=51820
SERVER_PRIV_KEY=${NEW_PRIVATE_KEY}
SERVER_PUB_KEY=${NEW_PUBLIC_KEY}
CLIENT_DNS_1=1.1.1.1
CLIENT_DNS_2=1.0.0.1
ALLOWED_IPS=0.0.0.0/0,::/0
EOF
            chmod 600 "$PARAMS_FILE"
            echo -e "${GREEN}Создан новый файл $PARAMS_FILE с ключами${NC}"
        fi
    else
        echo -e "${GREEN}Приватный ключ уже установлен в файле конфигурации${NC}"
    fi
else
    echo -e "${RED}Файл конфигурации $WG_CONF не найден${NC}"
    echo -e "${YELLOW}Создание новой конфигурации...${NC}"
    
    # Генерация ключей
    NEW_PRIVATE_KEY=$(wg genkey)
    NEW_PUBLIC_KEY=$(echo "$NEW_PRIVATE_KEY" | wg pubkey)
    
    # Определение сетевого интерфейса
    SERVER_PUB_NIC=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
    
    # Создание директории конфигурации
    mkdir -p "$CONFIG_DIR"
    
    # Создание файла конфигурации WireGuard
    cat > "$WG_CONF" << EOF
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 51820
PrivateKey = ${NEW_PRIVATE_KEY}
PostUp = iptables -I INPUT -p udp --dport 51820 -j ACCEPT
PostUp = iptables -I FORWARD -i ${SERVER_PUB_NIC} -o wg0 -j ACCEPT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostUp = ip6tables -I FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
EOF
    
    chmod 600 "$WG_CONF"
    echo -e "${GREEN}Создан новый файл конфигурации $WG_CONF${NC}"
    
    # Создание файла params
    SERVER_PUB_IP=$(ip -4 addr show dev ${SERVER_PUB_NIC} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    cat > "$PARAMS_FILE" << EOF
SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=wg0
SERVER_WG_IPV4=10.66.66.1
SERVER_WG_IPV6=fd42:42:42::1
SERVER_PORT=51820
SERVER_PRIV_KEY=${NEW_PRIVATE_KEY}
SERVER_PUB_KEY=${NEW_PUBLIC_KEY}
CLIENT_DNS_1=1.1.1.1
CLIENT_DNS_2=1.0.0.1
ALLOWED_IPS=0.0.0.0/0,::/0
EOF
    
    chmod 600 "$PARAMS_FILE"
    echo -e "${GREEN}Создан новый файл $PARAMS_FILE${NC}"
fi

# Проверка существования директории для клиентских конфигураций
CLIENTS_DIR="${CONFIG_DIR}/clients"
if [ ! -d "$CLIENTS_DIR" ]; then
    mkdir -p "$CLIENTS_DIR"
    chmod 700 "$CLIENTS_DIR"
    echo -e "${GREEN}Создана директория для клиентских конфигураций: $CLIENTS_DIR${NC}"
fi

# Перезапуск Docker-контейнеров
echo -e "${YELLOW}Перезапуск Docker-контейнеров...${NC}"
docker compose down
sleep 2
docker compose up -d

echo -e "${GREEN}Настройка WireGuard завершена!${NC}"
echo -e "${YELLOW}Для проверки статуса выполните:${NC}"
echo -e "  docker ps"
echo -e "  docker logs wireguard-server"
echo -e "${YELLOW}Для проверки состояния интерфейса WireGuard:${NC}"
echo -e "  docker exec wireguard-server wg"
EOF

chmod +x ./update-config.sh

echo -e "${GREEN}Система подготовлена для запуска WireGuard в Docker${NC}"
echo -e "${YELLOW}Теперь вы можете запустить контейнеры:${NC}"
echo -e "  docker compose up -d"
echo -e "${YELLOW}Для исправления пустого приватного ключа используйте:${NC}"
echo -e "  sudo ./update-config.sh"
echo -e "${YELLOW}Для исправления проблем с форвардингом:${NC}"
echo -e "  sudo ./fix-forwarding.sh"
echo -e "${YELLOW}Для проверки клиентских конфигураций:${NC}"
echo -e "  sudo ./check-client-config.sh <имя_клиента>"