import json

from app.routers import releases


def test_published_artifact_overrides_stale_environment(monkeypatch, tmp_path):
    directory = tmp_path / 'releases' / 'android'
    directory.mkdir(parents=True)
    (directory / 'quiz-vance.apk').write_bytes(b'apk')
    (directory / 'quiz-vance-2.0.68+67.apk').write_bytes(b'apk')
    (directory / 'release-manifest.json').write_text(
        json.dumps(
            {
                'app_version': '2.0.68+67',
                'size_bytes': 3,
                'release_notes': 'Revisão diária de editais e ativação biométrica',
                'published_at': '2026-09-30T20:00:00Z',
            },
            ensure_ascii=False,
        ),
        encoding='utf-8',
    )
    monkeypatch.setattr(releases, '_BACKEND_ROOT', tmp_path)
    monkeypatch.setenv('ANDROID_APP_LATEST_VERSION', '2.0.67+66')
    assert releases._android_latest_version() == '2.0.68+67'
    assert (
        releases._android_release_notes()
        == 'Revisão diária de editais e ativação biométrica'
    )
    assert releases._android_published_at().year == 2026
    (directory / 'quiz-vance.apk').write_bytes(b'incomplete')
    assert releases._android_latest_version() == '2.0.67+66'


def test_corrupt_manifest_preserves_configuration(monkeypatch, tmp_path):
    directory = tmp_path / 'releases' / 'android'
    directory.mkdir(parents=True)
    (directory / 'release-manifest.json').write_text('broken', encoding='utf-8')
    monkeypatch.setattr(releases, '_BACKEND_ROOT', tmp_path)
    monkeypatch.setenv('ANDROID_APP_LATEST_VERSION', '2.0.67+66')
    assert releases._android_latest_version() == '2.0.67+66'


def test_bundled_release_manifest_is_valid_utf8_without_mojibake():
    manifest_path = releases._BACKEND_ROOT / 'releases' / 'android' / 'release-manifest.json'
    raw = manifest_path.read_text(encoding='utf-8')
    assert '\ufffd' not in raw
    data = json.loads(raw)
    assert isinstance(data.get('release_notes'), str)
    assert data['release_notes'].strip() != ''

