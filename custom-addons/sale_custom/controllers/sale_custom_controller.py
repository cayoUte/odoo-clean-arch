# -*- coding: utf-8 -*-
"""
HTTP Controller — thin adapter (your FastAPI router equivalent).

Rules:
  - Parse + validate input via schemas/
  - Delegate everything to services/
  - Format and return response
  - Zero business logic here
"""
import logging
from odoo import http
from odoo.http import request
from odoo.exceptions import ValidationError, UserError
from ..schemas import ActivateRecordInput, CancelRecordInput

_logger = logging.getLogger(__name__)


class SaleCustomController(http.Controller):

    # -------------------------------------------------------------------------
    # Routes
    # -------------------------------------------------------------------------
    @http.route(
        '/api/sale_custom/activate',
        type='json',
        auth='user',
        methods=['POST'],
        csrf=False,
    )
    def activate_record(self):
        """POST /api/sale_custom/activate  { record_id: int }"""
        return self._handle(self._activate)

    @http.route(
        '/api/sale_custom/cancel',
        type='json',
        auth='user',
        methods=['POST'],
        csrf=False,
    )
    def cancel_record(self):
        """POST /api/sale_custom/cancel  { record_id: int, reason?: str }"""
        return self._handle(self._cancel)

    # -------------------------------------------------------------------------
    # Private route handlers  (one per route, keeps routing table clean)
    # -------------------------------------------------------------------------
    def _activate(self, payload: dict):
        inp = ActivateRecordInput.from_json(payload)   # validate input
        service = request.env['sale_custom.service']
        record = service.activate_record(inp.record_id)
        return self._serialize_record(record)           # format output

    def _cancel(self, payload: dict):
        inp = CancelRecordInput.from_json(payload)
        service = request.env['sale_custom.service']
        record = service.cancel_record(inp.record_id, inp.reason)
        return self._serialize_record(record)

    # -------------------------------------------------------------------------
    # Serializer  (your response schema / DTO)
    # -------------------------------------------------------------------------
    @staticmethod
    def _serialize_record(record) -> dict:
        """Pure function: recordset → plain dict. No side effects."""
        record.ensure_one()
        return {
            'id':    record.id,
            'name':  record.name,
            'state': record.state,
        }

    # -------------------------------------------------------------------------
    # Error wrapper  (centralized exception → HTTP response mapping)
    # -------------------------------------------------------------------------
    @staticmethod
    def _handle(fn):
        """Wrap handler: catches domain errors → structured JSON error."""
        try:
            payload = request.jsonrequest or {}
            return {'ok': True, 'data': fn(payload)}
        except (ValidationError, UserError) as e:
            return {'ok': False, 'error': str(e.args[0])}
        except Exception as e:
            _logger.exception('Unhandled error in sale_custom controller')
            return {'ok': False, 'error': 'Internal server error'}

