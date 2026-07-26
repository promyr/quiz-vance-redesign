import fs from 'node:fs';

const root = new URL('../', import.meta.url);
const plan = fs.readFileSync(
  new URL('docs/MASTER_SYSTEM_AUDIT_PLAN.md', root),
  'utf8',
);
const matrix = JSON.parse(
  fs.readFileSync(new URL('audit/AUDIT_CONTROL_MATRIX.json', root), 'utf8'),
);
const strict = process.argv.includes('--strict');
const requiredFields = [
  'id',
  'domain',
  'requirement',
  'risk',
  'environments_profiles',
  'test_type',
  'procedure',
  'expected_result',
  'evidence',
  'status',
  'severity',
  'component_refs',
  'owner',
  'reviewer',
  'commit',
  'version',
  'dependencies',
];
const planIds = [
  ...plan.matchAll(/\*\*\[(AUDIT-\d{2}-\d{3})\]\*\*/g),
].map((match) => match[1]);
const matrixIds = matrix.requirements.map((item) => item.id);
const duplicateIds = matrixIds.filter(
  (id, index) => matrixIds.indexOf(id) !== index,
);
const missingFields = matrix.requirements.flatMap((item) =>
  requiredFields
    .filter((field) => !(field in item))
    .map((field) => `${item.id}.${field}`),
);
const planOnly = planIds.filter((id) => !matrixIds.includes(id));
const matrixOnly = matrixIds.filter((id) => !planIds.includes(id));
const structuralFailures = [
  ...new Set(duplicateIds.map((id) => `ID duplicado: ${id}`)),
  ...missingFields.map((field) => `Campo ausente: ${field}`),
  ...planOnly.map((id) => `ID ausente na matriz: ${id}`),
  ...matrixOnly.map((id) => `ID ausente no plano: ${id}`),
];

const components = matrix.inventory?.components ?? [];
const componentIds = components.map((component) => component.id);
const duplicateComponentIds = componentIds.filter(
  (id, index) => componentIds.indexOf(id) !== index,
);
const unknownRequirementReferences = components.flatMap((component) =>
  (component.requirement_ids ?? [])
    .filter((id) => !matrixIds.includes(id))
    .map((id) => `${component.id} -> ${id}`),
);
for (const id of new Set(duplicateComponentIds)) {
  structuralFailures.push(`ID de componente duplicado: ${id}`);
}
for (const reference of unknownRequirementReferences) {
  structuralFailures.push(`Referência de requisito desconhecida: ${reference}`);
}
const unclassified = components.filter(
  (component) =>
    !Array.isArray(component.requirement_ids) ||
    component.requirement_ids.length === 0,
);
const incompleteRequirements = matrix.requirements.filter((item) => {
  const mandatoryValues = [
    item.risk,
    item.test_type,
    item.procedure,
    item.expected_result,
    item.severity,
    item.owner,
    item.reviewer,
    item.commit,
    item.version,
  ];
  return (
    mandatoryValues.some((value) => value === null || value === '') ||
    item.environments_profiles.length === 0 ||
    item.component_refs.length === 0 ||
    item.evidence.length === 0 ||
    item.status !== 'approved'
  );
});
const strictFailures = [];
if (!matrix.inventory?.complete) {
  strictFailures.push('Inventário ainda não foi marcado como completo.');
}
if (components.length === 0) {
  strictFailures.push('Inventário não contém componentes.');
}
if (unclassified.length > 0) {
  strictFailures.push(`${unclassified.length} componentes sem classificação.`);
}
if (incompleteRequirements.length > 0) {
  strictFailures.push(
    `${incompleteRequirements.length} requisitos sem aprovação/evidência completa.`,
  );
}

const report = {
  mode: strict ? 'strict' : 'structure',
  plan_requirements: planIds.length,
  matrix_requirements: matrixIds.length,
  duplicate_count: new Set(duplicateIds).size,
  duplicate_component_count: new Set(duplicateComponentIds).size,
  unclassified_count: unclassified.length,
  incomplete_requirement_count: incompleteRequirements.length,
  structural_failures: structuralFailures,
  strict_failures: strict ? strictFailures : [],
  ok:
    structuralFailures.length === 0 &&
    (!strict || strictFailures.length === 0),
};

console.log(JSON.stringify(report, null, 2));
if (!report.ok) process.exit(1);
