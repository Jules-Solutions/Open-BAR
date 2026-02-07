/* BAR Build Order Simulator - Frontend */

// ============================================================
// State
// ============================================================

let units = {};
let pools = {};
let buildOrders = [];
let charts = {};
let editorQueues = { commander: [], factory_0: [], con_1: [] };
let optimizeResult = null;

// ============================================================
// Utilities
// ============================================================

function fmtTime(tick) {
    const m = Math.floor(tick / 60);
    const s = tick % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
}

function fmtRate(v) { return v >= 1000 ? v.toFixed(0) : v.toFixed(1); }

async function api(path, opts = {}) {
    const res = await fetch(`/api${path}`, {
        headers: { 'Content-Type': 'application/json' },
        ...opts,
    });
    if (!res.ok) throw new Error(`API error: ${res.status}`);
    return res.json();
}

// ============================================================
// Chart helpers
// ============================================================

const CHART_DEFAULTS = {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
        legend: { labels: { color: '#8b949e', font: { size: 11 } } },
    },
    scales: {
        x: {
            grid: { color: 'rgba(255,255,255,0.05)' },
            ticks: { color: '#8b949e', font: { size: 10 } },
        },
        y: {
            grid: { color: 'rgba(255,255,255,0.05)' },
            ticks: { color: '#8b949e', font: { size: 10 } },
            beginAtZero: true,
        },
    },
};

function makeChartOpts(overrides = {}) {
    return JSON.parse(JSON.stringify({ ...CHART_DEFAULTS, ...overrides }));
}

function destroyChart(id) {
    if (charts[id]) { charts[id].destroy(); delete charts[id]; }
}

function stallAnnotations(stalls) {
    const annotations = {};
    stalls.forEach((s, i) => {
        annotations[`stall_${i}`] = {
            type: 'box',
            xMin: fmtTime(s.start_tick),
            xMax: fmtTime(s.end_tick),
            backgroundColor: s.resource === 'metal'
                ? 'rgba(255,82,82,0.12)' : 'rgba(255,167,38,0.12)',
            borderColor: s.resource === 'metal'
                ? 'rgba(255,82,82,0.3)' : 'rgba(255,167,38,0.3)',
            borderWidth: 1,
        };
    });
    return annotations;
}

function milestoneAnnotations(milestones) {
    const annotations = {};
    milestones.forEach((m, i) => {
        annotations[`ms_${i}`] = {
            type: 'line',
            xMin: fmtTime(m.tick),
            xMax: fmtTime(m.tick),
            borderColor: 'rgba(255,255,255,0.25)',
            borderWidth: 1,
            borderDash: [4, 4],
            label: {
                display: true,
                content: m.event.replace('first_', ''),
                position: 'start',
                color: '#8b949e',
                font: { size: 9 },
                rotation: -90,
                padding: 2,
            },
        };
    });
    return annotations;
}

// ============================================================
// Tab Navigation
// ============================================================

document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(`tab-${tab.dataset.tab}`).classList.add('active');
    });
});

// ============================================================
// Faction
// ============================================================

document.getElementById('faction-select').addEventListener('change', async (e) => {
    await api('/faction', { method: 'POST', body: JSON.stringify({ faction: e.target.value }) });
    await loadUnits();
    populateEditorUnitList();
});

// ============================================================
// Init
// ============================================================

async function loadUnits() {
    const data = await api('/units');
    units = data.units;
    pools = data.pools;
}

async function loadBuildOrders() {
    const data = await api('/build-orders');
    buildOrders = data.build_orders;
    populateBOSelectors();
}

function populateBOSelectors() {
    const selectors = ['sim-bo-select', 'ed-load-select', 'cmp-a-select', 'cmp-b-select', 'opt-start-from'];
    selectors.forEach(id => {
        const sel = document.getElementById(id);
        const first = sel.querySelector('option');
        sel.innerHTML = '';
        sel.appendChild(first);
        buildOrders.forEach(bo => {
            const opt = document.createElement('option');
            opt.value = bo.filename;
            opt.textContent = bo.stem;
            sel.appendChild(opt);
        });
    });
}

// ============================================================
// SIMULATE TAB
// ============================================================

