# -*- coding: utf-8 -*-
"""
Domain model for sale_custom.

Convention:
  - Fields + SQL constraints + @api.constrains  → schema / validation layer
  - @api.depends computed fields                → pure derived state (no write())
  - _assert_*  methods                          → guard clauses, raise only
  - _compute_* methods                          → pure reads, assign to self only
  No write() / create() / unlink() here.
  All mutations live in services/.
"""
import logging
from odoo import api, fields, models
from odoo.exceptions import ValidationError

_logger = logging.getLogger(__name__)


class SaleCustom(models.Model):
    _name = 'sale_custom.record'
    _description = 'SaleCustom Record'
    _order = 'id desc'

    # -------------------------------------------------------------------------
    # Fields  (your pydantic schema equivalent)
    # -------------------------------------------------------------------------
    name = fields.Char(
        string='Name',
        required=True,
        index=True,
    )
    state = fields.Selection(
        selection=[
            ('draft',    'Draft'),
            ('active',   'Active'),
            ('cancelled','Cancelled'),
        ],
        default='draft',
        required=True,
        tracking=True,       # logs changes in chatter
    )
    active = fields.Boolean(default=True)
    company_id = fields.Many2one(
        'res.company',
        default=lambda self: self.env.company,
    )
    # Computed example — pure derivation, store=True for DB persistence
    display_name_upper = fields.Char(
        compute='_compute_display_name_upper',
        store=True,
    )

    # -------------------------------------------------------------------------
    # SQL Constraints  (DB-level, cheapest enforcement)
    # -------------------------------------------------------------------------
    _sql_constraints = [
        (
            'unique_name_company',
            'UNIQUE(name, company_id)',
            'Name must be unique per company.',
        ),
    ]

    # -------------------------------------------------------------------------
    # Computed Fields  (pure — only reads deps, only assigns self.field)
    # -------------------------------------------------------------------------
    @api.depends('name')
    def _compute_display_name_upper(self):
        """Pure derivation. No side effects, no write() calls."""
        for rec in self:
            rec.display_name_upper = (rec.name or '').upper()

    # -------------------------------------------------------------------------
    # Constraints  (Python-level validation — raise or pass, never mutate)
    # -------------------------------------------------------------------------
    @api.constrains('state', 'name')
    def _check_active_requires_name(self):
        """Guard: active records must have a name."""
        for rec in self:
            if rec.state == 'active' and not rec.name:
                raise ValidationError('An active record must have a name.')

    # -------------------------------------------------------------------------
    # Guard Clauses  (_assert_* = pure precondition checks, no mutations)
    # Called by service methods before any write.
    # -------------------------------------------------------------------------
    def _assert_can_activate(self):
        self.ensure_one()
        if self.state != 'draft':
            raise ValidationError(
                f'Record must be in Draft to activate. Current: {self.state}'
            )

    def _assert_can_cancel(self):
        self.ensure_one()
        if self.state == 'cancelled':
            raise ValidationError('Record is already cancelled.')

    # -------------------------------------------------------------------------
    # ORM Hook Overrides  (keep minimal — prefer service layer entry points)
    # Use hooks only for enforcing invariants that MUST hold at DB level.
    # -------------------------------------------------------------------------
    @api.model_create_multi
    def create(self, vals_list):
        # Normalize before insert — keep pure (no DB writes here)
        for vals in vals_list:
            if 'name' in vals:
                vals['name'] = vals['name'].strip()
        return super().create(vals_list)

