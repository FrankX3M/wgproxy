# #!/usr/bin/env python3
# """
# WireGuard API - RESTful API для управления WireGuard VPN сервером
# Реализация основана на логике скрипта angristan/wireguard-install
# """

# import os
# import json
# import logging
# import time
# from flask import Flask, request, jsonify, send_file, abort
# from flask_cors import CORS
# from werkzeug.utils import secure_filename
# from utils.wg_manager import WireGuardManager

# # Настройка логирования
# logging.basicConfig(
#     level=logging.INFO,
#     format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
# )
# logger = logging.getLogger(__name__)

# # Инициализация Flask
# app = Flask(__name__)
# CORS(app)

# # Переменные окружения со значениями по умолчанию
# WG_INTERFACE = os.environ.get('WG_INTERFACE', 'wg0')
# WG_CONFIG_DIR = os.environ.get('WG_CONFIG_DIR', '/etc/wireguard')
# PEER_CONFIG_DIR = os.environ.get('PEER_CONFIG_DIR', '/etc/wireguard/clients')
# API_HOST = os.environ.get('API_HOST', '0.0.0.0')
# API_PORT = int(os.environ.get('API_PORT', 5000))

# # Инициализация менеджера WireGuard
# wg_manager = WireGuardManager(
#     interface=WG_INTERFACE,
#     config_dir=WG_CONFIG_DIR,
#     peer_config_dir=PEER_CONFIG_DIR
# )

# # Создание необходимых директорий
# os.makedirs(PEER_CONFIG_DIR, exist_ok=True)

# @app.route('/health', methods=['GET'])
# def health_check():
#     """Проверка работоспособности API"""
#     return jsonify({
#         "status": "ok",
#         "service": "wireguard-api"
#     })

# @app.route('/status', methods=['GET'])
# def get_status():
#     """Получение статуса сервера WireGuard"""
#     try:
#         status = wg_manager.get_server_status()
#         return jsonify(status)
#     except Exception as e:
#         logger.error(f"Ошибка при получении статуса: {str(e)}")
#         return jsonify({"error": str(e)}), 500

# @app.route('/peers', methods=['GET'])
# def get_peers():
#     """Получение списка всех пиров и активных соединений"""
#     try:
#         peers = wg_manager.get_peers()
#         return jsonify(peers)
#     except Exception as e:
#         logger.error(f"Ошибка при получении пиров: {str(e)}")
#         return jsonify({"error": str(e)}), 500

# @app.route('/create', methods=['POST'])
# def create_peer():
#     """Создание нового пира WireGuard"""
#     try:
#         data = request.json or {}
#         peer_name = data.get('name')
        
#         # Генерация имени пира, если не указано
#         if not peer_name:
#             existing_peers = wg_manager.get_peers().get('peers', [])
#             peer_count = len(existing_peers) + 1
#             peer_name = f"peer{peer_count}"
        
#         # Дополнительные параметры
#         allowed_ips = data.get('allowed_ips')
#         dns = data.get('dns')
        
#         # Создание пира
#         result = wg_manager.create_peer(
#             peer_name=peer_name,
#             allowed_ips=allowed_ips,
#             dns=dns
#         )
        
#         return jsonify(result)
#     except Exception as e:
#         logger.error(f"Ошибка при создании пира: {str(e)}")
#         return jsonify({"error": str(e), "success": False}), 500

# @app.route('/restart', methods=['POST'])
# def restart_wireguard():
#     """Перезапуск сервиса WireGuard"""
#     try:
#         result = wg_manager.restart_wireguard()
#         return jsonify(result)
#     except Exception as e:
#         logger.error(f"Ошибка при перезапуске WireGuard: {str(e)}")
#         return jsonify({"error": str(e), "success": False}), 500

# @app.route('/remove/<pubkey>', methods=['DELETE'])
# def remove_peer(pubkey):
#     """Удаление пира по публичному ключу"""
#     try:
#         result = wg_manager.remove_peer(pubkey)
#         return jsonify(result)
#     except Exception as e:
#         logger.error(f"Ошибка при удалении пира: {str(e)}")
#         return jsonify({"error": str(e), "success": False}), 500