document.getElementById('sim-run-btn').addEventListener('click', async () => {
    const filename = document.getElementById('sim-bo-select').value;
    const duration = parseInt(document.getElementById('sim-duration').value);
    if (!filename) return alert('Select a build order');

    document.getElementById('sim-run-btn').disabled = true;
    try {
        const result = await api('/simulate', {
            method: 'POST',
            body: JSON.stringify({ filename, duration }),
        });
        renderSimResults(result);
        document.getElementById('sim-results').classList.remove('hidden');
    } finally {
        document.getElementById('sim-run-btn').disabled = false;
    }
});

function renderSimResults(result, prefix = '') {
    const labels = result.snapshots.map(s => fmtTime(s.tick));
    const allAnnotations = {
        ...stallAnnotations(result.stall_events),
        ...milestoneAnnotations(result.milestones),
    };

    // Economy chart
    destroyChart(prefix + 'economy');
    const ecoCtx = document.getElementById(`chart-${prefix}economy`).getContext('2d');
    const ecoOpts = makeChartOpts();
    ecoOpts.plugins.annotation = { annotations: allAnnotations };
    charts[prefix + 'economy'] = new Chart(ecoCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                { label: 'Metal /s', data: result.snapshots.map(s => s.metal_income),
                  borderColor: '#00e5ff', backgroundColor: 'rgba(0,229,255,0.1)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
                { label: 'Energy /s', data: result.snapshots.map(s => s.energy_income),
                  borderColor: '#ffd740', backgroundColor: 'rgba(255,215,64,0.1)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
            ],
        },
        options: ecoOpts,
    });

    // Stored chart
    destroyChart(prefix + 'stored');
    const storedCtx = document.getElementById(`chart-${prefix}stored`).getContext('2d');
    charts[prefix + 'stored'] = new Chart(storedCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                { label: 'Metal Stored', data: result.snapshots.map(s => s.metal_stored),
                  borderColor: '#00e5ff', backgroundColor: 'rgba(0,229,255,0.05)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
                { label: 'Energy Stored', data: result.snapshots.map(s => s.energy_stored),
                  borderColor: '#ffd740', backgroundColor: 'rgba(255,215,64,0.05)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
            ],
        },
        options: makeChartOpts(),
    });

    // BP + Army chart
    destroyChart(prefix + 'bp-army');
    const bpCtx = document.getElementById(`chart-${prefix}bp-army`).getContext('2d');
    charts[prefix + 'bp-army'] = new Chart(bpCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                { label: 'Build Power', data: result.snapshots.map(s => s.build_power),
                  borderColor: '#ea80fc', tension: 0.3, pointRadius: 0, borderWidth: 2,
                  yAxisID: 'y' },
                { label: 'Army Value (M)', data: result.snapshots.map(s => s.army_value_metal),
                  borderColor: '#69f0ae', tension: 0.3, pointRadius: 0, borderWidth: 2,
                  yAxisID: 'y1' },
            ],
        },
        options: {
            ...makeChartOpts(),
            scales: {
                ...makeChartOpts().scales,
                y1: {
                    position: 'right',
                    grid: { drawOnChartArea: false },
                    ticks: { color: '#69f0ae', font: { size: 10 } },
                    beginAtZero: true,
                },
            },
        },
    });

    // Stall factor chart
    destroyChart(prefix + 'stall');
    const stallCtx = document.getElementById(`chart-${prefix}stall`).getContext('2d');
    charts[prefix + 'stall'] = new Chart(stallCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                { label: 'Stall Factor', data: result.snapshots.map(s => s.stall_factor),
                  borderColor: '#f85149', backgroundColor: 'rgba(248,81,73,0.1)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
            ],
        },
        options: {
            ...makeChartOpts(),
            scales: {
                ...makeChartOpts().scales,
                y: { ...makeChartOpts().scales.y, min: 0, max: 1.1 },
            },
        },
    });

    // Milestones table
    const msTbody = document.querySelector(`#${prefix || 'sim-'}milestones tbody`);
    if (msTbody) {
        msTbody.innerHTML = '';
        result.milestones.sort((a, b) => a.tick - b.tick).forEach(m => {
            msTbody.innerHTML += `<tr><td>${m.description}</td><td>${fmtTime(m.tick)}</td>
                <td class="metal">${fmtRate(m.metal_income)}</td>
                <td class="energy">${fmtRate(m.energy_income)}</td></tr>`;
        });
    }

    // Stall events table
    const stTbody = document.querySelector(`#${prefix || 'sim-'}stalls tbody`);
    if (stTbody) {
        stTbody.innerHTML = '';
        if (result.stall_events.length === 0) {
            stTbody.innerHTML = '<tr><td colspan="4" style="color:var(--success)">No stalls!</td></tr>';
        } else {
            result.stall_events.forEach(s => {
                const dur = s.end_tick - s.start_tick + 1;
                stTbody.innerHTML += `<tr><td>${fmtTime(s.start_tick)}-${fmtTime(s.end_tick)}</td>
                    <td>${s.resource}</td><td>${dur}s</td>
                    <td>${Math.round(s.severity * 100)}%</td></tr>`;
            });
        }
    }

    // Summary
    const sumDiv = document.getElementById(`${prefix || 'sim-'}summary`);
    if (sumDiv) {
        const stats = [
            ['Total Army Value', `${result.total_army_metal_value.toFixed(0)} metal`, 'metal'],
            ['Peak M/s', fmtRate(result.peak_metal_income), 'metal'],
            ['Peak E/s', fmtRate(result.peak_energy_income), 'energy'],
            ['Metal Stall', `${result.total_metal_stall_seconds}s`, ''],
            ['Energy Stall', `${result.total_energy_stall_seconds}s`, ''],
        ];
        if (result.time_to_first_factory)
            stats.push(['First Factory', fmtTime(result.time_to_first_factory), '']);
        if (result.time_to_first_constructor)
            stats.push(['First Constructor', fmtTime(result.time_to_first_constructor), '']);
        if (result.time_to_first_nano)
            stats.push(['First Nano', fmtTime(result.time_to_first_nano), '']);

        sumDiv.innerHTML = stats.map(([l, v, c]) =>
            `<div class="stat-row"><span class="stat-label">${l}</span>
             <span class="stat-value ${c}">${v}</span></div>`
        ).join('');
    }

    // Construction log
    const logDiv = document.getElementById(`${prefix || 'sim-'}log`);
    if (logDiv) {
        logDiv.innerHTML = result.completion_log.map(e => {
            const u = units[e.unit_key];
            const name = u ? u.name : e.unit_key;
            return `<div class="log-entry"><span class="time">${fmtTime(e.tick)}</span>
                <span class="builder">${e.builder_id}</span>
                <span class="unit">${name}</span></div>`;
        }).join('');
    }
}

