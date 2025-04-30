#!/bin/bash
# Скрипт для исправления конфигурации WireGuard

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Исправление конфигурации WireGuard...${NC}"

# 1. Остановка контейнеров
echo -e "${YELLOW}Останавливаем контейнеры...${NC}"
docker compose down

# 2. Проверка и исправление файла конфигурации WireGuard
CONFIG_FILE="./config/wg0.conf"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Исправление файла $CONFIG_FILE...${NC}"
    
    # Создаем резервную копию
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    echo -e "${GREEN}Создана резервная копия: ${CONFIG_FILE}.bak${NC}"
    
    # Удаление кавычек вокруг PrivateKey
    sed -i "s/PrivateKey = '[^']*'/PrivateKey = $(grep -oP "(?<=PrivateKey = ')[^']*(?=')" "$CONFIG_FILE")/" "$CONFIG_FILE"
    
    # Удаление кавычек вокруг PublicKey в секции [Peer]
    sed -i "s/PublicKey = '[^']*'/PublicKey = $(grep -oP "(?<=PublicKey = ')[^']*(?=')" "$CONFIG_FILE" 2>/dev/null || echo "KEY_NOT_FOUND")/" "$CONFIG_FILE"
    
    echo -e "${GREEN}Конфигурация исправлена${NC}"
else
    echo -e "${RED}Файл конфигурации $CONFIG_FILE не найден!${NC}"
    exit 1
fi

# 3. Проверка файла params
PARAMS_FILE="./config/params"
if [ -f "$PARAMS_FILE" ]; then
    echo -e "${YELLOW}Проверка файла $PARAMS_FILE...${NC}"
    
    # Создаем резервную копию
    cp "$PARAMS_FILE" "${PARAMS_FILE}.bak"
    
    # Исправление ключей, если они обернуты в кавычки
    sed -i "s/SERVER_PRIV_KEY='\([^']*\)'/SERVER_PRIV_KEY=\1/g" "$PARAMS_FILE"
    sed -i "s/SERVER_PUB_KEY='\([^']*\)'/SERVER_PUB_KEY=\1/g" "$PARAMS_FILE"
    
    echo -e "${GREEN}Файл params проверен и исправлен${NC}"
else
    echo -e "${YELLOW}Файл params не найден, продолжаем...${NC}"
fi

# 4. Создание простой конфигурации WireGuard заново
echo -e "${YELLOW}Создание новой простой конфигурации WireGuard...${NC}"

# Генерация новых ключей
TEMP_PRIV_KEY=$(wg genkey)
TEMP_PUB_KEY=$(echo "$TEMP_PRIV_KEY" | wg pubkey)

# Создание нового файла конфигурации
cat > "$CONFIG_FILE" << EOF
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 51820
PrivateKey = $TEMP_PRIV_KEY
PostUp = iptables -I INPUT -p udp --dport 51820 -j ACCEPT
PostUp = iptables -I FORWARD -i eth0 -o wg0 -j ACCEPT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = ip6tables -I FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport 51820 -j ACCEPT
PostDown = iptables -D FORWARD -i eth0 -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF

# Добавляем клиентов из исходной конфигурации
if [ -f "${CONFIG_FILE}.bak" ]; then
    echo -e "${YELLOW}Копирование информации о пирах из резервной копии...${NC}"
    
    # Извлекаем блоки [Peer] из бэкапа и добавляем их в новый файл
    grep -A 4 "\[Peer\]" "${CONFIG_FILE}.bak" | while read -r line; do
        if [[ "$line" == "--" ]]; then
            continue
        fi
        
        # Исправляем формат PublicKey, если он заключен в кавычки
        if [[ "$line" == *"PublicKey = '"* ]]; then
            # Извлекаем ключ, удаляя кавычки и возможные команды после
            KEY=$(echo "$line" | grep -oP "(?<=PublicKey = ')[^']*(?=')" | cut -d'|' -f1 | tr -d ' ')
            echo "PublicKey = $KEY" >> "$CONFIG_FILE"
        else
            echo "$line" >> "$CONFIG_FILE"
        fi
    done
fi

echo -e "${GREEN}Новый файл конфигурации WireGuard создан${NC}"

# 5. Обновление файла params
if [ -f "$PARAMS_FILE" ]; then
    echo -e "${YELLOW}Обновление файла params с новыми ключами...${NC}"
    
    # Создаем новый файл params на основе бэкапа, заменяя ключи
    grep -v "SERVER_PRIV_KEY\|SERVER_PUB_KEY" "${PARAMS_FILE}.bak" > "$PARAMS_FILE"
    echo "SERVER_PRIV_KEY=$TEMP_PRIV_KEY" >> "$PARAMS_FILE"
    echo "SERVER_PUB_KEY=$TEMP_PUB_KEY" >> "$PARAMS_FILE"
    
    echo -e "${GREEN}Файл params обновлен${NC}"
fi

# 6. Проверка прав доступа на файлах конфигурации
echo -e "${YELLOW}Установка правильных прав доступа...${NC}"
chmod 600 "$CONFIG_FILE"
if [ -f "$PARAMS_FILE" ]; then
    chmod 600 "$PARAMS_FILE"
fi

# 7. Запуск контейнеров
echo -e "${YELLOW}Запускаем контейнеры...${NC}"
docker compose up -d

echo -e "${GREEN}Проверьте логи контейнера:${NC}"
echo -e "docker compose logs"

echo -e "${YELLOW}ВНИМАНИЕ: Так как ключи были изменены, вам нужно:${NC}"
echo -e "1. Создать новых пиров с помощью API"
echo -e "2. Обновить конфигурации клиентов"
echo -e "3. Подключиться с использованием новых конфигураций"