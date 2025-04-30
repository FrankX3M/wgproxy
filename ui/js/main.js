/**
 * WireGuard API Web Interface
 * Клиентский JavaScript для взаимодействия с WireGuard API
 */

// Базовый URL API (при необходимости измените)
const API_URL = window.location.protocol + '//' + window.location.hostname + ':5000';

// DOM-элементы
const serverStatusEl = document.getElementById('server-status');
const serverInfoContentEl = document.getElementById('server-info-content');
const peersTableContainerEl = document.getElementById('peers-table-container');
const addPeerFormEl = document.getElementById('add-peer-form');
const refreshStatusBtn = document.getElementById('refresh-status');
const restartWireguardBtn = document.getElementById('restart-wireguard');
const modal = document.getElementById('modal');
const modalTitle = document.getElementById('modal-title');
const modalBody = document.getElementById('modal-body');
const closeModal = document.querySelector('.close-modal');

// Инициализация страницы
document.addEventListener('DOMContentLoaded', () => {
    // Загрузка начальных данных
    loadServerStatus();
    loadPeers();
    
    // Настройка обработчиков событий
    addPeerFormEl.addEventListener('submit', handleAddPeer);
    refreshStatusBtn.addEventListener('click', refreshAll);
    restartWireguardBtn.addEventListener('click', restartWireguard);
    closeModal.addEventListener('click', () => modal.style.display = 'none');
    window.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.style.display = 'none';
        }
    });
    
    // Автоматическое обновление статуса каждые 60 секунд
    setInterval(refreshAll, 60000);
});

/**
 * Загрузка статуса сервера
 */
async function loadServerStatus() {
    try {
        const response = await fetch(`${API_URL}/status`);
        const data = await response.json();
        
        updateServerStatus(data);
    } catch (error) {
        console.error('Ошибка при загрузке статуса сервера:', error);
        setServerStatusOffline();
    }
}

/**
 * Загрузка списка пиров
 */
async function loadPeers() {
    try {
        const response = await fetch(`${API_URL}/peers`);
        const data = await response.json();
        
        renderPeers(data);
    } catch (error) {
        console.error('Ошибка при загрузке пиров:', error);
        peersTableContainerEl.innerHTML = '<p class="error-message">Ошибка при загрузке пиров. Пожалуйста, проверьте соединение с сервером.</p>';
    }
}

/**
 * Обновление всех данных
 */
function refreshAll() {
    loadServerStatus();
    loadPeers();
}

/**
 * Обновление статуса сервера на странице
 */
function updateServerStatus(data) {
    // Обновление индикатора статуса
    const statusDot = serverStatusEl.querySelector('.status-dot');
    const statusText = serverStatusEl.querySelector('.status-text');
    
    if (data.status === 'active') {
        statusDot.className = 'status-dot online';
        statusText.textContent = 'Онлайн';
    } else if (data.status === 'degraded') {
        statusDot.className = 'status-dot degraded';
        statusText.textContent = 'Проблемы с соединением';
    } else {
        statusDot.className = 'status-dot offline';
        statusText.textContent = 'Офлайн';
    }
    
    // Обновление информации о сервере
    if (data.server) {
        const { interface: wgInterface, public_key, endpoint, allowed_ips, dns, internal_subnet } = data.server;
        
        serverInfoContentEl.innerHTML = `
            <div class="info-grid">
                <div class="info-label">Интерфейс:</div>
                <div class="info-value">${wgInterface}</div>
                
                <div class="info-label">Публичный ключ:</div>
                <div class="info-value">${public_key}</div>
                
                <div class="info-label">Эндпоинт:</div>
                <div class="info-value">${endpoint}</div>
                
                <div class="info-label">Внутренняя подсеть:</div>
                <div class="info-value">${internal_subnet}</div>
                
                <div class="info-label">Разрешенные IP (AllowedIPs):</div>
                <div class="info-value">${allowed_ips}</div>
                
                <div class="info-label">DNS:</div>
                <div class="info-value">${dns}</div>
                
                <div class="info-label">Количество пиров:</div>
                <div class="info-value">${data.peers_count}</div>
            </div>
        `;
    }
}

/**
 * Установка статуса сервера в "Офлайн"
 */
function setServerStatusOffline() {
    const statusDot = serverStatusEl.querySelector('.status-dot');
    const statusText = serverStatusEl.querySelector('.status-text');
    
    statusDot.className = 'status-dot offline';
    statusText.textContent = 'Офлайн';
    
    serverInfoContentEl.innerHTML = '<p class="error-message">Невозможно подключиться к серверу WireGuard. Проверьте, запущен ли сервер.</p>';
}

