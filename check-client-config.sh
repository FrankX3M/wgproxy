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
