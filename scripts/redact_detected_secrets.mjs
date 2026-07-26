import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const allowedFiles = new Set(['antigravity-skills-report.md']);
const requestedFiles = process.argv.slice(2);

if (requestedFiles.length === 0) {
  throw new Error('Provide at least one allowlisted file to redact.');
}

for (const relativePath of requestedFiles) {
  const normalized = relativePath.split(path.sep).join('/');
  if (!allowedFiles.has(normalized)) {
    throw new Error(`Refusing to redact a non-allowlisted file: ${normalized}`);
  }
  const absolutePath = path.join(root, normalized);
  const original = fs.readFileSync(absolutePath, 'utf8');
  const redacted = original
    .replaceAll(/sk-[A-Za-z0-9_-]{20,}/g, '<REDACTED_API_KEY>')
    .replaceAll(
      /[0-9]{8,12}:[A-Za-z0-9_-]{30,}/g,
      '<REDACTED_TELEGRAM_TOKEN>',
    )
    .replaceAll(/AIza[0-9A-Za-z_-]{30,}/g, '<REDACTED_GOOGLE_API_KEY>');
  fs.writeFileSync(absolutePath, redacted, 'utf8');
}

console.log(`Redação concluída em ${requestedFiles.length} arquivo(s).`);