/**
 * Отображение списка пиров
 */
function renderPeers(data) {
    const { peers, active_connections } = data;
    
    if (!peers || peers.length === 0) {
        peersTableContainerEl.innerHTML = '<p>Пиры не найдены. Создайте новый пир, используя форму выше.</p>';
        return;
    }
    
    // Создаем карту активных соединений для быстрого доступа
    const activeConnectionMap = {};
    if (active_connections && active_connections.length > 0) {
        active_connections.forEach(conn => {
            activeConnectionMap[conn.public_key] = conn;
        });
    }
    
    // Создаем таблицу пиров
    let tableHTML = `
        <table class="peer-table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Имя</th>
                    <th>Публичный ключ</th>
                    <th>Статус</th>
                    <th>Действия</th>
                </tr>
            </thead>
            <tbody>
    `;
    
    peers.forEach(peer => {
        const activeConnection = activeConnectionMap[peer.public_key];
        let statusHTML = '';
        
        if (activeConnection) {
            const status = activeConnection.status;
            
            if (status === 'active') {
                statusHTML = '<span class="badge badge-success">Активен</span>';
            } else {
                statusHTML = '<span class="badge badge-warning">Неактивен</span>';
            }
        } else {
            statusHTML = '<span class="badge badge-danger">Не подключен</span>';
        }
        
        tableHTML += `
            <tr>
                <td>${peer.id}</td>
                <td>${peer.name}</td>
                <td>${peer.public_key.substring(0, 10)}...</td>
                <td>${statusHTML}</td>
                <td class="actions">
                    <button class="btn secondary-btn view-btn" data-peer="${peer.name}">Просмотр</button>
                    <button class="btn danger-btn delete-btn" data-public-key="${peer.public_key}">Удалить</button>
                </td>
            </tr>
        `;
    });
    
    tableHTML += '</tbody></table>';
    
    peersTableContainerEl.innerHTML = tableHTML;
    
    // Добавляем обработчики событий для кнопок
    document.querySelectorAll('.view-btn').forEach(btn => {
        btn.addEventListener('click', () => viewPeerDetails(btn.dataset.peer));
    });
    
    document.querySelectorAll('.delete-btn').forEach(btn => {
        btn.addEventListener('click', () => deletePeer(btn.dataset.publicKey));
    });
}

/**
 * Обработка отправки формы для добавления нового пира
 */
async function handleAddPeer(event) {
    event.preventDefault();
    
    const nameInput = document.getElementById('peer-name');
    const allowedIpsInput = document.getElementById('allowed-ips');
    const dnsInput = document.getElementById('dns-servers');
    
    const formData = {
        name: nameInput.value.trim() || undefined,
        allowed_ips: allowedIpsInput.value.trim() || undefined,
        dns: dnsInput.value.trim() || undefined
    };
    
    try {
        // Отключаем кнопку на время создания пира
        const submitBtn = addPeerFormEl.querySelector('button[type="submit"]');
        submitBtn.disabled = true;
        submitBtn.textContent = 'Создание...';
        
        const response = await fetch(`${API_URL}/create`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        });
        
        const data = await response.json();
        
        if (data.success) {
            // Очистка формы
            addPeerFormEl.reset();
            
            // Обновление списка пиров
            loadPeers();
            
            // Показ модального окна с деталями
            showPeerDetailsModal(data);
        } else {
            alert(`Ошибка при создании пира: ${data.message}`);
        }
    } catch (error) {
        console.error('Ошибка при создании пира:', error);
        alert('Ошибка при создании пира. Проверьте соединение с сервером.');
    } finally {
        // Восстанавливаем кнопку
        const submitBtn = addPeerFormEl.querySelector('button[type="submit"]');
        submitBtn.disabled = false;
        submitBtn.textContent = 'Создать пир';
    }
}

/**
 * Просмотр деталей пира
 */
