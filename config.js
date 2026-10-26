// Cole aqui os dados do seu projeto Supabase (Project Settings > API)
const SUPABASE_URL = 'https://yfgynmdkjsadtscywpmo.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_UoWzUf3KfWF5TZkZOuWx7Q_6BNU8dHC';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Utilidades compartilhadas
const pad = n => String(n).padStart(3, '0');
const POR_FAIXA = 100;

// Abas 001–100, 101–200… com quantos livres em cada
function barraFaixas(total, atual, ocupados, onpick) {
  const abas = [];
  for (let i = 0; i * POR_FAIXA < total; i++) {
    const ini = i * POR_FAIXA + 1, fim = Math.min((i + 1) * POR_FAIXA, total);
    let livres = fim - ini + 1;
    for (let n = ini; n <= fim; n++) if (ocupados.has(n)) livres--;
    abas.push(h('button', { class: 'tab' + (i === atual ? ' on' : ''), 'aria-pressed': i === atual ? 'true' : 'false', onclick: () => onpick(i) },
      pad(ini) + '–' + pad(fim), h('small', null, livres + ' livres')));
  }
  return h('div', { class: 'tabs' }, abas);
}
const brl = v => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const COLORS = ['#f2c230', '#1f4fb3', '#d23a2c', '#5b2d8e', '#ee7a1e', '#1d7a3e', '#7a1f24', '#161616'];

function fmtData(d) {
  if (!d) return 'data a definir';
  const x = new Date(d + 'T12:00:00');
  return isNaN(x) ? d : x.toLocaleDateString('pt-BR', { day: '2-digit', month: 'long', year: 'numeric' });
}

function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') e.className = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (v === true) e.setAttribute(k, '');
    else if (v !== false && v != null) e.setAttribute(k, v);
  }
  (function add(list) {
    list.forEach(c => {
      if (c == null || c === false) return;
      if (Array.isArray(c)) return add(c);
      e.append(c.nodeType ? c : document.createTextNode(String(c)));
    });
  })(kids);
  return e;
}

function bola(n, status, extraClass, onclick) {
  const k = ((n - 1) % 15) + 1;
  const b = h('button', {
    class: 'ball' + (k > 8 ? ' stripe' : '') + (extraClass ? ' ' + extraClass : ''),
    style: '--c:' + COLORS[(k - 1) % 8],
    'aria-label': 'Número ' + pad(n) + ' (' + status + ')',
    onclick
  }, h('b', null, pad(n)));
  if (status === 'pago') b.append(h('span', { class: 'tag pago' }, 'pago'));
  if (status === 'reservado') b.append(h('span', { class: 'tag res' }, 'res.'));
  return b;
}

function waLink(numero, texto) {
  const d = String(numero || '').replace(/\D/g, '');
  if (!d) return null;
  return 'https://wa.me/' + (d.length <= 11 ? '55' + d : d) + '?text=' + encodeURIComponent(texto);
}

async function copiar(texto, btn) {
  try {
    await navigator.clipboard.writeText(texto);
    const o = btn.textContent; btn.textContent = 'Copiado';
    setTimeout(() => (btn.textContent = o), 1500);
  } catch (e) { prompt('Copie:', texto); }
}

function erroMsg(e) {
  return (e && (e.message || e.error_description)) || 'Erro inesperado. Tente de novo.';
}
