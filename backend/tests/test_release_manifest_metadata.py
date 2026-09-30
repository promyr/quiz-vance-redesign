import json

from app.routers import releases


def test_published_artifact_overrides_stale_environment(monkeypatch, tmp_path):
    directory = tmp_path / 'releases' / 'android'
    directory.mkdir(parents=True)
    (directory / 'quiz-vance.apk').write_bytes(b'apk')
    (directory / 'quiz-vance-2.0.68+67.apk').write_bytes(b'apk')
    (directory / 'release-manifest.json').write_text(json.dumps({
        'app_version': '2.0.68+67', 'size_bytes': 3,
        'release_notes': 'Revisao de editais', 'published_at': '2026-09-30T20:00:00Z',
    }))
    monkeypatch.setattr(releases, '_BACKEND_ROOT', tmp_path)
    monkeypatch.setenv('ANDROID_APP_LATEST_VERSION', '2.0.67+66')
    assert releases._android_latest_version() == '2.0.68+67'
    assert releases._android_release_notes() == 'Revisao de editais'
    assert releases._android_published_at().year == 2026
    (directory / 'quiz-vance.apk').write_bytes(b'incomplete')
    assert releases._android_latest_version() == '2.0.67+66'


def test_corrupt_manifest_preserves_configuration(monkeypatch, tmp_path):
    directory = tmp_path / 'releases' / 'android'
    directory.mkdir(parents=True)
    (directory / 'release-manifest.json').write_text('broken')
    monkeypatch.setattr(releases, '_BACKEND_ROOT', tmp_path)
    monkeypatch.setenv('ANDROID_APP_LATEST_VERSION', '2.0.67+66')
    assert releases._android_latest_version() == '2.0.67+66'
