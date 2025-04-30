#!/bin/bash
# Скрипт для диагностики WireGuard сервера в контейнере
# Основан на логике angristan/wireguard-install

# Цвета для вывода
RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Параметры по умолчанию
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_SERVER_PORT="${WG_SERVER_PORT:-51820}"
WG_CONFIG_DIR="${WG_CONFIG_DIR:-/etc/wireguard}"

echo -e "${BLUE}Инструмент диагностики WireGuard${NC}"
echo -e "${BLUE}===========================${NC}"

# Проверка установки WireGuard
echo -e "\n${BLUE}Проверка установки WireGuard:${NC}"
if command -v wg &> /dev/null; then
  WG_VERSION=$(wg --version)
  echo -e "${GREEN}✓ WireGuard установлен: $WG_VERSION${NC}"
else
  echo -e "${RED}✗ WireGuard не установлен${NC}"
  exit 1
fi

# Проверка модуля ядра
echo -e "\n${BLUE}Проверка модуля ядра WireGuard:${NC}"
if lsmod | grep -q wireguard; then
  echo -e "${GREEN}✓ Модуль ядра WireGuard загружен${NC}"
else
  echo -e "${ORANGE}! Модуль ядра WireGuard не загружен, проверка наличия встроенного модуля...${NC}"
  if modprobe -n wireguard &>/dev/null; then
    echo -e "${GREEN}✓ Модуль WireGuard может быть загружен${NC}"
    modprobe wireguard
  elif grep -q wireguard /lib/modules/$(uname -r)/modules.builtin 2>/dev/null; then
    echo -e "${GREEN}✓ WireGuard встроен в ядро${NC}"
  else
    echo -e "${RED}✗ Модуль ядра WireGuard недоступен${NC}"
  fi
fi

# Проверка конфигурации WireGuard
echo -e "\n${BLUE}Проверка конфигурации WireGuard:${NC}"
if [ -f "$WG_CONFIG_DIR/$WG_INTERFACE.conf" ]; then
  echo -e "${GREEN}✓ Файл конфигурации существует: $WG_CONFIG_DIR/$WG_INTERFACE.conf${NC}"
  
  # Проверка прав доступа
  CONF_PERMS=$(stat -c "%a" "$WG_CONFIG_DIR/$WG_INTERFACE.conf")
  if [ "$CONF_PERMS" = "600" ]; then
    echo -e "${GREEN}✓ Файл конфигурации имеет правильные права доступа (600)${NC}"
  else
    echo -e "${RED}✗ Файл конфигурации имеет неправильные права доступа: $CONF_PERMS (должно быть 600)${NC}"
    echo -e "${ORANGE}Исправление прав доступа...${NC}"
    chmod 600 "$WG_CONFIG_DIR/$WG_INTERFACE.conf"
  fi
  
  # Проверка наличия приватного ключа
  if grep -q "PrivateKey" "$WG_CONFIG_DIR/$WG_INTERFACE.conf"; then
    echo -e "${GREEN}✓ Приватный ключ настроен${NC}"
  else
    echo -e "${RED}✗ Приватный ключ отсутствует в конфигурации${NC}"
  fi
  
  # Проверка порта в конфигурации
  if grep -q "ListenPort" "$WG_CONFIG_DIR/$WG_INTERFACE.conf"; then
    CONFIG_PORT=$(grep "ListenPort" "$WG_CONFIG_DIR/$WG_INTERFACE.conf" | cut -d'=' -f2 | tr -d ' ')
    echo -e "${GREEN}✓ Порт прослушивания настроен: $CONFIG_PORT${NC}"
    if [ "$CONFIG_PORT" != "$WG_SERVER_PORT" ]; then
      echo -e "${ORANGE}! Порт в конфигурации ($CONFIG_PORT) отличается от переменной окружения ($WG_SERVER_PORT)${NC}"
    fi
  else
    echo -e "${RED}✗ Порт прослушивания отсутствует в конфигурации${NC}"
  fi
  
  # Проверка PostUp/PostDown в конфигурации
  if grep -q "PostUp" "$WG_CONFIG_DIR/$WG_INTERFACE.conf" && grep -q "PostDown" "$WG_CONFIG_DIR/$WG_INTERFACE.conf"; then
    echo -e "${GREEN}✓ Правила PostUp/PostDown настроены${NC}"
  else
    echo -e "${RED}✗ Правила PostUp/PostDown отсутствуют в конфигурации${NC}"
  fi
