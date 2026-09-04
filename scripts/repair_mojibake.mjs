import fs from 'node:fs';
import path from 'node:path';
import { TextDecoder } from 'node:util';

const projectRoot = path.resolve(import.meta.dirname, '..');
const libRoot = path.join(projectRoot, 'lib');
const checkOnly = process.argv.includes('--check');
const utf8Decoder = new TextDecoder('utf-8', { fatal: true });

const windows1252SpecialBytes = new Map([
  [0x20ac, 0x80], [0x201a, 0x82], [0x0192, 0x83], [0x201e, 0x84],
  [0x2026, 0x85], [0x2020, 0x86], [0x2021, 0x87], [0x02c6, 0x88],
  [0x2030, 0x89], [0x0160, 0x8a], [0x2039, 0x8b], [0x0152, 0x8c],
  [0x017d, 0x8e], [0x2018, 0x91], [0x2019, 0x92], [0x201c, 0x93],
  [0x201d, 0x94], [0x2022, 0x95], [0x2013, 0x96], [0x2014, 0x97],
  [0x02dc, 0x98], [0x2122, 0x99], [0x0161, 0x9a], [0x203a, 0x9b],
  [0x0153, 0x9c], [0x017e, 0x9e], [0x0178, 0x9f],
]);

const suspiciousPatterns = [
  '\u00c3',
  '\u00c2',
  '\u00e2\u20ac',
  '\u00e2\u2020',
  '\u00e2\u0153',
  '\u00e2\u201d',
  '\u00f0\u0178',
  '\u00ef\u00b8',
  '\ufffd',
];

function suspicionScore(value) {
  return suspiciousPatterns.reduce((score, pattern) => {
    return score + value.split(pattern).length - 1;
  }, 0);
}

function encodeWindows1252(value) {
  const bytes = [];
  for (const character of value) {
    const codePoint = character.codePointAt(0);
    if (codePoint <= 0xff) {
      bytes.push(codePoint);
      continue;
    }
    const mappedByte = windows1252SpecialBytes.get(codePoint);
    if (mappedByte === undefined) {
      throw new Error('character cannot be represented in Windows-1252');
    }
    bytes.push(mappedByte);
  }
  return Uint8Array.from(bytes);
}

function dartFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return dartFiles(fullPath);
    }
    return entry.isFile() && entry.name.endsWith('.dart') ? [fullPath] : [];
  });
}

let changedFiles = 0;
let changedLines = 0;

for (const filePath of dartFiles(libRoot)) {
  const content = fs.readFileSync(filePath, 'utf8');
  let fileChanged = false;
  const repaired = content
    .split(/(\r\n|\n|\r)/)
    .map((part, index) => {
      if (index % 2 === 1) {
        return part;
      }
      const beforeScore = suspicionScore(part);
      if (beforeScore === 0) {
        return part;
      }
      try {
        const candidate = utf8Decoder.decode(encodeWindows1252(part));
        if (suspicionScore(candidate) >= beforeScore) {
          return part;
        }
        fileChanged = true;
        changedLines += 1;
        return candidate;
      } catch {
        return part;
      }
    })
    .join('');

  if (fileChanged) {
    changedFiles += 1;
    if (!checkOnly) {
      fs.writeFileSync(filePath, repaired, 'utf8');
    }
  }
}

console.log(`CHANGED_FILES=${changedFiles}`);
console.log(`CHANGED_LINES=${changedLines}`);
