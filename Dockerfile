FROM debian:11

# Установка необходимых пакетов
RUN apt-get update
RUN apt-get install -y \
    wireguard \
    iptables \
    openresolv \
    qrencode \
    iproute2 \
    procps \
    net-tools \
    curl \
    python3 \
    python3-pip \
    python3-setuptools \
    kmod \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Создание необходимых директорий
RUN mkdir -p /etc/wireguard && \
    chmod 700 /etc/wireguard

# Копирование файлов
WORKDIR /app
COPY api/requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Копирование скриптов инициализации и API
COPY scripts/ /app/scripts/
COPY api/ /app/api/
COPY api/utils/ /app/utils/

# Копирование дополнительных скриптов
COPY scripts/check-client-config.sh /app/scripts/
COPY scripts/fix-forwarding.sh /app/scripts/

# Копирование скрипта для исправления дублированных ключей
RUN echo '#!/bin/bash\n\
# Скрипт для исправления дублированных ключей в конфигурации WireGuard\n\
CONFIG_FILE="/etc/wireguard/wg0.conf"\n\
\n\
if [ -f "$CONFIG_FILE" ]; then\n\
    # Проверка на дублированные ключи\n\
    if grep -q "PrivateKey.*=.*=.*=" "$CONFIG_FILE"; then\n\
        echo "Обнаружен дублированный PrivateKey, исправление..."\n\
        # Извлечение первого ключа\n\
        FIRST_KEY=$(grep "PrivateKey" "$CONFIG_FILE" | sed -E "s/PrivateKey *= *([a-zA-Z0-9+\/=]+).*/\\1/" | cut -d"=" -f1)\n\
        # Исправление\n\
        sed -i "s|PrivateKey *=.*$|PrivateKey = $FIRST_KEY|" "$CONFIG_FILE"\n\
        echo "PrivateKey исправлен"\n\
    fi\n\
\n\
    # Исправление для пиров\n\
    PEER_SECTIONS=$(grep -n "\\[Peer\\]" "$CONFIG_FILE" | cut -d ":" -f1)\n\
    \n\
    for LINE_NUM in $PEER_SECTIONS; do\n\
        # Определение блока пира\n\
        NEXT_PEER=$(grep -n "\\[Peer\\]" "$CONFIG_FILE" | awk -v line="$LINE_NUM" "$1 > line {print $1; exit}")\n\
        \n\
        if [ -z "$NEXT_PEER" ]; then\n\
            END_LINE=$(wc -l "$CONFIG_FILE" | awk "{print $1}")\n\
        else\n\
            END_LINE=$((NEXT_PEER - 1))\n\
        fi\n\
        \n\
        # Проверка PublicKey\n\
        PEER_BLOCK=$(sed -n "${LINE_NUM},${END_LINE}p" "$CONFIG_FILE")\n\
        if echo "$PEER_BLOCK" | grep -q "PublicKey.*=.*=.*="; then\n\
            echo "Исправление дублированного PublicKey для пира..."\n\
            PEER_KEY=$(echo "$PEER_BLOCK" | grep "PublicKey" | sed -E "s/PublicKey *= *([a-zA-Z0-9+\/=]+).*/\\1/" | cut -d"=" -f1)\n\
            sed -i "${LINE_NUM},${END_LINE}s|PublicKey *=.*$|PublicKey = $PEER_KEY|" "$CONFIG_FILE"\n\
        fi\n\
        \n\
        # Проверка PresharedKey\n\
        if echo "$PEER_BLOCK" | grep -q "PresharedKey.*=.*=.*="; then\n\
            echo "Исправление дублированного PresharedKey для пира..."\n\
            PEER_KEY=$(echo "$PEER_BLOCK" | grep "PresharedKey" | sed -E "s/PresharedKey *= *([a-zA-Z0-9+\/=]+).*/\\1/" | cut -d"=" -f1)\n\
            sed -i "${LINE_NUM},${END_LINE}s|PresharedKey *=.*$|PresharedKey = $PEER_KEY|" "$CONFIG_FILE"\n\
        fi\n\
    done\n\
    \n\
    echo "Проверка и исправление дублированных ключей завершены"\n\
else\n\
    echo "Файл конфигурации $CONFIG_FILE не найден"\n\
fi' > /app/scripts/fix-duplicated-keys.sh

# Установка переменных окружения
ENV WG_CONFIG_DIR=/etc/wireguard
ENV WG_INTERFACE=wg0
ENV WG_SERVER_PORT=51820
ENV WG_SERVER_IP=10.66.66.1
ENV WG_SERVER_SUBNET=10.66.66.0/24
ENV WG_SERVER_IPV6=fd42:42:42::1
ENV WG_IPV6_SUBNET=fd42:42:42::/64
ENV WG_DNS_1=1.1.1.1
ENV WG_DNS_2=1.0.0.1
ENV ALLOWED_IPS="0.0.0.0/0,::/0"
ENV API_PORT=5000
ENV API_HOST=0.0.0.0

# Делаем скрипты исполняемыми
COPY start.sh /app/start.sh
RUN chmod +x start.sh /app/scripts/*.sh

# Открываем порты
EXPOSE 51820/udp
EXPOSE 5000/tcp

# Запускаем сервисы
CMD ["/app/start.sh"]