// ============================================================
// EDITOR TAB
// ============================================================

function populateEditorUnitList(pool = 'commander') {
    const list = document.getElementById('ed-unit-list');
    list.innerHTML = '';
    const poolKeys = pools[pool] || [];
    poolKeys.forEach(key => {
        const u = units[key];
        if (!u) return;
        const item = document.createElement('div');
        item.className = 'unit-item';
        item.innerHTML = `<span class="unit-name">${key}</span>
            <span class="unit-cost">${u.metal_cost}M ${u.energy_cost}E</span>
            <span class="unit-add">+</span>`;
        item.addEventListener('click', () => addToQueue(key, pool));
        list.appendChild(item);
    });
}

function addToQueue(key, pool) {
    let queueId;
    if (pool === 'commander') queueId = 'commander';
    else if (pool === 'factory') queueId = 'factory_0';
    else queueId = 'con_1';

    editorQueues[queueId].push(key);
    renderQueue(queueId);
}

function renderQueue(queueId) {
    const el = document.getElementById(`queue-${queueId}`);
    el.innerHTML = '';
    editorQueues[queueId].forEach((key, i) => {
        const u = units[key];
        const item = document.createElement('div');
        item.className = 'queue-item';
        item.dataset.index = i;
        item.innerHTML = `<span class="q-name">${key}</span>
            <span class="q-remove" title="Remove">&times;</span>`;
        if (u) item.title = `${u.name} (${u.metal_cost}M ${u.energy_cost}E)`;
        item.querySelector('.q-remove').addEventListener('click', (e) => {
            e.stopPropagation();
            editorQueues[queueId].splice(i, 1);
            renderQueue(queueId);
        });
        el.appendChild(item);
    });

    // Init SortableJS
    if (typeof Sortable !== 'undefined' && !el._sortable) {
        el._sortable = new Sortable(el, {
            animation: 150,
            ghostClass: 'sortable-ghost',
            onEnd: (evt) => {
                const arr = editorQueues[queueId];
                const [moved] = arr.splice(evt.oldIndex, 1);
                arr.splice(evt.newIndex, 0, moved);
            },
        });
    }
}

