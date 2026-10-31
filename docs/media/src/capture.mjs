// Drives headless Chrome over the DevTools protocol (no packages: Node has WebSocket built in),
// plays a scripted scene on the temporary page and saves a PNG every few dozen milliseconds.
import {spawn,spawnSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [,, scene, outRoot] = process.argv;
// Set CHROME_PATH on other systems. Any Chromium-based browser works.
const CHROME = process.env.CHROME_PATH ?? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PORT = 9333;
const W = 1000, H = 560;

const scenes = {
  connect: {
    end: 10600,
    steps: [
      [900, `scene.moveTo('.telegram-form .primary')`],
      [1700, `scene.click()`],
      [1800, `document.querySelector('.telegram-form').requestSubmit()`],
      [2900, `scene.moveTo('.telegram-pending a.primary')`],
      [3700, `scene.click()`],
      [3900, `scene.moveTo('#start-btn')`],
      [4800, `scene.click()`],
      [4900, `scene.phone('input'); scene.say('me','/start')`],
      [5400, `scene.typing(true)`],
      [6200, `scene.say('bot','✅ Telegram conectado! As despesas vão para Conta principal. Mande algo como: almoço 32,50'); scene.linked(true)`],
    ],
  },
  register: {
    end: 9800,
    steps: [
      [1000, `scene.say('me','almoço 32,50')`],
      [1700, `scene.typing(true)`],
      [2500, `scene.say('bot','✅ Registrado: almoço - R$ 32,50 em Conta do salário (Alimentação)'); scene.addTx('almoço',3250,'cat-1')`],
      [4900, `scene.say('me','uber 18,90')`],
      [5600, `scene.typing(true)`],
      [6400, `scene.say('bot','✅ Registrado: uber - R$ 18,90 em Conta do salário (Transporte)'); scene.addTx('uber',1890,'cat-2')`],
    ],
  },
  workflow: {
    end: 7600,
    steps: [
      [300, `scene.hl(['Telegram Trigger'])`],
      [1100, `scene.hl(['Telegram Trigger','Interpretar mensagem'])`],
      [1900, `scene.hl(['Telegram Trigger','Interpretar mensagem','É conexão?'])`],
      [2700, `scene.hl(['Telegram Trigger','Interpretar mensagem','É conexão?','É despesa?'])`],
      [3500, `scene.hl(['Telegram Trigger','Interpretar mensagem','É conexão?','É despesa?','Gravar no Cifro'])`],
      [4300, `scene.hl(['Telegram Trigger','Interpretar mensagem','É conexão?','É despesa?','Gravar no Cifro','Gravou?'])`],
      [5100, `scene.hl(['Telegram Trigger','Interpretar mensagem','É conexão?','É despesa?','Gravar no Cifro','Gravou?','Confirmar no Telegram'])`],
    ],
  },
};
const plan = scenes[scene];
if (!plan) throw new Error('cena desconhecida: ' + scene);

const dir = path.join(outRoot, scene);
fs.rmSync(dir, {recursive: true, force: true});
fs.mkdirSync(dir, {recursive: true});

const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cifro-media-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--force-device-scale-factor=1', `--window-size=${W},${H + 100}`,
  '--no-first-run', '--no-default-browser-check', '--disable-extensions', 'about:blank',
], {stdio: 'ignore'});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitForChrome() {
  for (let i = 0; i < 60; i++) {
    try { return await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); } catch { await sleep(250); }
  }
  throw new Error('Chrome não respondeu');
}

try {
  const targets = await waitForChrome();
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let id = 0; const pending = new Map();
  const shots = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    else if (m.method === 'Page.screencastFrame') {
      shots.push({data: m.params.data, ts: m.params.metadata.timestamp * 1000});
      send('Page.screencastFrameAck', {sessionId: m.params.sessionId}).catch(() => {});
    }
  };
  const send = (method, params = {}) => new Promise((res, rej) => {
    const myId = ++id; pending.set(myId, (m) => (m.error ? rej(new Error(`${method}: ${m.error.message}`)) : res(m.result)));
    ws.send(JSON.stringify({id: myId, method, params}));
  });
  const evaluate = async (expression) => {
    const r = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
    if (r.exceptionDetails) throw new Error('JS: ' + (r.exceptionDetails.exception?.description ?? r.exceptionDetails.text));
    return r.result.value;
  };

  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', {width: W, height: H, deviceScaleFactor: 1, mobile: false});
  await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'dark'}]});
  await send('Page.navigate', {url: `http://localhost:5173/media-scenes?s=${scene}`});
  for (let i = 0; i < 200; i++) { if (await evaluate('window.__ready === true').catch(() => false)) break; await sleep(300); }
  if (!(await evaluate('window.__ready === true'))) throw new Error('a página não ficou pronta');
  await evaluate('window.scene.reset()');
  await sleep(400);

  const steps = [...plan.steps];
  await send('Page.startScreencast', {format: 'jpeg', quality: 92, maxWidth: W, maxHeight: H, everyNthFrame: 1});
  await sleep(150);
  const t0 = Date.now();
  while (Date.now() - t0 < plan.end) {
    const now = Date.now() - t0;
    while (steps.length && steps[0][0] <= now) { const [, js] = steps.shift(); await evaluate(js); }
    await sleep(8);
  }
  await send('Page.stopScreencast');
  await sleep(150);
  const base = shots.length ? shots[0].ts : 0;
  const frames = shots.map((f, i) => {
    const file = `${String(i).padStart(4, '0')}.jpg`;
    fs.writeFileSync(path.join(dir, file), Buffer.from(f.data, 'base64'));
    return {file, t: Math.round(f.ts - base)};
  });
  fs.writeFileSync(path.join(dir, 'frames.json'), JSON.stringify({end: plan.end, frames}));
  console.log(`${scene}: ${frames.length} quadros, último em ${frames.at(-1)?.t} ms`);
  ws.close();
} finally {
  // taskkill is not on PATH for every shell, so end the browser directly; its helper processes exit with it.
  chrome.kill('SIGKILL');
  await sleep(800);
  for (let k = 0; k < 5; k++) { try { fs.rmSync(profile, {recursive: true, force: true}); break; } catch { await sleep(500); } }
}
process.exit(0);
