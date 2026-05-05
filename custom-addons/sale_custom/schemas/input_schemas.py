# -*- coding: utf-8 -*-
"""
Input validation schemas.

Odoo doesn't have pydantic, but you can replicate the pattern with dataclasses
+ explicit validators. Call these at the controller boundary before touching
the ORM — same discipline as pydantic models in FastAPI routes.

Usage in controller:
    payload = ActivateRecordInput.from_json(request.jsonrequest)
    service.activate_record(payload.record_id)
"""
from dataclasses import dataclass
from odoo.exceptions import ValidationError


@dataclass(frozen=True)   # frozen=True → immutable, like a pydantic model
class ActivateRecordInput:
    record_id: int

    def __post_init__(self):
        if not isinstance(self.record_id, int) or self.record_id <= 0:
            raise ValidationError('record_id must be a positive integer.')

    @classmethod
    def from_json(cls, data: dict) -> 'ActivateRecordInput':
        """Parse and validate raw JSON payload."""
        try:
            return cls(record_id=int(data['record_id']))
        except (KeyError, TypeError, ValueError) as e:
            raise ValidationError(f'Invalid payload: {e}') from e


@dataclass(frozen=True)
class CancelRecordInput:
    record_id: int
    reason: str = ''

    def __post_init__(self):
        if not isinstance(self.record_id, int) or self.record_id <= 0:
            raise ValidationError('record_id must be a positive integer.')
        if len(self.reason) > 500:
            raise ValidationError('Reason must be under 500 characters.')

    @classmethod
    def from_json(cls, data: dict) -> 'CancelRecordInput':
        try:
            return cls(
                record_id=int(data['record_id']),
                reason=str(data.get('reason', '')).strip(),
            )
        except (KeyError, TypeError, ValueError) as e:
            raise ValidationError(f'Invalid payload: {e}') from e

