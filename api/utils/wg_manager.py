#!/usr/bin/env python3
"""
WireGuard Manager - Утилита для управления WireGuard VPN
Основана на логике скрипта angristan/wireguard-install
"""

import os
import re
import json
import logging
import subprocess
import tempfile
from datetime import datetime

logger = logging.getLogger('wireguard-api.wg_manager')

class WireGuardManager:
    """Управляет конфигурацией и операциями WireGuard"""
    
    def __init__(self, interface='wg0', config_dir='/etc/wireguard', peer_config_dir='/etc/wireguard/clients'):
        """Инициализация с путями к конфигурации"""
        self.interface = interface
        self.config_dir = config_dir
        self.peer_config_dir = peer_config_dir
        self.config_file = os.path.join(config_dir, f"{interface}.conf")
        self.params_file = os.path.join(config_dir, "params")
        
        # Создание директорий, если они не существуют
        os.makedirs(config_dir, exist_ok=True)
        os.makedirs(peer_config_dir, exist_ok=True)
        
        # Загрузка параметров из файла
        self.params = self.load_params()
        
        # Переменные среды с значениями по умолчанию
        self.server_port = int(os.environ.get('WG_SERVER_PORT', 51820))
        self.server_ip = os.environ.get('WG_SERVER_IP', '10.66.66.1')
        self.server_ipv6 = os.environ.get('WG_SERVER_IPV6', 'fd42:42:42::1')
        self.server_dns_1 = os.environ.get('WG_DNS_1', '1.1.1.1')
        self.server_dns_2 = os.environ.get('WG_DNS_2', '1.0.0.1')
        self.allowed_ips = os.environ.get('ALLOWED_IPS', '0.0.0.0/0,::/0')
    
    def load_params(self):
        """Загрузка параметров из файла /etc/wireguard/params"""
        params = {}
        
        if os.path.exists(self.params_file):
            try:
                with open(self.params_file, 'r') as f:
                    for line in f:
                        if '=' in line:
                            key, value = line.strip().split('=', 1)
                            params[key] = value
                return params
            except Exception as e:
                logger.error(f"Ошибка при загрузке параметров: {e}")
        
        return params
    
    def _run_command(self, command, shell=False):
        """Запуск команды оболочки и возврат вывода"""
        try:
            if shell:
                # Если это команда с процессной подстановкой, используем явно bash
                if '<(' in command:
                    command = f"bash -c '{command}'"
                
                result = subprocess.run(command, shell=True, check=True, 
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True)
            else:
                result = subprocess.run(command.split(), check=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            logger.error(f"Ошибка выполнения команды: {command}")
            logger.error(f"Ошибка: {e.stderr.strip()}")
            raise RuntimeError(f"Ошибка выполнения команды: {e.stderr.strip()}")
    
    def _generate_keys(self):
        """Генерация пары ключей WireGuard"""
        try:
            # Создаем временные файлы для ключей
            with tempfile.NamedTemporaryFile(delete=False) as private_key_file:
                private_key_path = private_key_file.name
            
            with tempfile.NamedTemporaryFile(delete=False) as public_key_file:
                public_key_path = public_key_file.name
            
            with tempfile.NamedTemporaryFile(delete=False) as preshared_key_file:
                preshared_key_path = preshared_key_file.name
            
            # Генерируем ключи с сохранением во временные файлы
            self._run_command(f"wg genkey > {private_key_path}", shell=True)
            self._run_command(f"cat {private_key_path} | wg pubkey > {public_key_path}", shell=True)
            self._run_command(f"wg genpsk > {preshared_key_path}", shell=True)
            
            # Считываем ключи из файлов
            with open(private_key_path, 'r') as f:
                private_key = f.read().strip()
            
            with open(public_key_path, 'r') as f:
                public_key = f.read().strip()
            
            with open(preshared_key_path, 'r') as f:
                preshared_key = f.read().strip()
            
            # Удаляем временные файлы
            os.unlink(private_key_path)
            os.unlink(public_key_path)
            os.unlink(preshared_key_path)
            
            return private_key, public_key, preshared_key
        except Exception as e:
            logger.error(f"Ошибка при генерации ключей: {str(e)}")
            raise
    
    def _sync_wireguard_config(self):
        """Применение изменений конфигурации WireGuard без перезапуска интерфейса"""
        try:
            # Создаем временный файл со stripped конфигурацией
            temp_config = f"/tmp/wg-{self.interface}-temp.conf"
            
            # Выполняем strip конфигурации и сохраняем во временный файл
            self._run_command(f"wg-quick strip {self.interface} > {temp_config}", shell=True)
            
            # Синхронизируем конфигурацию с временным файлом
            self._run_command(f"wg syncconf {self.interface} {temp_config}", shell=True)
            
            # Удаляем временный файл
            self._run_command(f"rm -f {temp_config}", shell=True)
            
            return True
        except Exception as e:
            logger.error(f"Ошибка при синхронизации конфигурации: {str(e)}")
            return False
    
    def _get_next_available_ip(self):
        """Поиск следующего доступного IP в подсети"""
        try:
            # Извлечение базового IP из подсети (например, 10.66.66 из 10.66.66.1)
            base_ip = '.'.join(self.server_ip.split('.')[:3])
            
            # Получение всех используемых IP из конфигурации
            used_ips = set()
            
            # Добавление IP сервера
            used_ips.add(self.server_ip)
            
            # Проверка конфигурационного файла на наличие назначенных IP
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = f.read()
                    ip_matches = re.findall(r'AllowedIPs\s*=\s*([\d\.]+)/32', config)
                    for ip in ip_matches:
                        used_ips.add(ip)
            
            # Поиск следующего доступного IP
            for i in range(2, 254):  # Пропускаем .0 (сеть) и .1 (сервер)
                candidate_ip = f"{base_ip}.{i}"
                if candidate_ip not in used_ips:
                    return candidate_ip
                    
            raise RuntimeError("В подсети нет доступных IP!")
        except Exception as e:
            logger.error(f"Ошибка при поиске доступного IP: {str(e)}")
            raise
    
    def _get_next_available_ipv6(self, ipv4_suffix):
        """Получить IPv6 на основе IPv4 суффикса"""
        try:
            # Извлечение базового IPv6 из адреса сервера (например, fd42:42:42 из fd42:42:42::1)
            base_ipv6 = self.server_ipv6.split('::')[0]
            return f"{base_ipv6}::{ipv4_suffix}"
        except Exception as e:
            logger.error(f"Ошибка при генерации IPv6: {str(e)}")
            raise
    
    def initialize_server(self):
        """Инициализация конфигурации сервера WireGuard"""
        try:
            if os.path.exists(self.config_file):
                return {"success": True, "message": "Сервер уже инициализирован"}
            
            # Выполняем скрипт инициализации
            self._run_command(f"/app/scripts/init_server.sh")
            
            # Перезагружаем параметры
            self.params = self.load_params()
            
            return {
                "success": True,
                "message": "WireGuard сервер успешно инициализирован",
                "interface": self.interface,
                "public_key": self.params.get("SERVER_PUB_KEY", "unknown"),
                "server_ip": self.params.get("SERVER_WG_IPV4", self.server_ip),
                "port": int(self.params.get("SERVER_PORT", self.server_port))
            }
        except Exception as e:
            logger.error(f"Ошибка при инициализации сервера: {str(e)}")
            return {"success": False, "message": str(e)}
    
    def get_server_status(self):
        """Получение информации о статусе сервера WireGuard"""
        try:
            # Проверка, запущен ли WireGuard
            try:
                self._run_command(f"wg show {self.interface}")
                status = "active"
            except:
                status = "inactive"
            
            # Загрузка параметров, если они еще не загружены
            if not self.params:
                self.params = self.load_params()
            
            # Информация о сервере
            server_info = {
                "interface": self.interface,
                "public_key": self.params.get("SERVER_PUB_KEY", "unknown"),
                "endpoint": f"{self.params.get('SERVER_PUB_IP', 'unknown')}:{self.params.get('SERVER_PORT', self.server_port)}",
                "allowed_ips": self.allowed_ips,
                "dns": f"{self.server_dns_1},{self.server_dns_2}",
                "internal_subnet": f"{'.'.join(self.server_ip.split('.')[:3])}.0/24",
                "persistent_keepalive": "25"
            }
            
            # Подсчет пиров
            peers = self.get_peers().get('peers', [])
            
            return {
                "status": status,
                "server": server_info,
                "peers_count": len(peers),
                "version": "WireGuard API v1.0"
            }
        except Exception as e:
            logger.error(f"Ошибка при получении статуса сервера: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    def get_peers(self):
        """Получение всех пиров и активных соединений"""
        try:
            peers = []
            active_connections = []
            
            # Извлечение списка пиров из конфигурации
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = f.read()
                    
                    # Найти все блоки пиров
                    peer_blocks = re.findall(r'### Client ([^\n]+)\n\[Peer\](.*?)(?=\n\n|\n### |$)', config, re.DOTALL)
                    
                    for client_name, peer_block in peer_blocks:
                        public_key_match = re.search(r'PublicKey\s*=\s*([a-zA-Z0-9+/=]+)', peer_block)
                        allowed_ips_match = re.search(r'AllowedIPs\s*=\s*([^,\s]+)', peer_block)
                        
                        if public_key_match and allowed_ips_match:
                            public_key = public_key_match.group(1)
                            allowed_ips = allowed_ips_match.group(1)
                            
                            # Определяем номер пира из имени (если имя имеет формат peerX)
                            try:
                                peer_id = re.match(r'peer(\d+)', client_name)
                                peer_id = peer_id.group(1) if peer_id else client_name
                            except:
                                peer_id = client_name
                            
                            # Проверяем наличие файла конфигурации клиента
                            config_file = f"{self.interface}-client-{client_name}.conf"
                            config_path = os.path.join(self.peer_config_dir, config_file)
                            qr_path = os.path.join(self.peer_config_dir, f"{client_name}_qr.png")
                            
                            peer_info = {
                                "id": peer_id,
                                "name": client_name,
                                "public_key": public_key,
                                "config_file": os.path.exists(config_path),
                                "qr_code": os.path.exists(qr_path)
                            }
                            
                            peers.append(peer_info)
            
            # Получение информации об активных соединениях
            try:
                wg_output = self._run_command(f"wg show {self.interface}")
                
                current_peer = None
                endpoint = None
                latest_handshake = 0
                transfer_rx = "0"
                transfer_tx = "0"
                allowed_ips = ""
                
                for line in wg_output.splitlines():
                    line = line.strip()
                    
                    if line.startswith("peer:"):
                        # Если была информация о предыдущем пире, добавляем её
                        if current_peer:
                            # Вычисление времени с последнего рукопожатия
                            handshake_ago = 0
                            if latest_handshake > 0:
                                current_time = int(datetime.now().timestamp())
                                handshake_ago = current_time - latest_handshake
                            
                            # Определение статуса соединения
                            status = "active" if handshake_ago < 180 else "inactive"
                            
                            connection = {
                                "interface": self.interface,
                                "public_key": current_peer,
                                "endpoint": endpoint,
                                "allowed_ips": allowed_ips,
                                "last_handshake": latest_handshake,
                                "handshake_ago": handshake_ago,
                                "transfer": {
                                    "received": transfer_rx,
                                    "sent": transfer_tx
                                },
                                "status": status
                            }
                            active_connections.append(connection)
                        
                        # Начало информации о новом пире
                        current_peer = line.split("peer:")[1].strip()
                        endpoint = None
                        latest_handshake = 0
                        transfer_rx = "0"
                        transfer_tx = "0"
                        allowed_ips = ""
                    elif line.startswith("endpoint:") and current_peer:
                        endpoint = line.split("endpoint:")[1].strip()
                    elif line.startswith("allowed ips:") and current_peer:
                        allowed_ips = line.split("allowed ips:")[1].strip()
                    elif line.startswith("latest handshake:") and current_peer:
                        try:
                            latest_handshake = int(line.split("latest handshake:")[1].strip())
                        except:
                            latest_handshake = 0
                    elif line.startswith("transfer:") and current_peer:
                        try:
                            transfer_parts = line.split("transfer:")[1].strip().split("received,")
                            transfer_rx = transfer_parts[0].strip()
                            transfer_tx = transfer_parts[1].strip().split("sent")[0].strip()
                        except:
                            transfer_rx = "0"
                            transfer_tx = "0"
                
                # Добавляем последний пир
                if current_peer:
                    # Вычисление времени с последнего рукопожатия
                    handshake_ago = 0
                    if latest_handshake > 0:
                        current_time = int(datetime.now().timestamp())
                        handshake_ago = current_time - latest_handshake
                    
                    # Определение статуса соединения
                    status = "active" if handshake_ago < 180 else "inactive"
                    
                    connection = {
                        "interface": self.interface,
                        "public_key": current_peer,
                        "endpoint": endpoint,
                        "allowed_ips": allowed_ips,
                        "last_handshake": latest_handshake,
                        "handshake_ago": handshake_ago,
                        "transfer": {
                            "received": transfer_rx,
                            "sent": transfer_tx
                        },
                        "status": status
                    }
                    active_connections.append(connection)
                
            except Exception as e:
                logger.warning(f"Ошибка при получении активных соединений: {str(e)}")
            
            return {
                "peers": peers,
                "active_connections": active_connections
            }
        except Exception as e:
            logger.error(f"Ошибка при получении пиров: {str(e)}")
            return {"peers": [], "active_connections": []}
    
    def create_peer(self, peer_name, allowed_ips=None, dns=None):
        """Создание нового пира WireGuard"""
        try:
            # Создание имени пира, если не указано
            if not peer_name:
                # Определяем следующий номер пира
                existing_peers = self.get_peers().get('peers', [])
                next_id = 1
                for peer in existing_peers:
                    try:
                        peer_id = int(peer.get('id', 0))
                        if peer_id >= next_id:
                            next_id = peer_id + 1
                    except:
                        pass
                
                peer_name = f"peer{next_id}"
            
            # Проверка, существует ли пир с таким именем
            client_exists = False
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    client_exists = f"### Client {peer_name}" in f.read()
            
            if client_exists:
                return {"success": False, "message": f"Пир с именем {peer_name} уже существует"}
            
            # Загрузка параметров, если они еще не загружены
            if not self.params:
                self.params = self.load_params()
            
            # Получение следующего доступного IP
            client_ip = self._get_next_available_ip()
            ipv4_suffix = client_ip.split('.')[-1]
            client_ipv6 = self._get_next_available_ipv6(ipv4_suffix)
            
            # Использование указанных или стандартных значений
            allowed_ips = allowed_ips or self.allowed_ips
            dns = dns or f"{self.server_dns_1},{self.server_dns_2}"
            
            # Генерация ключей для клиента
            client_private_key, client_public_key, client_preshared_key = self._generate_keys()
            
            # Получение информации о сервере
            server_public_key = self.params.get("SERVER_PUB_KEY")
            server_ip = self.params.get("SERVER_PUB_IP")
            server_port = self.params.get("SERVER_PORT", self.server_port)
            endpoint = f"{server_ip}:{server_port}"
            
            # Если SERVER_PUB_IP - это IPv6, нужно добавить скобки
            if ':' in server_ip and not (server_ip.startswith('[') and server_ip.endswith(']')):
                endpoint = f"[{server_ip}]:{server_port}"
            
            # Создание файла конфигурации клиента
            client_config = f"""[Interface]
PrivateKey = {client_private_key}
Address = {client_ip}/32,{client_ipv6}/128
DNS = {dns}

[Peer]
PublicKey = {server_public_key}
PresharedKey = {client_preshared_key}
Endpoint = {endpoint}
AllowedIPs = {allowed_ips}
PersistentKeepalive = 25
"""
            
            # Сохранение конфигурации клиента
            config_path = os.path.join(self.peer_config_dir, f"{self.interface}-client-{peer_name}.conf")
            with open(config_path, 'w') as f:
                f.write(client_config)
            os.chmod(config_path, 0o600)
            
            # Добавление клиента как пира на сервере
            with open(self.config_file, 'a') as f:
                f.write(f"""
### Client {peer_name}
[Peer]
PublicKey = {client_public_key}
PresharedKey = {client_preshared_key}
AllowedIPs = {client_ip}/32,{client_ipv6}/128
""")
            
            # Применение изменений
            self._sync_wireguard_config()
            
            # Генерация QR-кода, если доступно qrencode
            qr_generated = False
            try:
                qr_path = os.path.join(self.peer_config_dir, f"{peer_name}_qr.png")
                self._run_command(f"qrencode -t png -o {qr_path} < {config_path}")
                qr_generated = True
            except Exception as e:
                logger.warning(f"Не удалось создать QR-код: {e}")
            
            return {
                "success": True,
                "message": "Пир успешно создан",
                "peer_id": peer_name.replace("peer", ""),
                "peer_name": peer_name,
                "peer_ip": client_ip,
                "peer_ipv6": client_ipv6,
                "public_key": client_public_key,
                "private_key": client_private_key,
                "preshared_key": client_preshared_key,
                "config": client_config,
                "server_endpoint": endpoint,
                "allowed_ips": allowed_ips,
                "dns": dns,
                "qr_code_generated": qr_generated
            }
        except Exception as e:
            logger.error(f"Ошибка при создании пира: {str(e)}")
            return {"success": False, "message": str(e)}
    
    def remove_peer(self, public_key):
        """Удаление пира по публичному ключу"""
        try:
            # Проверка формата публичного ключа
            if not re.match(r'^[a-zA-Z0-9+/=]{43,44}$', public_key):
                return {"success": False, "message": "Неверный формат публичного ключа"}
            
            # Поиск пира в конфигурации
            if not os.path.exists(self.config_file):
                return {"success": False, "message": "Файл конфигурации не существует"}
            
            with open(self.config_file, 'r') as f:
                config_lines = f.readlines()
            
            # Поиск блока пира
            peer_start = None
            peer_end = None
            peer_name = None
            
            for i, line in enumerate(config_lines):
                if line.strip().startswith("### Client ") and peer_start is None:
                    # Ищем ключ в следующих нескольких строках
                    for j in range(i, min(i + 5, len(config_lines))):
                        if config_lines[j].strip().startswith("PublicKey") and public_key in config_lines[j]:
                            peer_start = i
                            peer_name = line.strip().replace("### Client ", "")
                            break
                    
                    if peer_start is not None:
                        # Ищем конец блока
                        for j in range(peer_start + 1, len(config_lines)):
                            if j == len(config_lines) - 1 or (config_lines[j].strip() == "" and j > peer_start + 1):
                                peer_end = j
                                break
                        break
            
            if peer_start is None or peer_end is None:
                return {"success": False, "message": f"Пир с публичным ключом {public_key} не найден"}
            
            # Удаление блока пира из конфигурации
            new_config = config_lines[:peer_start] + (config_lines[peer_end+1:] if peer_end < len(config_lines) - 1 else [])
            
            with open(self.config_file, 'w') as f:
                f.writelines(new_config)
            
            # Применение изменений
            self._sync_wireguard_config()
            
            # Удаление файлов конфигурации клиента
            if peer_name:
                config_path = os.path.join(self.peer_config_dir, f"{self.interface}-client-{peer_name}.conf")
                qr_path = os.path.join(self.peer_config_dir, f"{peer_name}_qr.png")
                
                if os.path.exists(config_path):
                    os.remove(config_path)
                
                if os.path.exists(qr_path):
                    os.remove(qr_path)
            
            return {
                "success": True,
                "message": f"Пир с публичным ключом {public_key} успешно удален",
                "peer_name": peer_name
            }
        except Exception as e:
            logger.error(f"Ошибка при удалении пира: {str(e)}")
            return {"success": False, "message": str(e)}
    
    def restart_wireguard(self):
        """Перезапуск сервиса WireGuard"""
        try:
            # Сначала останавливаем интерфейс
            self._run_command(f"wg-quick down {self.interface}")
            
            # Затем запускаем его снова
            output = self._run_command(f"wg-quick up {self.interface}")
            
            return {
                "success": True,
                "message": "WireGuard успешно перезапущен",
                "output": output
            }
        except Exception as e:
            logger.error(f"Ошибка при перезапуске WireGuard: {str(e)}")
            return {"success": False, "message": str(e)}