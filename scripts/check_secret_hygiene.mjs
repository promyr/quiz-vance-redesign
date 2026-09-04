import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ignoredDirectories = new Set([
  '.dart_tool',
  '.git',
  '.gradle',
  '.venv',
  'audit',
  'build',
  'node_modules',
  'output_apk',
]);
const ignoredExtensions = new Set([
  '.apk',
  '.dex',
  '.jpg',
  '.jpeg',
  '.keystore',
  '.png',
  '.zip',
]);
const patterns = [
  {
    name: 'telegram_bot_token',
    expression: /(?:^|[^A-Za-z0-9])[0-9]{8,12}:[A-Za-z0-9_-]{30,}/,
  },
  {
    name: 'openai_api_key',
    expression: /sk-[A-Za-z0-9_-]{20,}/,
  },
  {
    name: 'google_api_key',
    expression: /AIza[0-9A-Za-z_-]{30,}/,
  },
];

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return ignoredDirectories.has(entry.name) ? [] : walk(absolutePath);
    }
    return [absolutePath];
  });
}

const findings = [];
for (const absolutePath of walk(root)) {
  if (ignoredExtensions.has(path.extname(absolutePath).toLowerCase())) continue;
  let content;
  try {
    content = fs.readFileSync(absolutePath, 'utf8');
  } catch {
    continue;
  }
  for (const pattern of patterns) {
    if (pattern.expression.test(content)) {
      findings.push({
        path: path.relative(root, absolutePath).split(path.sep).join('/'),
        pattern: pattern.name,
      });
    }
  }
}

console.log(
  JSON.stringify(
    {
      ok: findings.length === 0,
      finding_count: findings.length,
      findings,
    },
    null,
    2,
  ),
);
if (findings.length > 0) process.exit(1);
