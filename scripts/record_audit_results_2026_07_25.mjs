import fs from 'node:fs';

const root = new URL('../', import.meta.url);
const matrixPath = new URL('audit/AUDIT_CONTROL_MATRIX.json', root);
const matrix = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));
const requirementById = new Map(
  matrix.requirements.map((requirement) => [requirement.id, requirement]),
);
const componentByPath = new Map();

for (const component of matrix.inventory.components) {
  const entries = componentByPath.get(component.path) ?? [];
  entries.push(component);
  componentByPath.set(component.path, entries);
}

const findings = [
  {
    severity: 'P0',
    summary: 'Credencial Telegram exposta em arquivos e propagável para logs/banco.',
    ids: ['AUDIT-23-001', 'AUDIT-23-005', 'AUDIT-27-006', 'AUDIT-28-001', 'AUDIT-28-011', 'AUDIT-28-013'],
    paths: ['scripts/upload_apk_telegram.py', 'scripts/get_tele_token.ps1', 'backend/app/telegram_bot.py', 'backend/app/main.py'],
  },
  {
    severity: 'P1',
    summary: 'Checkout pode ativar Premium sem pagamento, valor, moeda ou plano verificados.',
    ids: ['AUDIT-19-003', 'AUDIT-19-004', 'AUDIT-19-009', 'AUDIT-20-002', 'AUDIT-21-006'],
    paths: ['backend/app/main.py', 'backend/app/services.py'],
  },
  {
    severity: 'P1',
    summary: 'Webhooks Mercado Pago/Telegram têm autenticação ou atomicidade incorretas.',
    ids: ['AUDIT-19-005', 'AUDIT-19-007', 'AUDIT-20-007', 'AUDIT-23-002', 'AUDIT-28-003'],
    paths: ['backend/app/main.py'],
  },
  {
    severity: 'P1',
    summary: 'Operações administrativas sensíveis não exigem MFA/step-up.',
    ids: ['AUDIT-10-013', 'AUDIT-10-014', 'AUDIT-28-008'],
    paths: ['backend/app/routers/admin_ai.py'],
  },
  {
    severity: 'P1',
    summary: 'HTTP 429 de provedor é exibido como falta de Premium/quota do usuário.',
    ids: ['AUDIT-11-005', 'AUDIT-11-006', 'AUDIT-11-009', 'AUDIT-12-006', 'AUDIT-13-001', 'AUDIT-14-005'],
    paths: ['lib/features/quiz/data/quiz_repository.dart', 'lib/features/simulado/data/simulado_repository.dart', 'lib/features/open_quiz/data/open_quiz_repository.dart'],
  },
  {
    severity: 'P1',
    summary: 'Resultados anunciados como offline não são persistidos nem enfileirados.',
    ids: ['AUDIT-12-009', 'AUDIT-13-004', 'AUDIT-17-004', 'AUDIT-17-005', 'AUDIT-17-007', 'AUDIT-22-005', 'AUDIT-22-007'],
    paths: ['lib/features/quiz/presentation/quiz_result_screen.dart', 'lib/features/simulado/presentation/simulado_result_screen.dart', 'lib/shared/application/offline_sync_queue.dart'],
  },
  {
    severity: 'P1',
    summary: 'Falha do keystore pode criar chave efêmera e tornar o SQLCipher ilegível.',
    ids: ['AUDIT-08-001', 'AUDIT-08-006', 'AUDIT-22-002', 'AUDIT-22-003', 'AUDIT-22-008'],
    paths: ['lib/core/storage/local_storage.dart', 'lib/main.dart'],
  },
  {
    severity: 'P1',
    summary: 'SRS ignora estado anterior e sincronização pode perder revisão local.',
    ids: ['AUDIT-15-002', 'AUDIT-15-003', 'AUDIT-15-004', 'AUDIT-15-006'],
    paths: ['lib/features/flashcard/data/flashcard_repository.dart', 'lib/features/flashcard/presentation/flashcard_screen.dart'],
  },
  {
    severity: 'P1',
    summary: 'Migração e reordenação de chaves administrativas não são atômicas.',
    ids: ['AUDIT-10-007', 'AUDIT-10-009', 'AUDIT-10-011'],
    paths: ['lib/features/settings/data/admin_master_keys_service.dart'],
  },
  {
    severity: 'P1',
    summary: 'Release não possui proveniência reproduzível e contém artefatos antigos concorrentes.',
    ids: ['AUDIT-07-001', 'AUDIT-07-003', 'AUDIT-23-005', 'AUDIT-26-001', 'AUDIT-26-015', 'AUDIT-26-016', 'AUDIT-27-020', 'AUDIT-27-021', 'AUDIT-27-022'],
    paths: ['scripts/build_release.ps1', 'scripts/upload_apk_telegram.py'],
  },
  {
    severity: 'P1',
    summary: 'CI não prova flavor production, assinatura, backend gates, SBOM ou supply chain.',
    ids: ['AUDIT-26-005', 'AUDIT-27-001', 'AUDIT-27-015', 'AUDIT-27-016', 'AUDIT-27-017', 'AUDIT-27-018', 'AUDIT-27-019'],
    paths: ['.github/workflows/build.yml', 'android/app/build.gradle', 'backend/Dockerfile'],
  },
  {
    severity: 'P1',
    summary: 'Migration acoplada ao startup e compatibilidade N−1/N−2 não comprovada.',
    ids: ['AUDIT-21-002', 'AUDIT-21-003', 'AUDIT-21-010', 'AUDIT-27-010', 'AUDIT-27-023', 'AUDIT-27-024'],
    paths: ['backend/Dockerfile', 'backend/alembic/versions/20260725_17_admin_ai_gateway.py'],
  },
];

const severityRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
for (const finding of findings) {
  const components = finding.paths.flatMap((path) => componentByPath.get(path) ?? []);
  const componentIds = [...new Set(components.map((component) => component.id))];
  for (const id of finding.ids) {
    const requirement = requirementById.get(id);
    if (!requirement) throw new Error(`Unknown audit requirement: ${id}`);
    if (
      requirement.severity === null ||
      severityRank[finding.severity] < severityRank[requirement.severity]
    ) {
      requirement.severity = finding.severity;
    }
    requirement.status = 'failed';
    requirement.risk = requirement.risk
      ? `${requirement.risk} | ${finding.summary}`
      : finding.summary;
    requirement.environments_profiles = ['source', 'test', 'production-read-only'];
    requirement.test_type = 'static_review_and_safe_smoke';
    requirement.procedure = 'Plano Mestre 1.1, revisão independente e comandos reproduzíveis do relatório diário.';
    requirement.expected_result = requirement.requirement;
    requirement.evidence = [
      ...new Set([
        ...requirement.evidence,
        'audit/AUDIT_REPORT_2026-07-25.md',
      ]),
    ];
    requirement.component_refs = [
      ...new Set([...requirement.component_refs, ...componentIds]),
    ];
    requirement.owner = 'CTO Agent';
    requirement.reviewer = 'Reviewer Gate Agent';
    requirement.commit = 'c37c842f28451d6e04498b6ff86ce50619e75486';
    requirement.version = '2.0.35+34';

    for (const component of components) {
      component.requirement_ids = [
        ...new Set([...component.requirement_ids, id]),
      ];
    }
  }
}

matrix.inventory.complete = false;
matrix.provenance = {
  ...matrix.provenance,
  commit: 'c37c842f28451d6e04498b6ff86ce50619e75486',
  clean_tree: false,
  alembic_head: '20260725_17',
  apk_certificate_sha256:
    'b039a11e96aafa7107be445bd6404516ada37962c0b735c059939ea15ca67215',
  apk_sha256:
    '51ABDA91FCC94BF87BD7906D1E2E281CD6CEF3A6A3D1A7E48DBE6442C3AFE73E',
  public_url:
    'https://quiz-vance-redesign-backend.fly.dev/app/download/android/latest.apk',
  downloaded_sha256:
    '51ABDA91FCC94BF87BD7906D1E2E281CD6CEF3A6A3D1A7E48DBE6442C3AFE73E',
};

fs.writeFileSync(matrixPath, `${JSON.stringify(matrix, null, 2)}\n`, 'utf8');
console.log(`Resultados registrados: ${findings.length} grupos de achados.`);
