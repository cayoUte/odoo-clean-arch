# -*- coding: utf-8 -*-
"""
Service-layer tests.
Test the service methods directly — not the controller, not the ORM.
Keep tests focused on one use case per method.
"""
from odoo.tests.common import TransactionCase
from odoo.exceptions import ValidationError


class TestSaleCustomService(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.service = cls.env['sale_custom.service']
        cls.record = cls.env['sale_custom.record'].create({'name': 'Test'})

    # -------------------------------------------------------------------------
    # Activate use case
    # -------------------------------------------------------------------------
    def test_activate_draft_record_succeeds(self):
        self.service.activate_record(self.record.id)
        self.assertEqual(self.record.state, 'active')

    def test_activate_already_active_raises(self):
        self.record.write({'state': 'active'})
        with self.assertRaises(ValidationError):
            self.service.activate_record(self.record.id)

    def test_activate_batch_partial_failure_isolates(self):
        good = self.env['sale_custom.record'].create({'name': 'Good'})
        bad  = self.env['sale_custom.record'].create({'name': 'Bad'})
        bad.write({'state': 'active'})   # already active → will fail

        results = self.service.activate_batch([good.id, bad.id])

        self.assertIn(good.id, results['success'])
        self.assertTrue(any(f['id'] == bad.id for f in results['failed']))
        self.assertEqual(good.state, 'active')   # good record still succeeded

    # -------------------------------------------------------------------------
    # Cancel use case
    # -------------------------------------------------------------------------
    def test_cancel_active_record_succeeds(self):
        self.record.write({'state': 'active'})
        self.service.cancel_record(self.record.id, reason='Test cancellation')
        self.assertEqual(self.record.state, 'cancelled')

    def test_cancel_already_cancelled_raises(self):
        self.record.write({'state': 'cancelled'})
        with self.assertRaises(ValidationError):
            self.service.cancel_record(self.record.id)