// Pool tab switching
document.querySelectorAll('.pool-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.pool-tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        populateEditorUnitList(tab.dataset.pool);
    });
});

// Load BO into editor
document.getElementById('ed-load-btn').addEventListener('click', async () => {
    const filename = document.getElementById('ed-load-select').value;
    if (!filename) return;
    const bo = await api(`/build-orders/${filename}`);
    document.getElementById('ed-name').value = bo.name;
    document.getElementById('ed-wind').value = bo.map_config.avg_wind;
    document.getElementById('ed-mex-value').value = bo.map_config.mex_value;
    document.getElementById('ed-mex-spots').value = bo.map_config.mex_spots;
    document.getElementById('ed-has-geo').checked = bo.map_config.has_geo;

    editorQueues.commander = bo.commander_queue || [];
    editorQueues.factory_0 = (bo.factory_queues && bo.factory_queues.factory_0) || [];
    editorQueues.con_1 = (bo.constructor_queues && bo.constructor_queues.con_1) || [];

    renderQueue('commander');
    renderQueue('factory_0');
    renderQueue('con_1');
});

// Simulate from editor
document.getElementById('ed-sim-btn').addEventListener('click', async () => {
    const bo = getEditorBuildOrder();
    const result = await api('/simulate', {
        method: 'POST',
        body: JSON.stringify({ build_order: bo, duration: 600 }),
    });
    // Switch to simulate tab and render
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    document.querySelector('[data-tab="simulate"]').classList.add('active');
    document.getElementById('tab-simulate').classList.add('active');
    renderSimResults(result);
    document.getElementById('sim-results').classList.remove('hidden');
});

// Save
document.getElementById('ed-save-btn').addEventListener('click', async () => {
    const bo = getEditorBuildOrder();
    const name = document.getElementById('ed-name').value || 'untitled';
    const filename = name.toLowerCase().replace(/[^a-z0-9]+/g, '_') + '.yaml';
    await api('/save', {
        method: 'POST',
        body: JSON.stringify({ build_order: bo, filename }),
    });
    alert(`Saved as ${filename}`);
    loadBuildOrders();
});

// Clear
document.getElementById('ed-clear-btn').addEventListener('click', () => {
    editorQueues = { commander: [], factory_0: [], con_1: [] };
    renderQueue('commander');
    renderQueue('factory_0');
    renderQueue('con_1');
    document.getElementById('ed-name').value = 'Untitled';
});

function getEditorBuildOrder() {
    return {
        name: document.getElementById('ed-name').value,
        map_config: {
            avg_wind: parseFloat(document.getElementById('ed-wind').value),
            mex_value: parseFloat(document.getElementById('ed-mex-value').value),
            mex_spots: parseInt(document.getElementById('ed-mex-spots').value),
            has_geo: document.getElementById('ed-has-geo').checked,
        },
        commander_queue: editorQueues.commander,
        factory_queues: { factory_0: editorQueues.factory_0 },
        constructor_queues: { con_1: editorQueues.con_1 },
    };
}

// ============================================================
// COMPARE TAB
// ============================================================

document.getElementById('cmp-run-btn').addEventListener('click', async () => {
    const fileA = document.getElementById('cmp-a-select').value;
    const fileB = document.getElementById('cmp-b-select').value;
    if (!fileA || !fileB) return alert('Select two build orders');
    const duration = parseInt(document.getElementById('cmp-duration').value);

    document.getElementById('cmp-run-btn').disabled = true;
    try {
        const data = await api('/compare', {
            method: 'POST',
            body: JSON.stringify({ filenames: [fileA, fileB], duration }),
        });
        renderCompare(data.results);
        document.getElementById('cmp-results').classList.remove('hidden');
    } finally {
        document.getElementById('cmp-run-btn').disabled = false;
    }
});

