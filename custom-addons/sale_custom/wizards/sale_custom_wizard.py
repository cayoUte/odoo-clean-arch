# -*- coding: utf-8 -*-
"""
Wizard — transient model for multi-step user flows.
Think of it as a scoped form state + submit handler.
Delegates execution to the service layer.
"""
from odoo import api, fields, models


class SaleCustomWizard(models.TransientModel):
    _name = 'sale_custom.wizard'
    _description = 'SaleCustom Wizard'

    record_id = fields.Many2one('sale_custom.record', required=True)
    reason = fields.Text()

    def action_confirm(self):
        """Submit handler — delegates to service, returns window action."""
        service = self.env['sale_custom.service']
        service.cancel_record(self.record_id.id, self.reason or '')
        return {'type': 'ir.actions.act_window_close'}

