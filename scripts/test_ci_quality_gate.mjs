import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const workflowPath = new URL('../.github/workflows/build.yml', import.meta.url);
const workflow = readFileSync(workflowPath, 'utf8');

function validateQualityGate(source) {
  const jobs = new Map(
    [...source.matchAll(/^  ([a-z][a-z0-9-]*):\r?\n([\s\S]*?)(?=^  [a-z][a-z0-9-]*:\r?$|$(?![\s\S]))/gm)]
      .map((match) => [match[1], match[2]]),
  );
  const flutter = jobs.get('flutter');
  const android = jobs.get('android');
  assert.ok(flutter, 'Flutter verification must have its own job.');
  assert.ok(android, 'Signed Android release job must remain available.');
  assert.match(flutter, /run: flutter pub get --enforce-lockfile/);
  assert.match(flutter, /run: flutter analyze --no-pub/);
  assert.match(flutter, /run: flutter test --no-pub/);
  assert.doesNotMatch(flutter, /secrets\.|ANDROID_KEY|ANDROID_STORE|key\.properties/,
    'Flutter checks must run without production signing secrets.');
  assert.doesNotMatch(flutter, /^    if:|continue-on-error:|always\(\)/m,
    'Flutter verification must not be conditional or allow failures.');

  const needsMatch = android.match(/^    needs: \[([^\]]+)\]/m);
  assert.ok(needsMatch, 'Release must declare its verification dependencies.');
  const needs = needsMatch[1].split(',').map((value) => value.trim());
  for (const required of ['secret-hygiene', 'backend', 'backend-image', 'flutter']) {
    assert.ok(needs.includes(required), `Release must require ${required}.`);
  }
  assert.match(android,
    /^    if: github\.event_name == 'workflow_dispatch' \|\| startsWith\(github\.ref, 'refs\/tags\/v'\)$/m,
    'Signing must be restricted to manual releases or version tags.');
  assert.doesNotMatch(android, /always\(\)|continue-on-error:/,
    'A failed dependency must prevent release.');
  assert.match(android, /test -n "\$ANDROID_KEYSTORE_BASE64"/);
  assert.match(android, /apksigner.*verify/);
  assert.match(jobs.get('backend-image') ?? '', /fail-build: true/,
    'Image vulnerabilities must keep blocking releases.');
}

validateQualityGate(workflow);

// Prove the contract catches a bypass instead of merely accepting this file.
const mutations = [
  workflow.replace('run: flutter test --no-pub', 'run: echo skipped tests'),
  workflow.replace('backend-image, flutter]', 'backend-image]'),
  workflow.replace('    if: github.event_name', '    if: always() || github.event_name'),
  workflow.replace('run: flutter analyze --no-pub', 'run: echo ${{ secrets.ANDROID_KEY_ALIAS }}'),
];
for (const mutation of mutations) {
  assert.notEqual(mutation, workflow, 'Mutation must exercise an existing gate.');
  assert.throws(() => validateQualityGate(mutation));
}
console.log('PASS: independent Flutter checks, release dependencies, and four bypass regressions.');
