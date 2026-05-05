# -*- coding: utf-8 -*-
"""
Read-only repository methods for sale_custom.record.

Convention:
  - All methods return recordsets or scalar values — never mutate.
  - Think of each method as a named query / repository finder.
  - Import this mixin into the domain model via _inherit if query volume grows.

Usage in domain model:
    class SaleCustom(models.Model):
        _name = 'sale_custom.record'
        _inherit = ['sale_custom.record.query.mixin']
"""
from odoo import api, models


class SaleCustomQueryMixin(models.AbstractModel):
    _name = 'sale_custom.record.query.mixin'
    _description = 'SaleCustom Query Mixin'

    @api.model
    def query_active_by_company(self, company_id: int):
        """Pure read: returns active records for a given company."""
        return self.env['sale_custom.record'].search([
            ('state', '=', 'active'),
            ('company_id', '=', company_id),
        ])

    def filter_by_state(self, state: str):
        """Pure filter on an existing recordset — no DB call."""
        return self.filtered(lambda r: r.state == state)

