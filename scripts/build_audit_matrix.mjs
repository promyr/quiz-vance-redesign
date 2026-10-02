import fs from 'node:fs';

const root = new URL('../', import.meta.url);
const planPath = new URL('docs/MASTER_SYSTEM_AUDIT_PLAN.md', root);
const matrixPath = new URL('audit/AUDIT_CONTROL_MATRIX.json', root);
const plan = fs.readFileSync(planPath, 'utf8');
const existing = fs.existsSync(matrixPath)
  ? JSON.parse(fs.readFileSync(matrixPath, 'utf8'))
  : { requirements: [] };
const previousById = new Map(
  (existing.requirements ?? []).map((requirement) => [requirement.id, requirement]),
);

let sectionNumber = '00';
let sectionTitle = 'Governança';
const requirements = [];
const lines = plan.split(/\r?\n/);

for (let index = 0; index < lines.length; index += 1) {
  const heading = lines[index].match(/^## (\d+)\.\s+(.+)$/);
  if (heading) {
    sectionNumber = heading[1].padStart(2, '0');
    sectionTitle = heading[2];
    continue;
  }

  const item = lines[index].match(
    /^- \[ \] \*\*\[(AUDIT-\d{2}-\d{3})\]\*\*\s+(.+)$/,
  );
  if (!item) continue;

  const description = [item[2]];
  while (index + 1 < lines.length && /^  \S/.test(lines[index + 1])) {
    index += 1;
    description.push(lines[index].trim());
  }

  const previous = previousById.get(item[1]) ?? {};
  requirements.push({
    id: item[1],
    domain: `${sectionNumber} - ${sectionTitle}`,
    requirement: description.join(' '),
    risk: null,
    environments_profiles: [],
    test_type: null,
    procedure: null,
    expected_result: null,
    evidence: [],
    status: 'not_started',
    severity: null,
    component_refs: [],
    owner: null,
    reviewer: null,
    commit: null,
    version: null,
    dependencies: [],
    ...previous,
    id: item[1],
    domain: `${sectionNumber} - ${sectionTitle}`,
    requirement: description.join(' '),
  });
}

const matrix = {
  schema_version: 1,
  plan_version: '1.1',
  baseline: 'Quiz Vance 2.0.35+34',
  inventory: existing.inventory ?? {
    complete: false,
    generated_from: [
      'Flutter routes/features/providers/storage',
      'FastAPI OpenAPI/decorators',
      'SQLAlchemy models/Alembic migrations',
      'jobs/schedulers/Telegram commands',
      'configuration names/workflows/manifests/dependencies/artifacts',
    ],
    components: [],
  },
  provenance: existing.provenance ?? {
    commit: null,
    clean_tree: null,
    toolchains: {},
    lockfiles: {},
    alembic_head: null,
    fly_image_digest: null,
    apk_certificate_sha256: null,
    apk_sha256: null,
    public_url: null,
    downloaded_sha256: null,
    telegram_message_id: null,
  },
  requirements,
};

fs.mkdirSync(new URL('audit/', root), { recursive: true });
fs.writeFileSync(matrixPath, `${JSON.stringify(matrix, null, 2)}\n`, 'utf8');
console.log(`Matriz atualizada: ${requirements.length} requisitos.`);