async function viewPeerDetails(peerName) {
    try {
        // Загрузка конфигурации пира
        const response = await fetch(`${API_URL}/download/${peerName}`);
        
        if (!response.ok) {
            throw new Error(`Ошибка при загрузке конфигурации: ${response.statusText}`);
        }
        
        const configText = await response.text();
        
        // Показ модального окна с конфигурацией
        modalTitle.textContent = `Конфигурация пира: ${peerName}`;
        
        modalBody.innerHTML = `
            <div class="peer-details">
                <p>Используйте эту конфигурацию для подключения к WireGuard VPN.</p>
                
                <div class="download-links">
                    <a href="${API_URL}/download/${peerName}" class="btn secondary-btn" download="${peerName}.conf">Скачать .conf файл</a>
                    <a href="${API_URL}/download_qr/${peerName}" class="btn secondary-btn" target="_blank">Скачать QR-код</a>
                </div>
                
                <div class="qr-container">
                    <img src="${API_URL}/download_qr/${peerName}" alt="QR-код для ${peerName}" />
                </div>
                
                <h3>Конфигурация:</h3>
                <div class="config-container">${configText}</div>
            </div>
        `;
        
        modal.style.display = 'block';
    } catch (error) {
        console.error('Ошибка при загрузке деталей пира:', error);
        alert(`Ошибка при загрузке деталей пира: ${error.message}`);
    }
}

/**
 * Удаление пира
 */
async function deletePeer(publicKey) {
    if (!confirm('Вы уверены, что хотите удалить этот пир? Это действие нельзя отменить.')) {
        return;
    }
    
    try {
        const response = await fetch(`${API_URL}/remove/${publicKey}`, {
            method: 'DELETE'
        });
        
        const data = await response.json();
        
        if (data.success) {
            alert('Пир успешно удален');
            loadPeers(); // Обновление списка пиров
        } else {
            alert(`Ошибка при удалении пира: ${data.message}`);
        }
    } catch (error) {
        console.error('Ошибка при удалении пира:', error);
        alert('Ошибка при удалении пира. Проверьте соединение с сервером.');
    }
}

/**
 * Перезапуск WireGuard
 */
async function restartWireguard() {
    if (!confirm('Вы уверены, что хотите перезапустить сервер WireGuard? Все текущие соединения будут прерваны.')) {
        return;
    }
    
    try {
        restartWireguardBtn.disabled = true;
        restartWireguardBtn.textContent = 'Перезапуск...';
        
        const response = await fetch(`${API_URL}/restart`, {
            method: 'POST'
        });
        
        const data = await response.json();
        
        if (data.success) {
            alert('WireGuard успешно перезапущен');
            
            // Даем серверу время на перезапуск
            setTimeout(() => {
                refreshAll();
                restartWireguardBtn.disabled = false;
                restartWireguardBtn.textContent = 'Перезапустить WireGuard';
            }, 3000);
        } else {
            alert(`Ошибка при перезапуске WireGuard: ${data.message}`);
            restartWireguardBtn.disabled = false;
            restartWireguardBtn.textContent = 'Перезапустить WireGuard';
        }
    } catch (error) {
        console.error('Ошибка при перезапуске WireGuard:', error);
        alert('Ошибка при перезапуске WireGuard. Проверьте соединение с сервером.');
        restartWireguardBtn.disabled = false;
        restartWireguardBtn.textContent = 'Перезапустить WireGuard';
    }
}

/**
 * Показ модального окна с деталями нового пира
 */
function showPeerDetailsModal(peer) {
    modalTitle.textContent = `Пир создан: ${peer.peer_name}`;
    
    modalBody.innerHTML = `
        <div class="peer-details">
            <p>Пир успешно создан. Используйте эту конфигурацию для подключения к WireGuard VPN.</p>
            
            <div class="peer-info">
                <p><strong>Имя:</strong> ${peer.peer_name}</p>
                <p><strong>IP:</strong> ${peer.peer_ip}</p>
                <p><strong>IPv6:</strong> ${peer.peer_ipv6}</p>
                <p><strong>Публичный ключ:</strong> ${peer.public_key}</p>
                <p><strong>Приватный ключ:</strong> ${peer.private_key}</p>
                <p><strong>Адрес сервера:</strong> ${peer.server_endpoint}</p>
            </div>
            
            <div class="download-links">
                <a href="${API_URL}/download/${peer.peer_name}" class="btn secondary-btn" download="${peer.peer_name}.conf">Скачать .conf файл</a>
                <a href="${API_URL}/download_qr/${peer.peer_name}" class="btn secondary-btn" target="_blank">Скачать QR-код</a>
            </div>
            
            ${peer.qr_code_generated ? `
            <div class="qr-container">
                <img src="${API_URL}/download_qr/${peer.peer_name}" alt="QR-код для ${peer.peer_name}" />
                <p>Отсканируйте QR-код в приложении WireGuard на мобильном устройстве</p>
            </div>
            ` : ''}
            
            <h3>Конфигурация:</h3>
            <div class="config-container">${peer.config}</div>
        </div>
    `;
    
    modal.style.display = 'block';
}