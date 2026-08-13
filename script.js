const packs = [
    {
        id: 1,
        title: "Dark Trap Essentials",
        genre: "trap",
        price: 1490,
        badge: "Хит",
        icon: "fa-drum",
        audio: "bits/dark-trap.mp3"
    },
    {
        id: 2,
        title: "UK Drill Kit Vol.3",
        genre: "drill",
        price: 1290,
        badge: "Новинка",
        icon: "fa-bolt",
        audio: "bits/uk-drill.mp3"
    },
    {
        id: 3,
        title: "Melodic House Vibes",
        genre: "house",
        price: 990,
        badge: null,
        icon: "fa-wave-square",
        audio: "bits/melodic-house.mp3"
    },
    {
        id: 4,
        title: "Serum Presets — Future Bass",
        genre: "presets",
        price: 790,
        badge: "Топ",
        icon: "fa-sliders",
        audio: "bits/serum-presets.mp3"
    },
    {
        id: 5,
        title: "Hard Trap Drums",
        genre: "trap",
        price: 1190,
        badge: null,
        icon: "fa-music",
        audio: "bits/hard-trap.mp3"
    },
    {
        id: 6,
        title: "Chicago Drill Pack",
        genre: "drill",
        price: 1390,
        badge: "Хит",
        icon: "fa-fire",
        audio: "bits/chicago-drill.mp3"
    },
    {
        id: 7,
        title: "Deep House Starters",
        genre: "house",
        price: 890,
        badge: null,
        icon: "fa-compact-disc",
        audio: "bits/deep-house.mp3"
    },
    {
        id: 8,
        title: "Sylenth1 — Night Drive",
        genre: "presets",
        price: 690,
        badge: "Скидка",
        icon: "fa-keyboard",
        audio: "bits/sylenth1.mp3"
    }
];

let cart = JSON.parse(localStorage.getItem('flCart')) || [];
let currentAudio = null;
let currentBtn = null;

function renderPacks(filter = 'all') {
    const grid = document.getElementById('packs-grid');
    grid.innerHTML = '';

    const filtered = filter === 'all' ? packs : packs.filter(p => p.genre === filter);

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

    // Если уже играет этот же трек — останавливаем
    if (currentAudio && currentBtn === btn && !currentAudio.paused) {
        currentAudio.pause();
        btn.classList.remove('playing');
        btn.innerHTML = '<i class="fas fa-play"></i>';
        return;
    }

    // Останавливаем предыдущий
    if (currentAudio) {
        currentAudio.pause();
        if (currentBtn) {
            currentBtn.classList.remove('playing');
            currentBtn.innerHTML = '<i class="fas fa-play"></i>';
        }
    }

    // Создаём новый
    currentAudio = new Audio(audioSrc);
    currentBtn = btn;

    currentAudio.play().catch(err => {
        console.log('Ошибка загрузки аудио:', err);
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
    alert(`Заказ на ${total.toLocaleString()} ₽ принят!\n\nЗдесь будет оплата (ЮKassa / Crypto / Telegram).`);
    
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

// Старт
renderPacks();
updateCartUI();
