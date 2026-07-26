import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const matrixPath = path.join(root, 'audit', 'AUDIT_CONTROL_MATRIX.json');
const matrix = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));
const previousById = new Map(
  (matrix.inventory?.components ?? []).map((component) => [
    component.id,
    component,
  ]),
);
const scanRoots = ['lib', 'backend/app', 'backend/alembic/versions', '.github/workflows', 'android', 'scripts'];
const ignoredDirectories = new Set([
  '.dart_tool',
  '.gradle',
  '__pycache__',
  'build',
  'node_modules',
]);
const textExtensions = new Set([
  '.dart',
  '.gradle',
  '.json',
  '.kts',
  '.lock',
  '.md',
  '.properties',
  '.py',
  '.toml',
  '.yaml',
  '.yml',
]);
const components = [];

function normalize(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function addComponent(component) {
  const previous = previousById.get(component.id);
  components.push({
    ...component,
    requirement_ids: previous?.requirement_ids ?? [],
  });
}

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return ignoredDirectories.has(entry.name) ? [] : walk(absolute);
    }
    return [absolute];
  });
}

for (const feature of fs.existsSync(path.join(root, 'lib', 'features'))
  ? fs.readdirSync(path.join(root, 'lib', 'features'), { withFileTypes: true })
  : []) {
  if (feature.isDirectory()) {
    addComponent({
      id: `FEATURE::${feature.name}`,
      kind: 'flutter_feature',
      path: `lib/features/${feature.name}`,
    });
  }
}

for (const scanRoot of scanRoots) {
  for (const absolutePath of walk(path.join(root, scanRoot))) {
    const extension = path.extname(absolutePath).toLowerCase();
    if (!textExtensions.has(extension)) continue;

    const relativePath = normalize(path.relative(root, absolutePath));
    addComponent({
      id: `FILE::${relativePath}`,
      kind: 'source_file',
      path: relativePath,
    });
    const source = fs.readFileSync(absolutePath, 'utf8');

    if (extension === '.py') {
      for (const match of source.matchAll(
        /@(?:router|app)\.(get|post|put|patch|delete)\(\s*["']([^"']+)["']/g,
      )) {
        addComponent({
          id: `API::${match[1].toUpperCase()}::${relativePath}::${match[2]}`,
          kind: 'fastapi_route',
          path: relativePath,
          method: match[1].toUpperCase(),
          route: match[2],
        });
      }
      for (const match of source.matchAll(/__tablename__\s*=\s*["']([^"']+)["']/g)) {
        addComponent({
          id: `DBMODEL::${match[1]}::${relativePath}`,
          kind: 'sqlalchemy_model',
          path: relativePath,
          table: match[1],
        });
      }
    }

    if (extension === '.dart') {
      const routeOccurrences = new Map();
      for (const match of source.matchAll(
        /GoRoute\s*\([\s\S]*?path\s*:\s*["']([^"']+)["']/g,
      )) {
        const occurrence = (routeOccurrences.get(match[1]) ?? 0) + 1;
        routeOccurrences.set(match[1], occurrence);
        addComponent({
          id: `ROUTE::${relativePath}::${match[1]}::${occurrence}`,
          kind: 'flutter_route',
          path: relativePath,
          route: match[1],
        });
      }
    }

    if (
      relativePath.startsWith('backend/alembic/versions/') &&
      extension === '.py'
    ) {
      addComponent({
        id: `MIGRATION::${relativePath}`,
        kind: 'alembic_migration',
        path: relativePath,
      });
    }
  }
}

components.sort((left, right) => left.id.localeCompare(right.id));
matrix.inventory = {
  ...matrix.inventory,
  complete: false,
  generated_from: scanRoots,
  components,
};
fs.writeFileSync(matrixPath, `${JSON.stringify(matrix, null, 2)}\n`, 'utf8');
console.log(`Inventário gerado: ${components.length} componentes.`);
