let packs = [];
let cart = JSON.parse(localStorage.getItem('flCart')) || [];
let currentAudio = null;
let currentBtn = null;

// Автоматически загружаем список паков из /bits/list.json
async function loadPacks() {
    try {
        const response = await fetch('bits/list.json');
        if (!response.ok) throw new Error('Не удалось загрузить list.json');
        
        const data = await response.json();
        
        packs = data.map((item, index) => ({
            id: index + 1,
            title: item.title,
            genre: item.genre,
            price: item.price,
            badge: item.badge || null,
            icon: item.icon || 'fa-music',
            audio: `bits/${item.file}`
        }));

        renderPacks();
        updateCartUI();
    } catch (err) {
        console.error(err);
        document.getElementById('packs-grid').innerHTML = `
            <div style="grid-column: 1 / -1; text-align: center; color: #ff6b8a; padding: 40px;">
                Не удалось загрузить паки.<br>
                Проверь, что файл <b>bits/list.json</b> существует и написан правильно.
            </div>
        `;
    }
}

function renderPacks(filter = 'all') {
    const grid = document.getElementById('packs-grid');
    grid.innerHTML = '';

    const filtered = filter === 'all' 
        ? packs 
        : packs.filter(p => p.genre === filter);

    if (filtered.length === 0) {
        grid.innerHTML = `<div style="grid-column: 1/-1; text-align:center; color: var(--text-muted);">Ничего не найдено</div>`;
        return;
    }

    filtered.forEach(pack => {
        const card = document.createElement('div');
        card.className = 'pack-card';
        card.innerHTML = `
            <div class="pack-preview">
                ${pack.badge ? `<span class="pack-badge">${pack.badge}</span>` : ''}
                <i class="fas ${pack.icon} main-icon"></i>
                <button class="play-btn" data-audio="${pack.audio}" onclick="togglePlay(this, event)">
                    <i class="fas fa-play"></i>
                </button>
            </div>
            <div class="pack-info">
                <h3>${pack.title}</h3>
                <div class="genre">${pack.genre}</div>
                <div class="pack-bottom">
                    <div class="price">${pack.price.toLocaleString()} ₽</div>
                    <button class="btn btn-add" onclick="addToCart(${pack.id})">В корзину</button>
                </div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function togglePlay(btn, e) {
    e.stopPropagation();
    const audioSrc = btn.dataset.audio;

    if (currentAudio && currentBtn === btn && !currentAudio.paused) {
        currentAudio.pause();
        btn.classList.remove('playing');
        btn.innerHTML = '<i class="fas fa-play"></i>';
        return;
    }

    if (currentAudio) {
        currentAudio.pause();
        if (currentBtn) {
            currentBtn.classList.remove('playing');
            currentBtn.innerHTML = '<i class="fas fa-play"></i>';
        }
    }

    currentAudio = new Audio(audioSrc);
    currentBtn = btn;

    currentAudio.play().catch(() => {
        showToast('Не удалось загрузить превью');
    });

    btn.classList.add('playing');
    btn.innerHTML = '<i class="fas fa-pause"></i>';

    currentAudio.onended = () => {
        btn.classList.remove('playing');
        btn.innerHTML = '<i class="fas fa-play"></i>';
        currentAudio = null;
        currentBtn = null;
    };
}

document.querySelectorAll('.filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        renderPacks(btn.dataset.filter);
    });
});

function addToCart(id) {
    const pack = packs.find(p => p.id === id);
    if (!pack) return;

    const existing = cart.find(item => item.id === id);
    if (existing) {
        existing.qty += 1;
    } else {
        cart.push({ ...pack, qty: 1 });
    }

    saveCart();
    updateCartUI();
    showToast(`${pack.title} добавлен`);
}

function removeFromCart(id) {
    cart = cart.filter(item => item.id !== id);
    saveCart();
    updateCartUI();
}

function saveCart() {
    localStorage.setItem('flCart', JSON.stringify(cart));
}

function updateCartUI() {
    const count = cart.reduce((sum, item) => sum + item.qty, 0);
    document.getElementById('cart-count').textContent = count;

    const container = document.getElementById('cart-items');
    const totalEl = document.getElementById('cart-total');

    if (cart.length === 0) {
        container.innerHTML = '<p style="color: var(--text-muted); text-align: center; margin-top: 40px;">Корзина пуста</p>';
        totalEl.textContent = '0';
        return;
    }

    container.innerHTML = cart.map(item => `
        <div class="cart-item">
            <div class="cart-item-info">
                <h4>${item.title}</h4>
                <div class="price">${item.price.toLocaleString()} ₽ × ${item.qty}</div>
            </div>
            <button class="cart-item-remove" onclick="removeFromCart(${item.id})">
                <i class="fas fa-trash"></i>
            </button>
        </div>
    `).join('');

    const total = cart.reduce((sum, item) => sum + item.price * item.qty, 0);
    totalEl.textContent = total.toLocaleString();
}

function toggleCart() {
    document.getElementById('cart-sidebar').classList.toggle('open');
    document.getElementById('overlay').classList.toggle('show');
}

function checkout() {
    if (cart.length === 0) {
        alert('Корзина пуста');
        return;
    }

    const total = cart.reduce((sum, item) => sum + item.price * item.qty, 0);
    alert(`Заказ на ${total.toLocaleString()} ₽ принят!\n\nЗдесь будет оплата.`);
    
    cart = [];
    saveCart();
    updateCartUI();
    toggleCart();
}

function showToast(msg) {
    const toast = document.createElement('div');
    toast.style.cssText = `
        position: fixed;
        bottom: 30px;
        left: 50%;
        transform: translateX(-50%);
        background: var(--accent);
        color: white;
        padding: 12px 24px;
        border-radius: 10px;
        font-weight: 600;
        z-index: 3000;
        box-shadow: 0 10px 30px rgba(255,45,85,0.3);
    `;
    toast.textContent = msg;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2200);
}

// Запускаем
loadPacks();
