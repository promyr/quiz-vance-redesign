import importlib.util
import json
from pathlib import Path


def load_publisher():
    path = Path(__file__).parents[1] / 'scripts/publish_telegram_release_link.py'
    spec = importlib.util.spec_from_file_location('publisher_for_test', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_current_apk_version_overrides_stale_release_environment(monkeypatch, tmp_path):
    publisher = load_publisher()
    monkeypatch.setattr(publisher, 'APK_PATH', tmp_path / 'quiz-vance.apk')
    monkeypatch.setenv('RELEASE_VERSION', '2.0.67+66')
    (tmp_path / 'release-manifest.json').write_text(json.dumps({'app_version': '2.0.70+69'}))
    assert publisher._release_version() == '2.0.70+69'


def test_publisher_accepts_current_render_download(monkeypatch, tmp_path):
    publisher = load_publisher()
    apk = tmp_path / 'quiz-vance.apk'
    apk.write_bytes(b'apk')
    apk.with_name('quiz-vance-2.0.70+69.apk').write_bytes(b'apk')
    monkeypatch.setattr(publisher, 'APK_PATH', apk)
    monkeypatch.setattr(publisher.telegram_bot, 'download_url', lambda: 'https://quiz-vance-redesign-1.onrender.com/app/download/android/latest.apk')
    url, size, digest = publisher._release_metadata('2.0.70+69')
    assert 'onrender.com' in url
    assert size == 3
    assert len(digest) == 64


def test_caption_uses_current_release_notes(monkeypatch, tmp_path):
    publisher = load_publisher()
    monkeypatch.setattr(publisher, 'APK_PATH', tmp_path / 'quiz-vance.apk')
    (tmp_path / 'release-manifest.json').write_text(json.dumps({'release_notes': 'Estatisticas e Biblioteca corrigidas.'}))
    caption = publisher._release_caption(version='2.0.70+69', size=3, digest='A' * 64)
    assert 'Estatisticas e Biblioteca corrigidas.' in caption


def test_startup_publication_is_idempotent(tmp_path):
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from app import models, release_publication
    engine = create_engine('sqlite://')
    models.Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    calls = []
    manifest = {'app_version': '2.0.70+69', 'published_at': '2026-09-30T21:35:42Z', 'telegram_publish_requested': True}
    def publish():
        calls.append(True)
        return {'message_id': 42}
    release_publication.publish_requested_release(manifest=manifest, session_factory=sessions, publish=publish)
    release_publication.publish_requested_release(manifest=manifest, session_factory=sessions, publish=publish)
    assert calls == [True]
    assert release_publication.publication_status(manifest=manifest, session_factory=sessions) == {'version': '2.0.70+69', 'status': 'sent', 'message_id': 42}
    engine.dispose()


def test_unrequested_release_is_not_sent():
    from app import release_publication
    release_publication.publish_requested_release(manifest={'app_version': 'future'}, publish=lambda: (_ for _ in ()).throw(AssertionError('must not send')))


def test_failed_send_is_not_repeated_automatically():
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from app import models, release_publication
    engine = create_engine('sqlite://')
    models.Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    calls = []
    manifest = {'app_version': '2.0.70+69', 'published_at': '2026-09-30T21:35:42Z', 'telegram_publish_requested': True}
    def publish():
        calls.append(True)
        raise RuntimeError('unknown delivery outcome')
    release_publication.publish_requested_release(manifest=manifest, session_factory=sessions, publish=publish)
    release_publication.publish_requested_release(manifest=manifest, session_factory=sessions, publish=publish)
    assert calls == [True]
    assert release_publication.publication_status(manifest=manifest, session_factory=sessions)['status'] == 'failed'
    engine.dispose()


def test_verified_external_delivery_receipt_is_reported_without_resending():
    from app import release_publication
    manifest = {'app_version': '2.0.70+69', 'apk_sha256': 'A' * 64,
        'telegram_publication_receipt': {'version': '2.0.70+69', 'status': 'sent', 'message_id': 868, 'sha256': 'A' * 64}}
    assert release_publication.publication_status(manifest=manifest) == {'version': '2.0.70+69', 'status': 'sent', 'message_id': 868}
    release_publication.publish_requested_release(manifest=manifest, publish=lambda: (_ for _ in ()).throw(AssertionError('must not resend')))