function renderCompare(results) {
    if (results.length < 2) return;
    const [a, b] = results;
    const labelsA = a.snapshots.map(s => fmtTime(s.tick));

    const makeOverlay = (canvasId, fieldFn, labelA, labelB) => {
        destroyChart(canvasId);
        const ctx = document.getElementById(canvasId).getContext('2d');
        charts[canvasId] = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labelsA,
                datasets: [
                    { label: `${a.build_order_name}`, data: a.snapshots.map(fieldFn),
                      borderColor: '#00e5ff', tension: 0.3, pointRadius: 0, borderWidth: 2 },
                    { label: `${b.build_order_name}`, data: b.snapshots.map(fieldFn),
                      borderColor: '#ff9800', tension: 0.3, pointRadius: 0, borderWidth: 2 },
                ],
            },
            options: makeChartOpts(),
        });
    };

    makeOverlay('chart-cmp-metal', s => s.metal_income);
    makeOverlay('chart-cmp-energy', s => s.energy_income);
    makeOverlay('chart-cmp-army', s => s.army_value_metal);
    makeOverlay('chart-cmp-bp', s => s.build_power);

    // Milestone comparison
    const msTbody = document.querySelector('#cmp-milestones tbody');
    msTbody.innerHTML = '';
    const milestoneKeys = ['first_factory', 'first_scout', 'first_constructor', 'first_nano'];
    const milestoneLabels = ['First Factory', 'First Scout', 'First Constructor', 'First Nano'];
    milestoneKeys.forEach((key, i) => {
        const msA = a.milestones.find(m => m.event === key);
        const msB = b.milestones.find(m => m.event === key);
        const tA = msA ? msA.tick : null;
        const tB = msB ? msB.tick : null;
        let winner = '--';
        if (tA && tB) winner = tA < tB ? 'A' : tB < tA ? 'B' : 'Tie';
        else if (tA) winner = 'A';
        else if (tB) winner = 'B';
        msTbody.innerHTML += `<tr><td>${milestoneLabels[i]}</td>
            <td class="color-a">${tA ? fmtTime(tA) : '--'}</td>
            <td class="color-b">${tB ? fmtTime(tB) : '--'}</td>
            <td class="winner">${winner}</td></tr>`;
    });

    // Economy comparison at checkpoints
    const ecoTbody = document.querySelector('#cmp-economy tbody');
    ecoTbody.innerHTML = '';
    [180, 300, 420].forEach(t => {
        const snapA = findSnapshotAt(a, t);
        const snapB = findSnapshotAt(b, t);
        ecoTbody.innerHTML += `<tr style="background:var(--bg-tertiary)"><td colspan="3"><strong>@ ${fmtTime(t)}</strong></td></tr>`;
        ecoTbody.innerHTML += `<tr><td>Metal /s</td>
            <td class="color-a">${snapA ? fmtRate(snapA.metal_income) : '--'}</td>
            <td class="color-b">${snapB ? fmtRate(snapB.metal_income) : '--'}</td></tr>`;
        ecoTbody.innerHTML += `<tr><td>Energy /s</td>
            <td class="color-a">${snapA ? fmtRate(snapA.energy_income) : '--'}</td>
            <td class="color-b">${snapB ? fmtRate(snapB.energy_income) : '--'}</td></tr>`;
        ecoTbody.innerHTML += `<tr><td>Army Value</td>
            <td class="color-a">${snapA ? snapA.army_value_metal.toFixed(0) : '--'}</td>
            <td class="color-b">${snapB ? snapB.army_value_metal.toFixed(0) : '--'}</td></tr>`;
    });

    ecoTbody.innerHTML += `<tr style="background:var(--bg-tertiary)"><td colspan="3"><strong>Stalling</strong></td></tr>`;
    ecoTbody.innerHTML += `<tr><td>Metal Stall</td>
        <td class="color-a">${a.total_metal_stall_seconds}s</td>
        <td class="color-b">${b.total_metal_stall_seconds}s</td></tr>`;
    ecoTbody.innerHTML += `<tr><td>Energy Stall</td>
        <td class="color-a">${a.total_energy_stall_seconds}s</td>
        <td class="color-b">${b.total_energy_stall_seconds}s</td></tr>`;
}

