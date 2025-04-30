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
