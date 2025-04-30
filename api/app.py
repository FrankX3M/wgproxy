#!/usr/bin/env python3
"""
WireGuard API - RESTful API для управления WireGuard VPN сервером
Реализация основана на логике скрипта angristan/wireguard-install
"""

import os
import json
import logging
import time
from flask import Flask, request, jsonify, send_file, abort
from flask_cors import CORS
from werkzeug.utils import secure_filename
from utils.wg_manager import WireGuardManager

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Инициализация Flask
app = Flask(__name__)
CORS(app)

# Переменные окружения со значениями по умолчанию
WG_INTERFACE = os.environ.get('WG_INTERFACE', 'wg0')
WG_CONFIG_DIR = os.environ.get('WG_CONFIG_DIR', '/etc/wireguard')
PEER_CONFIG_DIR = os.environ.get('PEER_CONFIG_DIR', '/etc/wireguard/clients')
API_HOST = os.environ.get('API_HOST', '0.0.0.0')
API_PORT = int(os.environ.get('API_PORT', 5000))

# Инициализация менеджера WireGuard
wg_manager = WireGuardManager(
    interface=WG_INTERFACE,
    config_dir=WG_CONFIG_DIR,
    peer_config_dir=PEER_CONFIG_DIR
)

# Создание необходимых директорий
os.makedirs(PEER_CONFIG_DIR, exist_ok=True)

@app.route('/health', methods=['GET'])
def health_check():
    """Проверка работоспособности API"""
    return jsonify({
        "status": "ok",
        "service": "wireguard-api"
    })

@app.route('/status', methods=['GET'])
def get_status():
    """Получение статуса сервера WireGuard"""
    try:
        status = wg_manager.get_server_status()
        return jsonify(status)
    except Exception as e:
        logger.error(f"Ошибка при получении статуса: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/peers', methods=['GET'])
def get_peers():
    """Получение списка всех пиров и активных соединений"""
    try:
        peers = wg_manager.get_peers()
        return jsonify(peers)
    except Exception as e:
        logger.error(f"Ошибка при получении пиров: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/create', methods=['POST'])
def create_peer():
    """Создание нового пира WireGuard"""
    try:
        data = request.json or {}
        peer_name = data.get('name')
        
        # Генерация имени пира, если не указано
        if not peer_name:
            existing_peers = wg_manager.get_peers().get('peers', [])
            peer_count = len(existing_peers) + 1
            peer_name = f"peer{peer_count}"
        
        # Дополнительные параметры
        allowed_ips = data.get('allowed_ips')
        dns = data.get('dns')
        
        # Создание пира
        result = wg_manager.create_peer(
            peer_name=peer_name,
            allowed_ips=allowed_ips,
            dns=dns
        )
        
        return jsonify(result)
    except Exception as e:
        logger.error(f"Ошибка при создании пира: {str(e)}")
        return jsonify({"error": str(e), "success": False}), 500

@app.route('/restart', methods=['POST'])
def restart_wireguard():
    """Перезапуск сервиса WireGuard"""
    try:
        result = wg_manager.restart_wireguard()
        return jsonify(result)
    except Exception as e:
        logger.error(f"Ошибка при перезапуске WireGuard: {str(e)}")
        return jsonify({"error": str(e), "success": False}), 500

@app.route('/remove/<pubkey>', methods=['DELETE'])
def remove_peer(pubkey):
    """Удаление пира по публичному ключу"""
    try:
        result = wg_manager.remove_peer(pubkey)
        return jsonify(result)
    except Exception as e:
        logger.error(f"Ошибка при удалении пира: {str(e)}")
        return jsonify({"error": str(e), "success": False}), 500

@app.route('/download/<peer_name>', methods=['GET'])
def download_config(peer_name):
    """Скачивание конфигурационного файла пира"""
    try:
        # Защита от атак через пути
        peer_name = secure_filename(peer_name)
        
        # Поиск конфигурационного файла
        config_path = os.path.join(PEER_CONFIG_DIR, f"{WG_INTERFACE}-client-{peer_name}.conf")
        
        if not os.path.exists(config_path):
            abort(404, description=f"Конфигурация для {peer_name} не найдена")
            
        return send_file(
            config_path,
            mimetype='text/plain',
            as_attachment=True,
            download_name=f"{peer_name}.conf"
        )
    except Exception as e:
        logger.error(f"Ошибка при скачивании конфигурации: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/download_qr/<peer_name>', methods=['GET'])
def download_qr(peer_name):
    """Скачивание QR-кода для пира"""
    try:
        # Защита от атак через пути
        peer_name = secure_filename(peer_name)
        
        # Поиск файла QR-кода
        qr_path = os.path.join(PEER_CONFIG_DIR, f"{peer_name}_qr.png")
        
        if not os.path.exists(qr_path):
            # Попытка создать QR-код, если файл конфигурации существует
            config_path = os.path.join(PEER_CONFIG_DIR, f"{WG_INTERFACE}-client-{peer_name}.conf")
            if os.path.exists(config_path):
                try:
                    os.system(f"qrencode -t png -o {qr_path} < {config_path}")
                except:
                    abort(404, description=f"QR-код для {peer_name} не может быть создан")
            else:
                abort(404, description=f"QR-код для {peer_name} не найден")
                
        return send_file(
            qr_path,
            mimetype='image/png',
            as_attachment=True,
            download_name=f"{peer_name}_qr.png"
        )
    except Exception as e:
        logger.error(f"Ошибка при скачивании QR-кода: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Проверка инициализации сервера
    server_config_path = os.path.join(WG_CONFIG_DIR, f"{WG_INTERFACE}.conf")
    if not os.path.exists(server_config_path):
        logger.info("Конфигурация сервера не найдена. Инициализация WireGuard сервера...")
        result = wg_manager.initialize_server()
        if result.get('success'):
            logger.info("WireGuard сервер успешно инициализирован")
        else:
            logger.error(f"Ошибка инициализации WireGuard сервера: {result.get('message')}")
            exit(1)
    
    # Запуск API сервера
    logger.info(f"Запуск WireGuard API на {API_HOST}:{API_PORT}")
    app.run(host=API_HOST, port=API_PORT)