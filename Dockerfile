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

# Делаем скрипт исполняемым
COPY start.sh /app/start.sh
RUN chmod +x start.sh /app/scripts/*.sh

# Открываем порты
EXPOSE 51820/udp
EXPOSE 5000/tcp

# Запускаем сервисы
CMD ["/app/start.sh"]