# @app.route('/download/<peer_name>', methods=['GET'])
# def download_config(peer_name):
#     """Скачивание конфигурационного файла пира"""
#     try:
#         # Защита от атак через пути
#         peer_name = secure_filename(peer_name)
        
#         # Поиск конфигурационного файла
#         config_path = os.path.join(PEER_CONFIG_DIR, f"{WG_INTERFACE}-client-{peer_name}.conf")
        
#         if not os.path.exists(config_path):
#             abort(404, description=f"Конфигурация для {peer_name} не найдена")
            
#         return send_file(
#             config_path,
#             mimetype='text/plain',
#             as_attachment=True,
#             download_name=f"{peer_name}.conf"
#         )
#     except Exception as e:
#         logger.error(f"Ошибка при скачивании конфигурации: {str(e)}")
#         return jsonify({"error": str(e)}), 500

# @app.route('/download_qr/<peer_name>', methods=['GET'])
# def download_qr(peer_name):
#     """Скачивание QR-кода для пира"""
#     try:
#         # Защита от атак через пути
#         peer_name = secure_filename(peer_name)
        
#         # Поиск файла QR-кода
#         qr_path = os.path.join(PEER_CONFIG_DIR, f"{peer_name}_qr.png")
        
#         if not os.path.exists(qr_path):
#             # Попытка создать QR-код, если файл конфигурации существует
#             config_path = os.path.join(PEER_CONFIG_DIR, f"{WG_INTERFACE}-client-{peer_name}.conf")
#             if os.path.exists(config_path):
#                 try:
#                     os.system(f"qrencode -t png -o {qr_path} < {config_path}")
#                 except:
#                     abort(404, description=f"QR-код для {peer_name} не может быть создан")
#             else:
#                 abort(404, description=f"QR-код для {peer_name} не найден")
                
#         return send_file(
#             qr_path,
#             mimetype='image/png',
#             as_attachment=True,
#             download_name=f"{peer_name}_qr.png"
#         )
#     except Exception as e:
#         logger.error(f"Ошибка при скачивании QR-кода: {str(e)}")
#         return jsonify({"error": str(e)}), 500

# if __name__ == '__main__':
#     # Проверка инициализации сервера
#     server_config_path = os.path.join(WG_CONFIG_DIR, f"{WG_INTERFACE}.conf")
#     if not os.path.exists(server_config_path):
#         logger.info("Конфигурация сервера не найдена. Инициализация WireGuard сервера...")
#         result = wg_manager.initialize_server()
#         if result.get('success'):
#             logger.info("WireGuard сервер успешно инициализирован")
#         else:
#             logger.error(f"Ошибка инициализации WireGuard сервера: {result.get('message')}")
#             exit(1)
    
#     # Запуск API сервера
#     logger.info(f"Запуск WireGuard API на {API_HOST}:{API_PORT}")
#     app.run(host=API_HOST, port=API_PORT)

#!/usr/bin/env python3
"""
WireGuard API - RESTful API для управления WireGuard VPN сервером
Реализация основана на логике скрипта angristan/wireguard-install
"""

import os
import json
import logging
import time
import traceback
import subprocess
from flask import Flask, request, jsonify, send_file, abort
from flask_cors import CORS
from werkzeug.utils import secure_filename
from utils.wg_manager import WireGuardManager

