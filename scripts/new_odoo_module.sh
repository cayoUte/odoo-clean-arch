#!/usr/bin/env bash
# =============================================================================
# Odoo 19 — Clean Architecture Module Scaffold
# Usage: bash new_odoo_module.sh <module_name> [addons_path]
# Example: bash new_odoo_module.sh sale_custom ./custom_addons
# =============================================================================

set -euo pipefail

# --- Args --------------------------------------------------------------------
MODULE_NAME="${1:?Usage: $0 <module_name> [addons_path]}"
ADDONS_PATH="${2:-.}"
ROOT="$ADDONS_PATH/$MODULE_NAME"

# Validate module name (Odoo convention: lowercase + underscores only)
if [[ ! "$MODULE_NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "❌  Module name must be lowercase with underscores (e.g. sale_custom)"
  exit 1
fi

if [ -d "$ROOT" ]; then
  echo "❌  Directory '$ROOT' already exists."
  exit 1
fi

# Derive a PascalCase class prefix from module name
# e.g. sale_custom → SaleCustom
CLASS_PREFIX=$(echo "$MODULE_NAME" | sed 's/_\([a-z]\)/\U\1/g;s/^\([a-z]\)/\U\1/')

echo ""
echo "🏗  Scaffolding Odoo module: $MODULE_NAME"
echo "   Class prefix : $CLASS_PREFIX"
echo "   Target path  : $ROOT"
echo ""

# =============================================================================
# 1. DIRECTORY TREE
# =============================================================================
# Layer map (mirrors hexagonal arch):
#
#   controllers/   ← Ports (thin HTTP adapters, no business logic)
#   services/      ← Application layer (orchestration, UoW, entry points)
#   models/
#     ├── domain/  ← Core models: fields, constraints, computed (pure)
#     ├── query/   ← Read-only repository methods (search, filtered, mapped)
#     └── mixins/  ← Reusable field/method groups (like abstract base classes)
#   schemas/       ← Input validation helpers (like pydantic schemas)
#   wizards/       ← Transient models (multi-step UX flows)
#   security/      ← Access rules, record rules, groups
#   data/          ← Config/seed data loaded on install
#   demo/          ← Demo data (dev only)
#   views/         ← XML UI definitions
#   static/        ← OWL components (your React world)
#     ├── src/
#     │   ├── components/   ← Presentational OWL components
#     │   ├── stores/       ← Reactive state (replaces React context/reducers)
#     │   └── services/     ← Frontend service layer (API calls)
#     └── tests/
#   tests/         ← Backend Python tests
#   i18n/          ← Translation files

dirs=(
  # Python layers
  "controllers"
  "services"
  "models/domain"
  "models/query"
  "models/mixins"
  "schemas"
  "wizards"

  # Odoo config
  "security"
  "data"
  "demo"
  "views"

  # OWL / JS frontend
  "static/src/components"
  "static/src/stores"
  "static/src/services"
  "static/tests"

  # Tests
  "tests"

  # Translations
  "i18n"
)

for d in "${dirs[@]}"; do
  mkdir -p "$ROOT/$d"
done


# =============================================================================
# 2. HELPER — write file with a header comment
# =============================================================================
write_file() {
  local path="$1"
  local content="$2"
  printf '%s\n' "$content" > "$ROOT/$path"
}


# =============================================================================
# 3. MODULE MANIFEST  __manifest__.py
# =============================================================================
write_file "__manifest__.py" "# -*- coding: utf-8 -*-
{
    'name': '${MODULE_NAME}',
    'version': '19.0.1.0.0',
    'summary': 'Short description',
    'category': 'Uncategorized',
    'author': '',
    'license': 'LGPL-3',
    'depends': ['base'],
    'data': [
        # Load order matters: security first, then data, then views
        'security/ir.model.access.csv',
        # 'data/config_data.xml',
        # 'views/${MODULE_NAME}_views.xml',
        # 'views/menu.xml',
    ],
    'demo': [
        # 'demo/demo_data.xml',
    ],
    'assets': {
        'web.assets_backend': [
            # '${MODULE_NAME}/static/src/components/**/*.xml',
            # '${MODULE_NAME}/static/src/components/**/*.js',
            # '${MODULE_NAME}/static/src/stores/**/*.js',
        ],
    },
    'installable': True,
    'auto_install': False,
    'application': False,
}
"


# =============================================================================
# 4. ROOT __init__.py  — explicit imports enforce layer awareness
# =============================================================================
write_file "__init__.py" "# -*- coding: utf-8 -*-
# Import order = dependency order. Controllers last (depend on everything).
from . import models
from . import services
from . import wizards
from . import controllers
"


# =============================================================================
# 5. MODELS layer
# =============================================================================
write_file "models/__init__.py" "# -*- coding: utf-8 -*-
# Re-export domain models. Query and mixin modules are imported by domain models
# directly — they are not standalone.
from .domain import *  # noqa: F401, F403
"

write_file "models/domain/__init__.py" "# -*- coding: utf-8 -*-
# One import per domain model file.
# from . import ${MODULE_NAME}_model
"

# --- Domain model template ---------------------------------------------------
write_file "models/domain/${MODULE_NAME}_model.py" "# -*- coding: utf-8 -*-
\"\"\"
Domain model for ${MODULE_NAME}.

Convention:
  - Fields + SQL constraints + @api.constrains  → schema / validation layer
  - @api.depends computed fields                → pure derived state (no write())
  - _assert_*  methods                          → guard clauses, raise only
  - _compute_* methods                          → pure reads, assign to self only
  No write() / create() / unlink() here.
  All mutations live in services/.
\"\"\"
import logging
from odoo import api, fields, models
from odoo.exceptions import ValidationError

_logger = logging.getLogger(__name__)


class ${CLASS_PREFIX}(models.Model):
    _name = '${MODULE_NAME}.record'
    _description = '${CLASS_PREFIX} Record'
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
        \"\"\"Pure derivation. No side effects, no write() calls.\"\"\"
        for rec in self:
            rec.display_name_upper = (rec.name or '').upper()

    # -------------------------------------------------------------------------
    # Constraints  (Python-level validation — raise or pass, never mutate)
    # -------------------------------------------------------------------------
    @api.constrains('state', 'name')
    def _check_active_requires_name(self):
        \"\"\"Guard: active records must have a name.\"\"\"
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
"


# --- Query module template ---------------------------------------------------
write_file "models/query/__init__.py" "# -*- coding: utf-8 -*-
# Query modules are imported directly by the domain model that owns them.
# They must never call write() / create() / unlink().
"

write_file "models/query/${MODULE_NAME}_query.py" "# -*- coding: utf-8 -*-
\"\"\"
Read-only repository methods for ${MODULE_NAME}.record.

Convention:
  - All methods return recordsets or scalar values — never mutate.
  - Think of each method as a named query / repository finder.
  - Import this mixin into the domain model via _inherit if query volume grows.

Usage in domain model:
    class ${CLASS_PREFIX}(models.Model):
        _name = '${MODULE_NAME}.record'
        _inherit = ['${MODULE_NAME}.record.query.mixin']
\"\"\"
from odoo import api, models


class ${CLASS_PREFIX}QueryMixin(models.AbstractModel):
    _name = '${MODULE_NAME}.record.query.mixin'
    _description = '${CLASS_PREFIX} Query Mixin'

    @api.model
    def query_active_by_company(self, company_id: int):
        \"\"\"Pure read: returns active records for a given company.\"\"\"
        return self.env['${MODULE_NAME}.record'].search([
            ('state', '=', 'active'),
            ('company_id', '=', company_id),
        ])

    def filter_by_state(self, state: str):
        \"\"\"Pure filter on an existing recordset — no DB call.\"\"\"
        return self.filtered(lambda r: r.state == state)
"


# --- Mixin template ----------------------------------------------------------
write_file "models/mixins/__init__.py" "# -*- coding: utf-8 -*-
"

write_file "models/mixins/timestamp_mixin.py" "# -*- coding: utf-8 -*-
\"\"\"
Example reusable mixin — adds audit timestamp fields.
Inherit in any domain model: _inherit = ['${MODULE_NAME}.timestamp.mixin']
\"\"\"
from odoo import fields, models


class TimestampMixin(models.AbstractModel):
    _name = '${MODULE_NAME}.timestamp.mixin'
    _description = 'Audit Timestamp Mixin'

    processed_at = fields.Datetime(string='Processed At', readonly=True)
    processed_by = fields.Many2one('res.users', string='Processed By', readonly=True)
"


# =============================================================================
# 6. SERVICES layer  (application / orchestration layer)
# =============================================================================
write_file "services/__init__.py" "# -*- coding: utf-8 -*-
from . import ${MODULE_NAME}_service  # noqa: F401
"

write_file "services/${MODULE_NAME}_service.py" "# -*- coding: utf-8 -*-
\"\"\"
Service layer for ${MODULE_NAME}.

Convention (Ensure → Assert → Execute pattern):
  1. ensure_one() / validate cardinality
  2. _assert_* guard clauses  (pure, raise on violation)
  3. _apply_* or write()      (all mutations in one place)
  4. side effects              (email, webhook, etc.) — explicit and last
  5. return result             (don't mutate caller)

This is your FastAPI service / use-case class equivalent.
One public method = one use case.
\"\"\"
import logging
from odoo import api, fields, models
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)


class ${CLASS_PREFIX}Service(models.Model):
    \"\"\"
    Service model — thin orchestration layer.
    _auto = False means no DB table is created.
    Think of it as a stateless service bean.
    \"\"\"
    _name = '${MODULE_NAME}.service'
    _description = '${CLASS_PREFIX} Service'
    _auto = False  # No table — pure logic carrier

    # -------------------------------------------------------------------------
    # Use Cases  (one public method per business operation)
    # -------------------------------------------------------------------------
    @api.model
    def activate_record(self, record_id: int):
        \"\"\"
        Use case: activate a draft record.
        Entry point for controllers and wizards.
        \"\"\"
        record = self._load_record(record_id)  # fetch
        record._assert_can_activate()          # guard (pure)
        self._apply_activate(record)           # mutate (explicit)
        self._notify_activation(record)        # side effect (explicit)
        return record

    @api.model
    def activate_batch(self, record_ids: list[int]):
        \"\"\"
        Use case: activate multiple records.
        Uses savepoints so one failure doesn't roll back the whole batch.
        \"\"\"
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
        \"\"\"Use case: cancel a record.\"\"\"
        record = self._load_record(record_id)
        record._assert_can_cancel()
        self._apply_cancel(record, reason)
        return record

    # -------------------------------------------------------------------------
    # Private — Fetch helpers (read-only, no side effects)
    # -------------------------------------------------------------------------
    def _load_record(self, record_id: int):
        record = self.env['${MODULE_NAME}.record'].browse(record_id)
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
"


# =============================================================================
# 7. SCHEMAS  (input validation — your pydantic layer)
# =============================================================================
write_file "schemas/__init__.py" "# -*- coding: utf-8 -*-
from .input_schemas import *  # noqa: F401, F403
"

write_file "schemas/input_schemas.py" "# -*- coding: utf-8 -*-
\"\"\"
Input validation schemas.

Odoo doesn't have pydantic, but you can replicate the pattern with dataclasses
+ explicit validators. Call these at the controller boundary before touching
the ORM — same discipline as pydantic models in FastAPI routes.

Usage in controller:
    payload = ActivateRecordInput.from_json(request.jsonrequest)
    service.activate_record(payload.record_id)
\"\"\"
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
        \"\"\"Parse and validate raw JSON payload.\"\"\"
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
"


# =============================================================================
# 8. CONTROLLERS  (thin ports — no business logic)
# =============================================================================
write_file "controllers/__init__.py" "# -*- coding: utf-8 -*-
from . import ${MODULE_NAME}_controller  # noqa: F401
"

write_file "controllers/${MODULE_NAME}_controller.py" "# -*- coding: utf-8 -*-
\"\"\"
HTTP Controller — thin adapter (your FastAPI router equivalent).

Rules:
  - Parse + validate input via schemas/
  - Delegate everything to services/
  - Format and return response
  - Zero business logic here
\"\"\"
import logging
from odoo import http
from odoo.http import request
from odoo.exceptions import ValidationError, UserError
from ..schemas import ActivateRecordInput, CancelRecordInput

_logger = logging.getLogger(__name__)


class ${CLASS_PREFIX}Controller(http.Controller):

    # -------------------------------------------------------------------------
    # Routes
    # -------------------------------------------------------------------------
    @http.route(
        '/api/${MODULE_NAME}/activate',
        type='json',
        auth='user',
        methods=['POST'],
        csrf=False,
    )
    def activate_record(self):
        \"\"\"POST /api/${MODULE_NAME}/activate  { record_id: int }\"\"\"
        return self._handle(self._activate)

    @http.route(
        '/api/${MODULE_NAME}/cancel',
        type='json',
        auth='user',
        methods=['POST'],
        csrf=False,
    )
    def cancel_record(self):
        \"\"\"POST /api/${MODULE_NAME}/cancel  { record_id: int, reason?: str }\"\"\"
        return self._handle(self._cancel)

    # -------------------------------------------------------------------------
    # Private route handlers  (one per route, keeps routing table clean)
    # -------------------------------------------------------------------------
    def _activate(self, payload: dict):
        inp = ActivateRecordInput.from_json(payload)   # validate input
        service = request.env['${MODULE_NAME}.service']
        record = service.activate_record(inp.record_id)
        return self._serialize_record(record)           # format output

    def _cancel(self, payload: dict):
        inp = CancelRecordInput.from_json(payload)
        service = request.env['${MODULE_NAME}.service']
        record = service.cancel_record(inp.record_id, inp.reason)
        return self._serialize_record(record)

    # -------------------------------------------------------------------------
    # Serializer  (your response schema / DTO)
    # -------------------------------------------------------------------------
    @staticmethod
    def _serialize_record(record) -> dict:
        \"\"\"Pure function: recordset → plain dict. No side effects.\"\"\"
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
        \"\"\"Wrap handler: catches domain errors → structured JSON error.\"\"\"
        try:
            payload = request.jsonrequest or {}
            return {'ok': True, 'data': fn(payload)}
        except (ValidationError, UserError) as e:
            return {'ok': False, 'error': str(e.args[0])}
        except Exception as e:
            _logger.exception('Unhandled error in ${MODULE_NAME} controller')
            return {'ok': False, 'error': 'Internal server error'}
"


# =============================================================================
# 9. WIZARDS  (transient multi-step flows)
# =============================================================================
write_file "wizards/__init__.py" "# -*- coding: utf-8 -*-
# from . import ${MODULE_NAME}_wizard
"

write_file "wizards/${MODULE_NAME}_wizard.py" "# -*- coding: utf-8 -*-
\"\"\"
Wizard — transient model for multi-step user flows.
Think of it as a scoped form state + submit handler.
Delegates execution to the service layer.
\"\"\"
from odoo import api, fields, models


class ${CLASS_PREFIX}Wizard(models.TransientModel):
    _name = '${MODULE_NAME}.wizard'
    _description = '${CLASS_PREFIX} Wizard'

    record_id = fields.Many2one('${MODULE_NAME}.record', required=True)
    reason = fields.Text()

    def action_confirm(self):
        \"\"\"Submit handler — delegates to service, returns window action.\"\"\"
        service = self.env['${MODULE_NAME}.service']
        service.cancel_record(self.record_id.id, self.reason or '')
        return {'type': 'ir.actions.act_window_close'}
"


# =============================================================================
# 10. SECURITY
# =============================================================================
write_file "security/ir.model.access.csv" \
"id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_${MODULE_NAME}_record_user,${MODULE_NAME} Record User,model_${MODULE_NAME//-/_}_record,base.group_user,1,1,1,0
access_${MODULE_NAME}_record_manager,${MODULE_NAME} Record Manager,model_${MODULE_NAME//-/_}_record,base.group_system,1,1,1,1
"


# =============================================================================
# 11. TESTS
# =============================================================================
write_file "tests/__init__.py" "# -*- coding: utf-8 -*-
from . import test_${MODULE_NAME}_service
"

write_file "tests/test_${MODULE_NAME}_service.py" "# -*- coding: utf-8 -*-
\"\"\"
Service-layer tests.
Test the service methods directly — not the controller, not the ORM.
Keep tests focused on one use case per method.
\"\"\"
from odoo.tests.common import TransactionCase
from odoo.exceptions import ValidationError


class Test${CLASS_PREFIX}Service(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.service = cls.env['${MODULE_NAME}.service']
        cls.record = cls.env['${MODULE_NAME}.record'].create({'name': 'Test'})

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
        good = self.env['${MODULE_NAME}.record'].create({'name': 'Good'})
        bad  = self.env['${MODULE_NAME}.record'].create({'name': 'Bad'})
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
"


# =============================================================================
# 12. OWL FRONTEND  (your React/reducers equivalent)
# =============================================================================
write_file "static/src/stores/${MODULE_NAME}_store.js" \
"/** @odoo-module **/
/**
 * ${CLASS_PREFIX} Store — reactive state for OWL components.
 *
 * Mental model mapping:
 *   useState / useReducer   →  useState from @odoo/owl
 *   Context provider        →  this store (injected via useService)
 *   Reducer action          →  store method (activate, cancel, etc.)
 *   Side-effect dispatch    →  await this.rpc(...)  (explicit, at the end)
 *
 * Keep this store as the single source of truth for this module's UI state.
 */
import { reactive } from '@odoo/owl';
import { useService } from '@web/core/utils/hooks';

export function use${CLASS_PREFIX}Store() {
    const rpc    = useService('rpc');
    const notify = useService('notification');

    // --- State  (your useReducer initial state) ---
    const state = reactive({
        records: [],
        loading: false,
        error:   null,
    });

    // --- Pure selectors (no side effects) ---
    const getActive = () => state.records.filter(r => r.state === 'active');
    const getById   = (id) => state.records.find(r => r.id === id) ?? null;

    // --- Commands (your reducer actions — async, explicit side effects) ---
    async function activate(recordId) {
        state.loading = true;
        state.error   = null;
        try {
            const res = await rpc('/api/${MODULE_NAME}/activate', { record_id: recordId });
            if (!res.ok) throw new Error(res.error);
            _updateRecord(res.data);           // mutate state last
            notify.add('Record activated', { type: 'success' });
        } catch (e) {
            state.error = e.message;
            notify.add(e.message, { type: 'danger' });
        } finally {
            state.loading = false;
        }
    }

    async function cancel(recordId, reason = '') {
        state.loading = true;
        state.error   = null;
        try {
            const res = await rpc('/api/${MODULE_NAME}/cancel', { record_id: recordId, reason });
            if (!res.ok) throw new Error(res.error);
            _updateRecord(res.data);
            notify.add('Record cancelled', { type: 'warning' });
        } catch (e) {
            state.error = e.message;
        } finally {
            state.loading = false;
        }
    }

    async function loadAll() {
        state.loading = true;
        try {
            state.records = await rpc('/web/dataset/call_kw', {
                model:  '${MODULE_NAME}.record',
                method: 'search_read',
                args:   [[['active', '=', true]]],
                kwargs: { fields: ['id', 'name', 'state'] },
            });
        } finally {
            state.loading = false;
        }
    }

    // --- Private state updater (immutable-style merge) ---
    function _updateRecord(updated) {
        const idx = state.records.findIndex(r => r.id === updated.id);
        if (idx >= 0) {
            state.records[idx] = { ...state.records[idx], ...updated };
        }
    }

    return { state, getActive, getById, activate, cancel, loadAll };
}
"

write_file "static/src/components/${CLASS_PREFIX}Card.xml" \
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<templates xml:space=\"preserve\">
  <!--
    Presentational component — receives all data via props, emits events up.
    No store access here (mirrors React presentational / container split).
  -->
  <t t-name=\"${MODULE_NAME}.${CLASS_PREFIX}Card\">
    <div class=\"o_${MODULE_NAME}_card p-3 border rounded\">
      <div class=\"d-flex justify-content-between align-items-center\">
        <span t-esc=\"props.record.name\" class=\"fw-bold\"/>
        <span t-attf-class=\"badge bg-{{ props.record.state === 'active' ? 'success' : 'secondary' }}\">
          <t t-esc=\"props.record.state\"/>
        </span>
      </div>
      <div class=\"mt-2\">
        <button
          t-if=\"props.record.state === 'draft'\"
          class=\"btn btn-sm btn-primary me-1\"
          t-on-click=\"() => props.onActivate(props.record.id)\">
          Activate
        </button>
        <button
          t-if=\"props.record.state !== 'cancelled'\"
          class=\"btn btn-sm btn-outline-danger\"
          t-on-click=\"() => props.onCancel(props.record.id)\">
          Cancel
        </button>
      </div>
    </div>
  </t>
</templates>
"


# =============================================================================
# 13. VIEWS placeholder
# =============================================================================
write_file "views/${MODULE_NAME}_views.xml" \
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<odoo>
  <!-- List view -->
  <record id=\"view_${MODULE_NAME}_record_list\" model=\"ir.ui.view\">
    <field name=\"name\">${MODULE_NAME}.record.list</field>
    <field name=\"model\">${MODULE_NAME}.record</field>
    <field name=\"arch\" type=\"xml\">
      <list>
        <field name=\"name\"/>
        <field name=\"state\"/>
      </list>
    </field>
  </record>

  <!-- Form view -->
  <record id=\"view_${MODULE_NAME}_record_form\" model=\"ir.ui.view\">
    <field name=\"name\">${MODULE_NAME}.record.form</field>
    <field name=\"model\">${MODULE_NAME}.record</field>
    <field name=\"arch\" type=\"xml\">
      <form>
        <header>
          <field name=\"state\" widget=\"statusbar\"/>
        </header>
        <sheet>
          <group>
            <field name=\"name\"/>
          </group>
        </sheet>
        <chatter/>
      </form>
    </field>
  </record>
</odoo>
"


# =============================================================================
# 14. README
# =============================================================================
write_file "README.md" "# ${MODULE_NAME}

## Architecture Layers

\`\`\`
controllers/          ← Thin HTTP adapters (ports). No business logic.
services/             ← Use cases / application layer. One method = one use case.
models/
  domain/             ← Fields, constraints, computed fields, guard clauses.
  query/              ← Read-only repository methods. Never call write().
  mixins/             ← Reusable abstract field/method groups.
schemas/              ← Input validation (pydantic-style dataclasses).
wizards/              ← Transient UI flows. Delegates to services/.
static/src/
  stores/             ← OWL reactive state (replaces React context/reducers).
  components/         ← Presentational OWL components.
tests/                ← Service-layer tests. One use case per test method.
\`\`\`

## Conventions

| Prefix       | Rule                                           |
|--------------|------------------------------------------------|
| \`_assert_*\`  | Pure guard — raises or passes, never mutates   |
| \`_compute_*\` | Pure derivation — only assigns computed fields |
| \`_apply_*\`   | All \`write()\` calls live here                  |
| \`_notify_*\`  | Explicit side effects — emails, webhooks, logs |
| \`_query_*\`   | Read-only search — never calls \`write()\`       |

## Pattern: Ensure → Assert → Execute

\`\`\`python
def my_use_case(self, record_id):
    record = self._load_record(record_id)   # 1. fetch
    record._assert_precondition()           # 2. guard (pure)
    self._apply_mutation(record)            # 3. mutate (explicit)
    self._notify_stakeholders(record)       # 4. side effects (last)
    return record                           # 5. return
\`\`\`
"


# =============================================================================
# 15. DONE — print tree
# =============================================================================
echo "✅  Module scaffolded at: $ROOT"
echo ""

if command -v tree &>/dev/null; then
  tree "$ROOT"
else
  find "$ROOT" | sort | sed "s|$ROOT||;s|/\([^/]*\)$| └── \1|;s|/| │   |g"
fi

echo ""
echo "Next steps:"
echo "  1. Add '$MODULE_NAME' to your odoo.conf addons_path"
echo "  2. Restart Odoo and install: Settings → Apps → search '$MODULE_NAME'"
echo "  3. Run tests: ./odoo-bin -d <db> --test-enable -i $MODULE_NAME"
