#!/bin/bash
# Скрипт перезапуска WireGuard VPN сервера

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

echo -e "${GREEN}Перезапуск WireGuard VPN сервера...${NC}"

# Остановка контейнеров
echo -e "${YELLOW}Остановка контейнеров...${NC}"
docker compose down

# Небольшая пауза
sleep 3

# Обновление IP forwarding для уверенности
echo -e "${YELLOW}Проверка IP forwarding...${NC}"
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

# Запуск контейнеров
echo -e "${YELLOW}Запуск контейнеров...${NC}"
docker compose up -d

# Проверка статуса запуска
if [ $? -eq 0 ]; then
  echo -e "${GREEN}WireGuard VPN сервер успешно перезапущен!${NC}"
  
  # Получение IP-адреса сервера
  SERVER_IP=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
  if [ -n "$SERVER_IP" ]; then
    echo -e "${GREEN}API доступен по адресу: http://${SERVER_IP}:5000${NC}"
    echo -e "${GREEN}Веб-интерфейс доступен по адресу: http://${SERVER_IP}:8080${NC}"
  else
    echo -e "${GREEN}API доступен по адресу: http://<ваш_IP>:5000${NC}"
    echo -e "${GREEN}Веб-интерфейс доступен по адресу: http://<ваш_IP>:8080${NC}"
  fi
else
  echo -e "${RED}Ошибка при перезапуске WireGuard VPN сервера.${NC}"
  echo -e "${YELLOW}Проверьте логи:${NC}"
  echo -e "  docker compose logs -f"
fi