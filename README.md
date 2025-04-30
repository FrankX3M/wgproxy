# WireGuard VPN Server с REST API и веб-интерфейсом

Проект представляет собой готовое решение для развертывания WireGuard VPN сервера с RESTful API и веб-интерфейсом управления в Docker-контейнере.

## Особенности

- ✅ Простая установка и настройка через Docker
- ✅ RESTful API для управления пирами
- ✅ Веб-интерфейс для управления VPN-соединениями
- ✅ Генерация QR-кодов для быстрого подключения с мобильных устройств
- ✅ Поддержка IPv4 и IPv6
- ✅ Минимальные системные требования

## Системные требования

- Linux-сервер (Ubuntu, Debian, CentOS и др.)
- Поддержка модуля WireGuard в ядре ОС
- Docker и Docker Compose
- Открытые порты:
  - 51820/udp (WireGuard)
  - 5000/tcp (API)
  - 8080/tcp (Веб-интерфейс)

## Установка

### 1. Клонирование репозитория

```bash
git clone https://github.com/FrankX3M/wgproxy.git
cd wireguard-api

### 2. Настройка прав доступа для скриптов

```bash
chmod +x prepare_host.sh run.sh restart.sh
```

### 3. Запуск сервера

```bash
sudo ./run.sh
```

Скрипт автоматически:
- Подготовит хост-систему для запуска WireGuard
- Настроит необходимые параметры ядра
- Соберет и запустит Docker-контейнеры

### 4. Проверка статуса

```bash
docker compose ps
```

## Использование
curl -X POST http://5.180.137.197:5000/create \
  -H "Content-Type: application/json" \
  -d '{"name":"my-device", "allowed_ips":"0.0.0.0/0,::/0", "dns":"1.1.1.1,8.8.8.8"}'

curl http://5.180.137.197:5000/download/my-device

curl -o my-device2_qr.png http://5.180.137.197:5000/download_qr/my-device
curl -o my-device2_qr.png http://5.180.137.197:5000/download_qr/my-device

### Веб-интерфейс

Веб-интерфейс доступен по адресу:
```
http://<IP-адрес-сервера>:8080
```

С помощью веб-интерфейса вы можете:
- Просматривать статус сервера WireGuard
- Создавать новых пиров (клиентов)
- Скачивать файлы конфигурации и QR-коды
- Удалять пиров
- Перезапускать WireGuard-сервер

### REST API

API доступен по адресу:
```
http://<IP-адрес-сервера>:5000
```

#### Основные эндпоинты API:

| Метод | Эндпоинт | Описание |
|-------|----------|----------|
| GET | /health | Проверка работоспособности API |
| GET | /status | Получение статуса сервера WireGuard |
| GET | /peers | Получение списка всех пиров |
| POST | /create | Создание нового пира |
| POST | /restart | Перезапуск сервиса WireGuard |
| DELETE | /remove/\<pubkey\> | Удаление пира по публичному ключу |
| GET | /download/\<peer_name\> | Скачивание конфигурационного файла |
| GET | /download_qr/\<peer_name\> | Скачивание QR-кода для пира |

#### Пример создания нового пира через API:

```bash
curl -X POST http://<IP-адрес-сервера>:5000/create \
  -H "Content-Type: application/json" \
  -d '{"name":"my-phone", "allowed_ips":"0.0.0.0/0,::/0", "dns":"1.1.1.1,8.8.8.8"}'
```

## Управление сервером

### Перезапуск сервера

```bash
sudo ./restart.sh
```

### Остановка сервера

```bash
docker compose down
```

### Просмотр логов

```bash
docker compose logs -f
```

### Проверка состояния WireGuard в контейнере

```bash
docker exec -it wireguard-server wg show
```

## Устранение неполадок

### 1. Проблема с IP forwarding

Если возникает ошибка при запуске контейнера:
```
Error response from daemon: failed to create task for container: failed to create shim task: OCI runtime create failed: runc create failed: sysctl "net.ipv4.ip_forward" not allowed in host network namespace: unknown
```

Решение:
- Запустите скрипт подготовки хоста: `sudo ./prepare_host.sh`
- Или вручную установите параметры ядра:
  ```bash
  sudo sysctl -w net.ipv4.ip_forward=1
  sudo sysctl -w net.ipv6.conf.all.forwarding=1
  ```

### 2. Проблемы с DNS в клиентах

Если у клиентов проблемы с DNS:
- Проверьте значения DNS в настройках Docker Compose
- Попробуйте альтернативные DNS, например:
  - Google: `8.8.8.8, 8.8.4.4`
  - Cloudflare: `1.1.1.1, 1.0.0.1`
  - Quad9: `9.9.9.9`

### 3. Контейнер запускается, но WireGuard не работает

Выполните диагностику внутри контейнера:
```bash
docker exec -it wireguard-server /app/scripts/check_wg.sh
```

## Архитектура проекта

```
wireguard-api/
├── api/
│   ├── app.py                # Основной файл API
│   ├── requirements.txt      # Зависимости Python
│   └── utils/
│       ├── __init__.py
│       └── wg_manager.py     # Класс для управления WireGuard
├── config/                   # Директория с конфигурацией WireGuard
├── scripts/
│   ├── check_wg.sh           # Скрипт для диагностики
│   ├── generate_qr.sh        # Генерация QR-кодов
│   └── init_server.sh        # Инициализация сервера
├── ui/                       # Веб-интерфейс
│   ├── css/
│   ├── js/
│   └── index.html
├── Dockerfile                # Сборка образа Docker
├── docker-compose.yml        # Конфигурация Docker Compose
├── prepare_host.sh           # Подготовка хоста
├── restart.sh                # Перезапуск сервера
├── run.sh                    # Основной скрипт запуска
└── start.sh                  # Скрипт запуска внутри контейнера
```

## Безопасность

1. **Не выставляйте API в публичную сеть без дополнительной защиты**
2. Рекомендуется настроить HTTPS для API и веб-интерфейса
3. Настройте ограничения доступа через файрвол
4. Регулярно обновляйте контейнеры и хост-систему

## Лицензия

MIT
