# -*- coding: utf-8 -*-
"""
Example reusable mixin — adds audit timestamp fields.
Inherit in any domain model: _inherit = ['sale_custom.timestamp.mixin']
"""
from odoo import fields, models


class TimestampMixin(models.AbstractModel):
    _name = 'sale_custom.timestamp.mixin'
    _description = 'Audit Timestamp Mixin'

    processed_at = fields.Datetime(string='Processed At', readonly=True)
    processed_by = fields.Many2one('res.users', string='Processed By', readonly=True)

