#!/bin/bash
# Скрипт запуска WireGuard VPN сервера в Docker

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

echo -e "${GREEN}Запуск WireGuard VPN сервера...${NC}"

# Запуск скрипта подготовки хоста
if [ -f "./prepare_host.sh" ]; then
  echo -e "${YELLOW}Выполнение подготовки хоста...${NC}"
  bash ./prepare_host.sh
else
  echo -e "${RED}Скрипт подготовки хоста не найден. Пожалуйста, убедитесь, что файл prepare_host.sh существует.${NC}"
  exit 1
fi

# Проверка наличия docker-compose.yml
if [ ! -f "./docker-compose.yml" ]; then
  echo -e "${RED}Файл docker-compose.yml не найден. Убедитесь, что вы находитесь в правильной директории.${NC}"
  exit 1
fi

# Сборка и запуск контейнеров
echo -e "${YELLOW}Сборка и запуск контейнеров...${NC}"
docker compose build --no-cache
docker compose up -d

# Проверка статуса запуска
if [ $? -eq 0 ]; then
  echo -e "${GREEN}WireGuard VPN сервер успешно запущен!${NC}"
  echo -e "${GREEN}API доступен по адресу: http://<ваш_IP>:5000${NC}"
  echo -e "${GREEN}Веб-интерфейс доступен по адресу: http://<ваш_IP>:8080${NC}"
  
  # Получение IP-адреса сервера
  SERVER_IP=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
  if [ -n "$SERVER_IP" ]; then
    echo -e "${GREEN}API доступен по адресу: http://${SERVER_IP}:5000${NC}"
    echo -e "${GREEN}Веб-интерфейс доступен по адресу: http://${SERVER_IP}:8080${NC}"
  fi
  
  echo -e "${YELLOW}Для проверки статуса контейнеров выполните:${NC}"
  echo -e "  docker compose ps"
  echo -e "${YELLOW}Для просмотра логов:${NC}"
  echo -e "  docker compose logs -f"
  echo -e "${YELLOW}Для остановки сервиса:${NC}"
  echo -e "  docker compose down"
else
  echo -e "${RED}Ошибка при запуске WireGuard VPN сервера.${NC}"
  echo -e "${YELLOW}Проверьте логи:${NC}"
  echo -e "  docker compose logs -f"
fi