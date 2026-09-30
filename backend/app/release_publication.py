"""One-shot publication of a release explicitly requested in its manifest."""
import json
import logging
import re
import threading
from datetime import datetime, timezone

from sqlalchemy.exc import IntegrityError

from . import models, telegram_bot
from .database import SessionLocal
from .routers.releases import _android_release_manifest

logger = logging.getLogger(__name__)


def _release_key(manifest):
    version = str(manifest.get('app_version') or '')
    if not re.fullmatch(r'[0-9A-Za-z._+-]{1,32}', version):
        raise ValueError('invalid publication version')
    day = datetime.fromisoformat(manifest['published_at'].replace('Z', '+00:00')).date()
    return day, 'apk:' + version


def publish_requested_release(*, manifest=None, session_factory=None, publish=None):
    manifest = _android_release_manifest() if manifest is None else manifest
    if manifest.get('telegram_publish_requested') is not True:
        return
    if publish is None and not telegram_bot.telegram_enabled():
        logger.warning('telegram_release_not_configured')
        return
    sessions = session_factory or SessionLocal
    try:
        day, slot = _release_key(manifest)
        with sessions() as db:
            if db.query(models.TelegramDailyPostLog).filter_by(day_key=day, slot_key=slot).first():
                return
            # Claim before contacting Telegram. Unknown outcomes must not auto-retry.
            row = models.TelegramDailyPostLog(day_key=day, slot_key=slot,
                topic_key='atualizacoes', chat_id='release-publication',
                status='sending', attempt_count=1, last_attempt_at=datetime.now(timezone.utc))
            db.add(row)
            try:
                db.commit()
                row_id = row.id
            except IntegrityError:
                db.rollback()
                return
        try:
            if publish is None:
                from scripts.publish_telegram_release_link import publish_release
                publish = publish_release
            receipt = publish()
            if int(receipt.get('message_id') or 0) <= 0:
                raise ValueError('missing Telegram message receipt')
            status, error = 'sent', None
        except Exception as exc:  # noqa: BLE001 - record sanitized outcome at the worker boundary
            receipt = {}
            status, error = 'failed', telegram_bot.sanitize_error(exc)
        with sessions() as db:
            row = db.get(models.TelegramDailyPostLog, row_id)
            row.status = status
            row.last_error = error
            row.post_text = json.dumps({'message_id': receipt.get('message_id')})
            if receipt.get('chat_id'):
                row.chat_id = str(receipt['chat_id'])
                row.message_thread_id = receipt.get('message_thread_id')
            row.updated_at = datetime.now(timezone.utc)
            if status == 'sent':
                row.sent_at = row.updated_at
            db.commit()
        logger.info('telegram_release_publication_%s', status)
    except Exception as exc:  # noqa: BLE001 - record sanitized outcome at the worker boundary
        logger.warning('telegram_release_publication_error: %s', telegram_bot.sanitize_error(exc))


def publication_status(*, manifest=None, session_factory=None):
    manifest = _android_release_manifest() if manifest is None else manifest
    version = manifest.get('app_version')
    result = {'version': version, 'status': 'not_requested', 'message_id': None}
    if manifest.get('telegram_publish_requested') is not True:
        return result
    day, slot = _release_key(manifest)
    with (session_factory or SessionLocal)() as db:
        row = db.query(models.TelegramDailyPostLog).filter_by(day_key=day, slot_key=slot).first()
        if row:
            result['status'] = row.status
            result['message_id'] = json.loads(row.post_text or '{}').get('message_id')
            if row.status == 'failed':
                error = row.last_error or ''
                result['failure_reason'] = (
                    'community_not_configured' if 'community configuration' in error or 'Updates topic' in error
                    else 'download_url_mismatch' if 'non-canonical download URL' in error
                    else 'publication_failed'
                )
        else:
            result['status'] = 'pending' if telegram_bot.telegram_enabled() else 'not_configured'
    return result


def start_release_publication():
    threading.Thread(target=publish_requested_release, name='telegram-release', daemon=True).start()
