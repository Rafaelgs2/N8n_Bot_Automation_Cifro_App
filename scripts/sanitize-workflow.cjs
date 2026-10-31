#!/usr/bin/env node
// Turns an n8n export into something safe to publish: no credential ids, no project URL, no webhook ids,
// no instance metadata. Usage: node scripts/sanitize-workflow.cjs < export.json > workflows/cifro-telegram.json
//
// It refuses to write anything when the result still looks like it holds a secret, so a mistake stops here
// instead of reaching a commit.
const fs = require('fs');

const raw = fs.readFileSync(0, 'utf8');
// `n8n export:workflow` can print log lines before the JSON.
const parsed = JSON.parse(raw.slice(raw.search(/[\[{]/)));
const source = Array.isArray(parsed) ? parsed[0] : parsed;

const PLACEHOLDER_URL = 'https://YOUR-PROJECT.supabase.co';
const scrub = (value) => {
  if (typeof value === 'string') return value.replace(/https:\/\/[a-z0-9]+\.supabase\.co/gi, PLACEHOLDER_URL);
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, scrub(v)]));
  return value;
};

// Node ids carry no information, but `n8n import:workflow` needs them, so derive stable ones from the names.
const stableId = (name) => {
  const h = require('crypto').createHash('md5').update(name).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};

const nodes = source.nodes.map((node) => {
  const clean = { id: stableId(node.name), parameters: scrub(node.parameters), name: node.name, type: node.type, typeVersion: node.typeVersion, position: node.position };
  if (node.onError) clean.onError = node.onError;
  if (node.credentials) {
    // Keep the credential type and its display name so the reader knows what to create.
    clean.credentials = Object.fromEntries(Object.entries(node.credentials).map(([type, c]) => [type, { id: 'REPLACE_ME', name: c.name }]));
  }
  return clean;
});

const output = {
  // The CLI import needs a workflow id as well; the UI import ignores it and creates a new one.
  id: 'cifro-telegram',
  name: source.name,
  nodes,
  connections: source.connections,
  settings: source.settings || {},
};

const text = JSON.stringify(output, null, 2) + '\n';

const suspicious = [
  [/\b[0-9a-f]{64}\b/i, '64-character hex (a secret hash or token)'],
  [/\b\d{8,10}:[A-Za-z0-9_-]{35}\b/, 'Telegram bot token'],
  [/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\./, 'JWT'],
  [/sb_(publishable|secret)_[A-Za-z0-9_-]+/, 'Supabase key'],
  [/"chat_?id"\s*:\s*-?\d{6,}/i, 'hard-coded chat id'],
  [/"(rightValue|leftValue)"\s*:\s*\d{6,}/, 'hard-coded numeric id in a condition'],
  [/https:\/\/(?!YOUR-PROJECT)[a-z0-9]+\.supabase\.co/i, 'real Supabase project URL'],
  [/trycloudflare\.com/i, 'tunnel URL'],
];
const hits = suspicious.filter(([pattern]) => pattern.test(text)).map(([, label]) => label);
if (hits.length) {
  console.error('Recusado: o resultado ainda parece conter ' + hits.join(', ') + '.');
  process.exit(1);
}

process.stdout.write(text);
