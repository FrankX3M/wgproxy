#!/bin/bash
# Скрипт для генерации QR-кода из конфигурации WireGuard

# Проверка наличия аргументов
if [ "$#" -lt 1 ]; then
    echo "Использование: $0 <имя_пира>"
    exit 1
fi

# Имя пира
PEER_NAME="$1"
INTERFACE="${WG_INTERFACE:-wg0}"
PEER_CONFIG_DIR="${PEER_CONFIG_DIR:-/etc/wireguard/clients}"

# Путь к файлу конфигурации
CONFIG_FILE="${PEER_CONFIG_DIR}/${INTERFACE}-client-${PEER_NAME}.conf"
QR_FILE="${PEER_CONFIG_DIR}/${PEER_NAME}_qr.png"

# Проверка существования файла
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Ошибка: Файл конфигурации '$CONFIG_FILE' не найден."
    exit 1
fi

# Генерация QR-кода с помощью qrencode
echo "Генерация QR-кода для пира '$PEER_NAME'..."
if command -v qrencode &> /dev/null; then
    qrencode -t png -o "$QR_FILE" < "$CONFIG_FILE"
    if [ $? -eq 0 ]; then
        echo "QR-код успешно сохранен в '$QR_FILE'"
        chmod 644 "$QR_FILE"
    else
        echo "Ошибка при создании QR-кода."
        exit 1
    fi
else
    echo "Ошибка: qrencode не установлен. Установите пакет qrencode."
    exit 1
fi