else
  echo -e "${RED}✗ Файл конфигурации не найден: $WG_CONFIG_DIR/$WG_INTERFACE.conf${NC}"
fi

# Проверка интерфейса WireGuard
echo -e "\n${BLUE}Проверка интерфейса WireGuard:${NC}"
if ip link show "$WG_INTERFACE" &> /dev/null; then
  echo -e "${GREEN}✓ Интерфейс $WG_INTERFACE существует${NC}"
  
  # Проверка состояния интерфейса
  INTERFACE_STATE=$(ip -br link show dev "$WG_INTERFACE" | awk '{print $2}')
  if [ "$INTERFACE_STATE" = "UP" ]; then
    echo -e "${GREEN}✓ Интерфейс в состоянии UP${NC}"
  else
    echo -e "${RED}✗ Интерфейс в состоянии $INTERFACE_STATE${NC}"
  fi
  
  # Проверка IP-адреса интерфейса
  INTERFACE_IP=$(ip -br addr show dev "$WG_INTERFACE" | awk '{print $3}')
  if [ -n "$INTERFACE_IP" ]; then
    echo -e "${GREEN}✓ Интерфейс имеет IP: $INTERFACE_IP${NC}"
  else
    echo -e "${RED}✗ Интерфейс не имеет IP-адреса${NC}"
  fi
else
  echo -e "${RED}✗ Интерфейс $WG_INTERFACE не существует${NC}"
fi

