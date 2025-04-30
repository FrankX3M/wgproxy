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
chmod 700 ./config

echo -e "${GREEN}Система подготовлена для запуска WireGuard в Docker${NC}"
echo -e "${YELLOW}Теперь вы можете запустить контейнеры:${NC}"
echo -e "  docker compose up -d"