function findSnapshotAt(result, tick) {
    let best = null;
    for (const s of result.snapshots) {
        if (s.tick <= tick) best = s;
        else break;
    }
    return best;
}

// ============================================================
// OPTIMIZE TAB
// ============================================================

document.getElementById('opt-run-btn').addEventListener('click', async () => {
    const req = {
        goal: document.getElementById('opt-goal').value,
        target_time: parseInt(document.getElementById('opt-target-time').value),
        duration: parseInt(document.getElementById('opt-duration').value),
        generations: parseInt(document.getElementById('opt-generations').value),
        pop_size: parseInt(document.getElementById('opt-pop-size').value),
        map_config: {
            avg_wind: parseFloat(document.getElementById('opt-wind').value),
            mex_value: parseFloat(document.getElementById('opt-mex-value').value),
            mex_spots: parseInt(document.getElementById('opt-mex-spots').value),
        },
        start_from: document.getElementById('opt-start-from').value || null,
    };

    document.getElementById('opt-run-btn').disabled = true;
    document.getElementById('opt-cancel-btn').classList.remove('hidden');
    document.getElementById('opt-progress').classList.remove('hidden');
    document.getElementById('opt-result').classList.add('hidden');

    const fitnessData = [];

    // SSE connection
    const response = await fetch('/api/optimize', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(req),
    });

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        // Parse SSE events
        const lines = buffer.split('\n');
        buffer = lines.pop(); // Keep incomplete line

        let eventType = null;
        for (const line of lines) {
            if (line.startsWith('event: ')) {
                eventType = line.slice(7).trim();
            } else if (line.startsWith('data: ') && eventType) {
                try {
                    const data = JSON.parse(line.slice(6));
                    if (eventType === 'progress') {
                        handleOptProgress(data, fitnessData);
                    } else if (eventType === 'complete') {
                        handleOptComplete(data);
                    }
                } catch (e) { /* skip malformed */ }
                eventType = null;
            }
        }
    }

    document.getElementById('opt-run-btn').disabled = false;
    document.getElementById('opt-cancel-btn').classList.add('hidden');
});

function handleOptProgress(data, fitnessData) {
    const pct = Math.round((data.generation / data.total_generations) * 100);
    document.getElementById('opt-progress-bar').style.width = pct + '%';
    document.getElementById('opt-progress-text').textContent =
        `Gen ${data.generation}/${data.total_generations} | Best: ${data.best_score} | ` +
        `Gen best: ${data.gen_best} | Mutation: ${data.mutation_rate} | Stagnation: ${data.stagnation}`;

    fitnessData.push(data.best_score);

    // Update fitness chart
    destroyChart('opt-fitness');
    const ctx = document.getElementById('chart-opt-fitness').getContext('2d');
    charts['opt-fitness'] = new Chart(ctx, {
        type: 'line',
        data: {
            labels: fitnessData.map((_, i) => i),
            datasets: [{
                label: 'Best Fitness',
                data: fitnessData,
                borderColor: '#69f0ae',
                tension: 0.3,
                pointRadius: 0,
                borderWidth: 2,
            }],
        },
        options: makeChartOpts(),
    });
}

function handleOptComplete(data) {
    optimizeResult = data;
    document.getElementById('opt-result').classList.remove('hidden');

    // Display build order
    const display = document.getElementById('opt-bo-display');
    const bo = data.build_order;
    let html = `<strong>${bo.name}</strong><br><br>`;
    html += '<strong>Commander Queue:</strong><br>';
    bo.commander_queue.forEach((key, i) => {
        const u = units[key];
        html += `  ${i + 1}. ${key} (${u ? u.name : key})<br>`;
    });
    for (const [fid, q] of Object.entries(bo.factory_queues)) {
        html += `<br><strong>${fid} Queue:</strong><br>`;
        q.forEach((key, i) => {
            const u = units[key];
            html += `  ${i + 1}. ${key} (${u ? u.name : key})<br>`;
        });
    }
    for (const [cid, q] of Object.entries(bo.constructor_queues)) {
        html += `<br><strong>${cid} Queue:</strong><br>`;
        q.forEach((key, i) => {
            const u = units[key];
            html += `  ${i + 1}. ${key} (${u ? u.name : key})<br>`;
        });
    }
    display.innerHTML = html;

    // Render fitness history from complete data
    if (data.history) {
        destroyChart('opt-fitness');
        const ctx = document.getElementById('chart-opt-fitness').getContext('2d');
        charts['opt-fitness'] = new Chart(ctx, {
            type: 'line',
            data: {
                labels: data.history.map((_, i) => i),
                datasets: [{
                    label: 'Best Fitness',
                    data: data.history,
                    borderColor: '#69f0ae',
                    tension: 0.3,
                    pointRadius: 0,
                    borderWidth: 2,
                }],
            },
            options: makeChartOpts(),
        });
    }
}

