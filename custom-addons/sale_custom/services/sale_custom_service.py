# -*- coding: utf-8 -*-
"""
Service layer for sale_custom.

Convention (Ensure → Assert → Execute pattern):
  1. ensure_one() / validate cardinality
  2. _assert_* guard clauses  (pure, raise on violation)
  3. _apply_* or write()      (all mutations in one place)
  4. side effects              (email, webhook, etc.) — explicit and last
  5. return result             (don't mutate caller)

This is your FastAPI service / use-case class equivalent.
One public method = one use case.
"""
import logging
from odoo import api, fields, models
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)


class SaleCustomService(models.Model):
    """
    Service model — thin orchestration layer.
    _auto = False means no DB table is created.
    Think of it as a stateless service bean.
    """
    _name = 'sale_custom.service'
    _description = 'SaleCustom Service'
    _auto = False  # No table — pure logic carrier

    # -------------------------------------------------------------------------
    # Use Cases  (one public method per business operation)
    # -------------------------------------------------------------------------
    @api.model
    def activate_record(self, record_id: int):
        """
        Use case: activate a draft record.
        Entry point for controllers and wizards.
        """
        record = self._load_record(record_id)  # fetch
        record._assert_can_activate()          # guard (pure)
        self._apply_activate(record)           # mutate (explicit)
        self._notify_activation(record)        # side effect (explicit)
        return record

    @api.model
    def activate_batch(self, record_ids: list[int]):
        """
        Use case: activate multiple records.
        Uses savepoints so one failure doesn't roll back the whole batch.
        """
        results = {'success': [], 'failed': []}
        for record_id in record_ids:
            try:
                with self.env.cr.savepoint():   # ← your nested UoW
                    record = self.activate_record(record_id)
                    results['success'].append(record.id)
            except Exception as e:
                _logger.warning(
                    'activate_batch: record %s failed — %s', record_id, e
                )
                results['failed'].append({'id': record_id, 'error': str(e)})
        return results

    @api.model
    def cancel_record(self, record_id: int, reason: str = ''):
        """Use case: cancel a record."""
        record = self._load_record(record_id)
        record._assert_can_cancel()
        self._apply_cancel(record, reason)
        return record

    # -------------------------------------------------------------------------
    # Private — Fetch helpers (read-only, no side effects)
    # -------------------------------------------------------------------------
    def _load_record(self, record_id: int):
        record = self.env['sale_custom.record'].browse(record_id)
        if not record.exists():
            raise UserError(f'Record {record_id} not found.')
        return record

    # -------------------------------------------------------------------------
    # Private — Mutation helpers (_apply_* = all writes live here)
    # -------------------------------------------------------------------------
    def _apply_activate(self, record):
        record.write({
            'state': 'active',
            'processed_at': fields.Datetime.now(),
            'processed_by': self.env.uid,
        })

    def _apply_cancel(self, record, reason: str):
        record.write({'state': 'cancelled'})
        if reason:
            record.message_post(body=f'Cancelled: {reason}')

    # -------------------------------------------------------------------------
    # Private — Side effects (_notify_*, _send_*, _sync_*)
    # Kept last and named explicitly so they're impossible to miss in review.
    # -------------------------------------------------------------------------
    def _notify_activation(self, record):
        # Example: post to chatter, send email, call webhook
        record.message_post(
            body=f'Record activated by {self.env.user.name}',
            subtype_xmlid='mail.mt_note',
        )

