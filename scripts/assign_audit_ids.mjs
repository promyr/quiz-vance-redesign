import fs from 'node:fs';

const planPath = new URL('../docs/MASTER_SYSTEM_AUDIT_PLAN.md', import.meta.url);
const original = fs.readFileSync(planPath, 'utf8');
let section = '00';
const nextBySection = new Map();

for (const match of original.matchAll(/\[AUDIT-(\d{2})-(\d{3})\]/g)) {
  const current = nextBySection.get(match[1]) ?? 0;
  nextBySection.set(match[1], Math.max(current, Number(match[2])));
}

const updated = original
  .split(/\r?\n/)
  .map((line) => {
    const heading = line.match(/^## (\d+)\./);
    if (heading) {
      section = heading[1].padStart(2, '0');
    }

    if (!line.startsWith('- [ ] ')) {
      return line;
    }

    if (/^- \[ \] \*\*\[AUDIT-\d{2}-\d{3}\]\*\*/.test(line)) {
      return line;
    }

    const next = (nextBySection.get(section) ?? 0) + 1;
    nextBySection.set(section, next);
    const id = `AUDIT-${section}-${String(next).padStart(3, '0')}`;
    return line.replace('- [ ] ', `- [ ] **[${id}]** `);
  })
  .join('\n');

fs.writeFileSync(planPath, updated, 'utf8');