# Настройка логирования с более подробным форматом
logging.basicConfig(
    level=logging.DEBUG,  # Изменено на DEBUG для более подробных логов
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
DEBUG = os.environ.get('DEBUG', 'false').lower() == 'true'

# Создание необходимых директорий
os.makedirs(PEER_CONFIG_DIR, exist_ok=True)
os.chmod(PEER_CONFIG_DIR, 0o700)  # Убедимся, что у директории правильные права

# Функция для запуска команд shell и логирования результата
def run_command(command, shell=False):
    """Запускает команду и возвращает результат с логированием"""
    try:
        if shell:
            process = subprocess.run(command, shell=True, check=True, 
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True)
        else:
            process = subprocess.run(command.split(), check=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True)
        logger.debug(f"Команда выполнена успешно: {command}")
        return process.stdout.strip(), True
    except subprocess.CalledProcessError as e:
        logger.error(f"Ошибка при выполнении команды: {command}")
        logger.error(f"Стандартный вывод: {e.stdout}")
        logger.error(f"Стандартная ошибка: {e.stderr}")
        return e.stderr.strip(), False

# Функция для проверки и установки qrencode
def check_qrencode():
    """Проверяет установку qrencode и пытается установить, если его нет"""
    output, success = run_command("which qrencode")
    
    if not success or not output:
        logger.warning("qrencode не найден, попытка установки...")
        apt_update, _ = run_command("apt-get update", shell=True)
        logger.debug(f"apt-get update: {apt_update}")
        
        install_output, install_success = run_command("apt-get install -y qrencode", shell=True)
        logger.debug(f"apt-get install qrencode: {install_output}")
        
        if install_success:
            logger.info("qrencode успешно установлен")
            return True
        else:
            logger.error("Не удалось установить qrencode")
            return False
    
    logger.info(f"qrencode найден: {output}")
    return True

# Проверка установки qrencode при запуске
qrencode_available = check_qrencode()

# Функция для генерации QR-кода
def generate_qrcode(config_path, output_path):
    """Генерирует QR-код из конфигурационного файла"""
    try:
        logger.debug(f"Генерация QR-кода: {output_path} из {config_path}")
        
        # Проверяем существование исходного файла
        if not os.path.exists(config_path):
            logger.error(f"Файл конфигурации не существует: {config_path}")
            return False
        
        # Проверка прав доступа и содержимого файла конфигурации
        logger.debug(f"Проверка прав доступа файла: {config_path}")
        file_permissions = oct(os.stat(config_path).st_mode)[-3:]
        logger.debug(f"Права доступа: {file_permissions}")
        
        # Чтение содержимого для проверки
        with open(config_path, 'r') as f:
            config_content = f.read()
            logger.debug(f"Размер конфигурации: {len(config_content)} байт")
            if len(config_content) < 10:  # Проверка, что файл не пустой
                logger.error(f"Файл конфигурации слишком короткий или пустой: {config_path}")
                return False
        
        # Создаем временный файл для логирования ошибок qrencode
        error_log = os.path.join(os.path.dirname(output_path), "qrencode_error.log")
        
        # Формируем команду для qrencode
        qr_command = f"qrencode -t png -o {output_path} < {config_path} 2> {error_log}"
        logger.debug(f"Запуск команды: {qr_command}")
        
        # Запускаем команду
        output, success = run_command(qr_command, shell=True)
        
        # Проверяем результат
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            logger.info(f"QR-код успешно создан: {output_path}")
            return True
        else:
            # Проверяем лог ошибок
            if os.path.exists(error_log):
                with open(error_log, 'r') as f:
                    error_content = f.read()
                    logger.error(f"Ошибка qrencode: {error_content}")
            logger.error(f"Не удалось создать QR-код или файл пустой: {output_path}")
            return False
    except Exception as e:
        logger.error(f"Исключение при генерации QR-кода: {str(e)}")
        logger.error(traceback.format_exc())
        return False

# Инициализация менеджера WireGuard
wg_manager = WireGuardManager(
    interface=WG_INTERFACE,
    config_dir=WG_CONFIG_DIR,
    peer_config_dir=PEER_CONFIG_DIR
)

@app.route('/health', methods=['GET'])
def health_check():
    """Проверка работоспособности API"""
    return jsonify({
        "status": "ok",
        "service": "wireguard-api",
        "qrencode_available": qrencode_available
    })

@app.route('/status', methods=['GET'])
def get_status():
    """Получение статуса сервера WireGuard"""
    try:
        status = wg_manager.get_server_status()
        return jsonify(status)
    except Exception as e:
        logger.error(f"Ошибка при получении статуса: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@app.route('/peers', methods=['GET'])
def get_peers():
    """Получение списка всех пиров и активных соединений"""
    try:
        peers = wg_manager.get_peers()
        return jsonify(peers)
    except Exception as e:
        logger.error(f"Ошибка при получении пиров: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@app.route('/create', methods=['POST'])
def create_peer():
    """Создание нового пира WireGuard"""
    try:
        logger.info("Начало создания нового пира")
        data = request.json or {}
        logger.debug(f"Полученные данные: {json.dumps(data)}")
        
        peer_name = data.get('name')
        logger.debug(f"Имя пира: {peer_name}")
        
        # Генерация имени пира, если не указано
        if not peer_name:
            existing_peers = wg_manager.get_peers().get('peers', [])
            peer_count = len(existing_peers) + 1
            peer_name = f"peer{peer_count}"
            logger.debug(f"Сгенерировано имя пира: {peer_name}")
        
        # Дополнительные параметры
        allowed_ips = data.get('allowed_ips')
        dns = data.get('dns')
        logger.debug(f"Параметры: allowed_ips={allowed_ips}, dns={dns}")
        
        # Создание пира
        logger.info(f"Создание пира с именем: {peer_name}")
        result = wg_manager.create_peer(
            peer_name=peer_name,
            allowed_ips=allowed_ips,
            dns=dns
        )
        
        # Проверяем результат создания пира
        if not result.get('success'):
            logger.error(f"Ошибка при создании пира: {result.get('message')}")
            return jsonify(result), 500
        
        # Если пир создан успешно, генерируем QR-код
        logger.info(f"Пир успешно создан, генерация QR-кода")
        config_path = os.path.join(PEER_CONFIG_DIR, f"{WG_INTERFACE}-client-{peer_name}.conf")
        qr_path = os.path.join(PEER_CONFIG_DIR, f"{peer_name}_qr.png")
        
        # Проверяем существование конфигурации
        if not os.path.exists(config_path):
            logger.error(f"Файл конфигурации не создан: {config_path}")
            result['qr_code_generated'] = False
            result['qr_code_error'] = "Файл конфигурации не найден"
            return jsonify(result)
        
        # Генерация QR-кода
        qr_success = generate_qrcode(config_path, qr_path)
        result['qr_code_generated'] = qr_success
        
        if not qr_success:
            logger.warning(f"Не удалось сгенерировать QR-код для пира {peer_name}")
            result['qr_code_error'] = "Ошибка генерации QR-кода"
            # Пробуем альтернативный метод
            try:
                logger.info("Попытка использования альтернативного метода для создания QR-кода")
                alt_command = f"cat {config_path} | qrencode -t png -o {qr_path}"
                output, alt_success = run_command(alt_command, shell=True)
                
                if os.path.exists(qr_path) and os.path.getsize(qr_path) > 0:
                    logger.info("QR-код успешно создан альтернативным методом")
                    result['qr_code_generated'] = True
                    result.pop('qr_code_error', None)
                else:
                    logger.error("Альтернативный метод также не удался")
            except Exception as e:
                logger.error(f"Ошибка при альтернативной генерации QR-кода: {str(e)}")
        
        logger.info(f"Создание пира завершено: {result.get('success')}")
        return jsonify(result)
    except Exception as e:
        logger.error(f"Необработанное исключение при создании пира: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e), "success": False}), 500

@app.route('/restart', methods=['POST'])
def restart_wireguard():
    """Перезапуск сервиса WireGuard"""
    try:
        result = wg_manager.restart_wireguard()
        return jsonify(result)
    except Exception as e:
        logger.error(f"Ошибка при перезапуске WireGuard: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e), "success": False}), 500

@app.route('/remove/<pubkey>', methods=['DELETE'])
def remove_peer(pubkey):
    """Удаление пира по публичному ключу"""
    try:
        result = wg_manager.remove_peer(pubkey)
        return jsonify(result)
    except Exception as e:
        logger.error(f"Ошибка при удалении пира: {str(e)}")
        logger.error(traceback.format_exc())
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
            logger.error(f"Конфигурация для {peer_name} не найдена: {config_path}")
            abort(404, description=f"Конфигурация для {peer_name} не найдена")
        
        logger.info(f"Отправка файла конфигурации для {peer_name}")
        return send_file(
            config_path,
            mimetype='text/plain',
            as_attachment=True,
            download_name=f"{peer_name}.conf"
        )
    except Exception as e:
        logger.error(f"Ошибка при скачивании конфигурации: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@app.route('/download_qr/<peer_name>', methods=['GET'])
def download_qr(peer_name):
    """Скачивание QR-кода для пира"""
    try:
        # Защита от атак через пути
        peer_name = secure_filename(peer_name)
        
        # Поиск файла QR-кода
        qr_path = os.path.join(PEER_CONFIG_DIR, f"{peer_name}_qr.png")
        config_path = os.path.join(PEER_CONFIG_DIR, f"{WG_INTERFACE}-client-{peer_name}.conf")
        
        logger.debug(f"Запрос QR-кода для {peer_name}. Путь: {qr_path}")
        
        # Если QR код не существует, пытаемся его создать
        if not os.path.exists(qr_path) or os.path.getsize(qr_path) == 0:
            logger.info(f"QR-код для {peer_name} не найден или пустой, пытаемся создать...")
            
            # Проверяем наличие конфигурационного файла
            if not os.path.exists(config_path):
                logger.error(f"Конфигурация для {peer_name} не найдена: {config_path}")
                abort(404, description=f"Конфигурация для {peer_name} не найдена")
            
            # Проверяем размер файла конфигурации
            config_size = os.path.getsize(config_path)
            logger.debug(f"Размер файла конфигурации: {config_size} байт")
            
            if config_size == 0:
                logger.error(f"Файл конфигурации пустой: {config_path}")
                abort(500, description=f"Файл конфигурации пустой")
            
            # Генерация QR-кода
            qr_success = generate_qrcode(config_path, qr_path)
            
            if not qr_success:
                logger.error(f"Не удалось сгенерировать QR-код для {peer_name}")
                # Пробуем альтернативный метод
                try:
                    logger.info("Попытка использования альтернативного метода для создания QR-кода")
                    with open(config_path, 'r') as f:
                        config_content = f.read()
                        logger.debug(f"Содержимое конфигурации ({len(config_content)} байт): {config_content[:100]}...")
                    
                    alt_command = f"cat {config_path} | qrencode -t png -o {qr_path}"
                    output, alt_success = run_command(alt_command, shell=True)
                    
                    if not os.path.exists(qr_path) or os.path.getsize(qr_path) == 0:
                        logger.error("Альтернативный метод также не удался")
                        abort(500, description=f"Не удалось сгенерировать QR-код для {peer_name}")
                except Exception as e:
                    logger.error(f"Ошибка при альтернативной генерации QR-кода: {str(e)}")
                    logger.error(traceback.format_exc())
                    abort(500, description=f"Ошибка при генерации QR-кода: {str(e)}")
            
            logger.info(f"QR-код для {peer_name} успешно создан")
        
        # Дополнительная проверка после создания
        if not os.path.exists(qr_path) or os.path.getsize(qr_path) == 0:
            logger.error(f"QR-код не существует или пустой после попытки создания: {qr_path}")
            abort(500, description=f"Не удалось создать QR-код")
        
        logger.info(f"Отправка QR-кода для {peer_name}")
        return send_file(
            qr_path,
            mimetype='image/png',
            as_attachment=True,
            download_name=f"{peer_name}_qr.png"
        )
    except Exception as e:
        logger.error(f"Ошибка при скачивании QR-кода: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@app.route('/test_qrencode', methods=['GET'])
def test_qrencode():
    """Тестирование работы qrencode"""
    try:
        # Создаем временный файл с тестовыми данными
        temp_dir = os.path.dirname(PEER_CONFIG_DIR)
        test_config = os.path.join(temp_dir, "test_wg_config.txt")
        with open(test_config, "w") as f:
            f.write("[Test]\nThis is a test for qrencode")
        
        # Устанавливаем правильные права
        os.chmod(test_config, 0o600)
        
        # Проверяем существование и размер файла
        config_exists = os.path.exists(test_config)
        config_size = os.path.getsize(test_config) if config_exists else 0
        logger.debug(f"Тестовый файл создан: {config_exists}, размер: {config_size} байт")
        
        # Создаем QR-код
        test_qr = os.path.join(temp_dir, "test_qr.png")
        qr_success = generate_qrcode(test_config, test_qr)
        
        # Если не удалось, пробуем напрямую через команду
        if not qr_success or not os.path.exists(test_qr) or os.path.getsize(test_qr) == 0:
            logger.warning("Не удалось создать тестовый QR-код, пробуем через shell команду")
            cmd = f"cat {test_config} | qrencode -t png -o {test_qr}"
            output, shell_success = run_command(cmd, shell=True)
            qr_success = os.path.exists(test_qr) and os.path.getsize(test_qr) > 0
        
        # Проверяем утилиту qrencode
        which_output, which_success = run_command("which qrencode", shell=True)
        version_output, version_success = run_command("qrencode --version", shell=True)
        
        # Результат
        result = {
            "success": qr_success,
            "qrencode_path": which_output if which_success else "не найден",
            "qrencode_version": version_output if version_success else "неизвестно",
            "config_file": {
                "exists": config_exists,
                "size": config_size,
                "path": test_config
            },
            "qr_file": {
                "exists": os.path.exists(test_qr),
                "size": os.path.getsize(test_qr) if os.path.exists(test_qr) else 0,
                "path": test_qr
            },
            "message": "QR-код успешно создан" if qr_success else "Ошибка создания QR-кода"
        }
        
        return jsonify(result)
    except Exception as e:
        logger.error(f"Ошибка при тестировании qrencode: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/debug_info', methods=['GET'])
def debug_info():
    """Возвращает информацию для отладки системы"""
    if not DEBUG:
        return jsonify({"error": "Debug mode is disabled"}), 403
    
    try:
        debug_data = {
            "environment": {
                "WG_INTERFACE": WG_INTERFACE,
                "WG_CONFIG_DIR": WG_CONFIG_DIR,
                "PEER_CONFIG_DIR": PEER_CONFIG_DIR,
                "API_HOST": API_HOST,
                "API_PORT": API_PORT
            },
            "paths": {
                "config_dir_exists": os.path.exists(WG_CONFIG_DIR),
                "peer_config_dir_exists": os.path.exists(PEER_CONFIG_DIR),
                "config_dir_permissions": oct(os.stat(WG_CONFIG_DIR).st_mode)[-3:] if os.path.exists(WG_CONFIG_DIR) else "N/A",
                "peer_config_dir_permissions": oct(os.stat(PEER_CONFIG_DIR).st_mode)[-3:] if os.path.exists(PEER_CONFIG_DIR) else "N/A"
            },
            "qrencode": {
                "available": qrencode_available,
                "which_qrencode": run_command("which qrencode", shell=True)[0] if qrencode_available else "N/A",
                "version": run_command("qrencode --version", shell=True)[0] if qrencode_available else "N/A"
            },
            "wireguard": {
                "interface_exists": os.path.exists(f"/sys/class/net/{WG_INTERFACE}"),
                "config_file_exists": os.path.exists(os.path.join(WG_CONFIG_DIR, f"{WG_INTERFACE}.conf")),
                "params_file_exists": os.path.exists(os.path.join(WG_CONFIG_DIR, "params")),
                "wg_show": run_command(f"wg show {WG_INTERFACE}", shell=True)[0] if os.path.exists(f"/sys/class/net/{WG_INTERFACE}") else "Интерфейс не существует"
            }
        }
        
        # Получение списка файлов в директориях
        if os.path.exists(WG_CONFIG_DIR):
            debug_data["files"] = {
                "config_dir": os.listdir(WG_CONFIG_DIR),
                "peer_config_dir": os.listdir(PEER_CONFIG_DIR) if os.path.exists(PEER_CONFIG_DIR) else []
            }
        
        return jsonify(debug_data)
    except Exception as e:
        logger.error(f"Ошибка при получении отладочной информации: {str(e)}")
        logger.error(traceback.format_exc())
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
    app.run(host=API_HOST, port=API_PORT, debug=DEBUG)