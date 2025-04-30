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
