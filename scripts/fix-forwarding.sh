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