# Проверка пиров WireGuard
echo -e "\n${BLUE}Проверка пиров WireGuard:${NC}"
if command -v wg &> /dev/null && ip link show "$WG_INTERFACE" &> /dev/null; then
  PEER_COUNT=$(wg show "$WG_INTERFACE" peers | wc -l)
  if [ "$PEER_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Настроено пиров: $PEER_COUNT${NC}"
    
    # Проверка статуса соединений пиров
    ACTIVE_COUNT=0
    while read -r PEER; do
      if [ -n "$PEER" ]; then
        LAST_HANDSHAKE=$(wg show "$WG_INTERFACE" latest-handshakes | grep "$PEER" | awk '{print $2}')
        if [ "$LAST_HANDSHAKE" -gt 0 ]; then
          HANDSHAKE_AGE=$(($(date +%s) - LAST_HANDSHAKE))
          if [ "$HANDSHAKE_AGE" -lt 180 ]; then
            ((ACTIVE_COUNT++))
          fi
        fi
      fi
    done < <(wg show "$WG_INTERFACE" peers)
    
    echo -e "${GREEN}✓ Активных пиров: $ACTIVE_COUNT (рукопожатие в последние 3 минуты)${NC}"
  else
    echo -e "${ORANGE}! Пиров не настроено${NC}"
  fi
else
  echo -e "${RED}✗ Невозможно проверить пиры (WireGuard не установлен или интерфейс не поднят)${NC}"
fi

# Проверка UDP-порта
echo -e "\n${BLUE}Проверка UDP-порта:${NC}"
if command -v netstat &> /dev/null; then
  if netstat -lnu | grep -q ":$WG_SERVER_PORT\s"; then
    echo -e "${GREEN}✓ UDP порт $WG_SERVER_PORT открыт${NC}"
  else
    echo -e "${RED}✗ UDP порт $WG_SERVER_PORT не открыт${NC}"
  fi
elif command -v ss &> /dev/null; then
  if ss -lnu | grep -q ":$WG_SERVER_PORT\s"; then
    echo -e "${GREEN}✓ UDP порт $WG_SERVER_PORT открыт${NC}"
  else
    echo -e "${RED}✗ UDP порт $WG_SERVER_PORT не открыт${NC}"
  fi
else
  echo -e "${ORANGE}! Невозможно проверить UDP-порт (netstat/ss не установлены)${NC}"
fi

# Проверка IP forwarding
echo -e "\n${BLUE}Проверка IP forwarding:${NC}"
IP4_FORWARD=$(sysctl -n net.ipv4.ip_forward)
IP6_FORWARD=$(sysctl -n net.ipv6.conf.all.forwarding)

if [ "$IP4_FORWARD" -eq 1 ]; then
  echo -e "${GREEN}✓ IPv4 forwarding включен${NC}"
else
  echo -e "${RED}✗ IPv4 forwarding отключен${NC}"
  echo -e "${ORANGE}Включение IPv4 forwarding...${NC}"
  sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/wg.conf
  sysctl --system
fi

if [ "$IP6_FORWARD" -eq 1 ]; then
  echo -e "${GREEN}✓ IPv6 forwarding включен${NC}"
else
  echo -e "${ORANGE}! IPv6 forwarding отключен${NC}"
  echo -e "${ORANGE}Включение IPv6 forwarding...${NC}"
  sysctl -w net.ipv6.conf.all.forwarding=1
  echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/wg.conf
  sysctl --system
fi

# Проверка правил iptables/NAT
echo -e "\n${BLUE}Проверка правил firewall/NAT:${NC}"
if command -v iptables &> /dev/null; then
  # Проверка правил MASQUERADE
  if iptables -t nat -L POSTROUTING | grep -q MASQUERADE; then
    echo -e "${GREEN}✓ Правило IPv4 NAT (MASQUERADE) существует${NC}"
  else
    echo -e "${RED}✗ Правило IPv4 NAT (MASQUERADE) отсутствует${NC}"
    echo -e "${ORANGE}Добавление правила MASQUERADE...${NC}"
    PUBLIC_INTERFACE=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
    iptables -t nat -A POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE
  fi
  
  # Проверка правил FORWARD для интерфейса WireGuard
  if iptables -L FORWARD | grep -q "$WG_INTERFACE"; then
    echo -e "${GREEN}✓ Правило IPv4 FORWARD для $WG_INTERFACE существует${NC}"
  else
    echo -e "${RED}✗ Правило IPv4 FORWARD для $WG_INTERFACE отсутствует${NC}"
    echo -e "${ORANGE}Добавление правила FORWARD...${NC}"
    iptables -I FORWARD -i $WG_INTERFACE -j ACCEPT
  fi
  
  # Проверка UDP-порта в цепочке INPUT
  if iptables -L INPUT | grep -q "udp dpt:$WG_SERVER_PORT"; then
    echo -e "${GREEN}✓ Правило IPv4 INPUT для UDP порта $WG_SERVER_PORT существует${NC}"
  else
    echo -e "${ORANGE}! Правило IPv4 INPUT для UDP порта $WG_SERVER_PORT отсутствует (может быть разрешено политикой по умолчанию)${NC}"
    echo -e "${ORANGE}Добавление правила INPUT...${NC}"
    iptables -I INPUT -p udp --dport $WG_SERVER_PORT -j ACCEPT
  fi
else
  echo -e "${ORANGE}! Невозможно проверить правила firewall (iptables не установлен)${NC}"
fi

echo -e "\n${BLUE}Итоги диагностики:${NC}"
echo -e "${GREEN}Проверка установки и конфигурации WireGuard завершена.${NC}"
echo -e "${ORANGE}Проверьте вывод выше на наличие предупреждений или ошибок.${NC}"
echo -e "${BLUE}Для получения более подробной информации о соединениях выполните: wg show${NC}"
echo -e "${BLUE}Для проверки конфигурации интерфейса: wg showconf ${WG_INTERFACE}${NC}"