// Load optimized BO into editor
document.getElementById('opt-load-editor').addEventListener('click', () => {
    if (!optimizeResult) return;
    const bo = optimizeResult.build_order;
    document.getElementById('ed-name').value = bo.name;
    editorQueues.commander = bo.commander_queue || [];
    editorQueues.factory_0 = (bo.factory_queues && bo.factory_queues.factory_0) || [];
    editorQueues.con_1 = (bo.constructor_queues && bo.constructor_queues.con_1) || [];
    renderQueue('commander');
    renderQueue('factory_0');
    renderQueue('con_1');

    // Switch to editor tab
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    document.querySelector('[data-tab="editor"]').classList.add('active');
    document.getElementById('tab-editor').classList.add('active');
});

// Save optimized BO
document.getElementById('opt-save-btn').addEventListener('click', async () => {
    if (!optimizeResult) return;
    const bo = optimizeResult.build_order;
    const filename = bo.name.toLowerCase().replace(/[^a-z0-9]+/g, '_') + '.yaml';
    await api('/save', {
        method: 'POST',
        body: JSON.stringify({ build_order: bo, filename }),
    });
    alert(`Saved as ${filename}`);
    loadBuildOrders();
});

// View full sim results for optimized BO
document.getElementById('opt-sim-btn').addEventListener('click', () => {
    if (!optimizeResult || !optimizeResult.result) return;
    // Show economy + stored charts for the optimized result
    const result = optimizeResult.result;
    const labels = result.snapshots.map(s => fmtTime(s.tick));
    const allAnnotations = {
        ...stallAnnotations(result.stall_events),
        ...milestoneAnnotations(result.milestones),
    };

    destroyChart('opt-economy');
    const ecoCtx = document.getElementById('chart-opt-economy').getContext('2d');
    const ecoOpts = makeChartOpts();
    ecoOpts.plugins.annotation = { annotations: allAnnotations };
    charts['opt-economy'] = new Chart(ecoCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                { label: 'Metal /s', data: result.snapshots.map(s => s.metal_income),
                  borderColor: '#00e5ff', backgroundColor: 'rgba(0,229,255,0.1)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
                { label: 'Energy /s', data: result.snapshots.map(s => s.energy_income),
                  borderColor: '#ffd740', backgroundColor: 'rgba(255,215,64,0.1)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
            ],
        },
        options: ecoOpts,
    });

    destroyChart('opt-stored');
    const storedCtx = document.getElementById('chart-opt-stored').getContext('2d');
    charts['opt-stored'] = new Chart(storedCtx, {
        type: 'line',
        data: {
            labels,
            datasets: [
                { label: 'Metal Stored', data: result.snapshots.map(s => s.metal_stored),
                  borderColor: '#00e5ff', backgroundColor: 'rgba(0,229,255,0.05)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
                { label: 'Energy Stored', data: result.snapshots.map(s => s.energy_stored),
                  borderColor: '#ffd740', backgroundColor: 'rgba(255,215,64,0.05)',
                  fill: true, tension: 0.3, pointRadius: 0, borderWidth: 2 },
            ],
        },
        options: makeChartOpts(),
    });

    document.getElementById('opt-sim-results').classList.remove('hidden');
});

// ============================================================
// Boot
// ============================================================

(async function init() {
    await loadUnits();
    await loadBuildOrders();
    populateEditorUnitList();
    renderQueue('commander');
    renderQueue('factory_0');
    renderQueue('con_1');
})();
