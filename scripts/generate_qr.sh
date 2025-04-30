#!/bin/bash
# Скрипт для генерации QR-кода из конфигурации WireGuard

# Проверка наличия аргументов
if [ "$#" -lt 1 ]; then
    echo "Использование: $0 <имя_пира>"
    exit 1
fi

# Определение текущей директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Имя пира
PEER_NAME="$1"
INTERFACE="${WG_INTERFACE:-wg0}"

# Автоматическое определение директории клиентских конфигураций
# Сначала проверяем переданную переменную окружения
if [ -n "$PEER_CONFIG_DIR" ]; then
    # Используем переданную переменную окружения
    CONFIG_DIR="$PEER_CONFIG_DIR"
elif [ -d "/etc/wireguard/clients" ]; then
    # Внутри контейнера
    CONFIG_DIR="/etc/wireguard/clients"
elif [ -d "$PROJECT_ROOT/config/clients" ]; then
    # На хост-системе, стандартный путь проекта
    CONFIG_DIR="$PROJECT_ROOT/config/clients"
else
    # Резервный вариант - относительный путь от скрипта
    CONFIG_DIR="$PROJECT_ROOT/config/clients"
    # Создаем директорию, если она не существует
    mkdir -p "$CONFIG_DIR"
fi

# Путь к файлу конфигурации
CONFIG_FILE="$CONFIG_DIR/${INTERFACE}-client-${PEER_NAME}.conf"
QR_FILE="$CONFIG_DIR/${PEER_NAME}_qr.png"

echo "Используемые пути:"
echo "Директория конфигураций: $CONFIG_DIR"
echo "Файл конфигурации: $CONFIG_FILE"
echo "Файл QR-кода: $QR_FILE"

# Проверка существования файла
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Ошибка: Файл конфигурации '$CONFIG_FILE' не найден."
    # Проверяем наличие файлов в директории
    echo "Доступные файлы конфигураций в директории $CONFIG_DIR:"
    ls -la "$CONFIG_DIR"
    exit 1
fi

# Проверка наличия qrencode
if ! command -v qrencode &> /dev/null; then
    echo "qrencode не установлен. Попытка установки..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y qrencode
    elif command -v yum &> /dev/null; then
        yum install -y qrencode
    else
        echo "Ошибка: Не удалось установить qrencode. Пожалуйста, установите его вручную."
        exit 1
    fi
fi

# Генерация QR-кода с помощью qrencode
echo "Генерация QR-кода для пира '$PEER_NAME'..."
qrencode -t png -o "$QR_FILE" < "$CONFIG_FILE"

if [ $? -eq 0 ]; then
    echo "QR-код успешно сохранен в '$QR_FILE'"
    chmod 644 "$QR_FILE"
    
    # Проверяем, есть ли утилита для отображения QR-кода в терминале
    if command -v display &> /dev/null; then
        echo "Попытка отобразить QR-код (если на сервере есть графический интерфейс)..."
        display "$QR_FILE" &
    elif command -v qrencode &> /dev/null; then
        echo "QR-код в текстовом виде (для графических терминалов):"
        qrencode -t ANSIUTF8 < "$CONFIG_FILE"
    fi
    
    echo "Вы можете скачать QR-код через API:"
    echo "curl -o ${PEER_NAME}_qr.png http://ВАША-IP-АДРЕС:5000/download_qr/${PEER_NAME}"
    echo "Или использовать веб-интерфейс: http://ВАША-IP-АДРЕС:8080"
else
    echo "Ошибка при создании QR-кода."
    exit 1
fi