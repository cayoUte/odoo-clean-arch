# odoo-clean-arch

A structured approach to Odoo 19 module development, written for developers coming from hexagonal architecture, FastAPI, and React. Each module in this repo demonstrates a layered pattern that contains side effects, separates reads from writes, and gives every piece of business logic a clear home.

---

## Motivation

Odoo's ORM is a shared, mutable object graph. Without explicit conventions, business logic drifts into controllers, computed fields trigger unintended writes, and a single RPC call quietly touches six models. This repo applies a small set of rules that make those effects visible and predictable — without fighting Odoo's OOP nature.

---

## Mental Model Map

If you come from the stack this repo was designed around, these equivalences apply:

| Your World | Odoo Equivalent |
|---|---|
| Pydantic schema | `_fields` + `@api.constrains` + `_sql_constraints` |
| Repository interface | `models/query/` — `search`, `filtered`, `mapped` only |
| Unit of Work | `self.env.cr` transaction + `cr.savepoint()` for batches |
| Service layer | `services/` — one public method per use case |
| Controller / router | `controllers/` — parse, delegate, serialize, nothing else |
| Dependency injection | `self.env` + `with_context()` |
| `useReducer` + Context | OWL `reactive` store in `static/src/stores/` |
| Presentational component | OWL component receiving props, emitting events |

---

## Architecture

```
my_module/
│
├── controllers/              # Ports — thin HTTP adapters, zero business logic
│   └── my_module_controller.py
│
├── services/                 # Application layer — one method = one use case
│   └── my_module_service.py
│
├── models/
│   ├── domain/               # Fields, constraints, computed fields, guard clauses
│   │   └── my_module_model.py
│   ├── query/                # Read-only finders — never call write()
│   │   └── my_module_query.py
│   └── mixins/               # Reusable abstract field/method groups
│       └── timestamp_mixin.py
│
├── schemas/                  # Input validation (frozen dataclasses, pydantic-style)
│   └── input_schemas.py
│
├── wizards/                  # Transient UI flows — delegate to services/
│   └── my_module_wizard.py
│
├── static/src/
│   ├── stores/               # OWL reactive state (replaces useReducer + Context)
│   │   └── my_module_store.js
│   ├── components/           # Presentational OWL components (props in, events out)
│   └── services/             # Frontend RPC service layer
│
├── tests/                    # Service-layer tests — one use case per method
├── security/
├── views/
├── data/
└── __manifest__.py
```

---

## Core Conventions

### Method Naming Contract

Every method name communicates its contract:

| Prefix | Contract |
|---|---|
| `_assert_*` | Pure guard — raises `ValidationError` or passes. Never mutates. |
| `_compute_*` | Pure derivation — reads dependencies, assigns to `self.field` only. |
| `_apply_*` | All `write()` / `create()` / `unlink()` calls live here. |
| `_notify_*` | Explicit side effects — emails, chatter, webhooks. Always called last. |
| `_query_*` | Read-only search helpers. Never calls `write()`. |
| `_load_*` | Fetch + existence check. Returns a record or raises. |

### The Ensure → Assert → Execute Pattern

Every public service method follows this sequence:

```python
def use_case_name(self, record_id: int):
    record = self._load_record(record_id)      # 1. fetch + existence check
    record._assert_precondition()              # 2. guard clauses (pure)
    self._apply_mutation(record)               # 3. all writes in one place
    self._notify_stakeholders(record)          # 4. side effects, explicit, last
    return record                              # 5. return result, don't mutate caller
```

### Reads and Writes Never Mix

```python
# query/ — reads only
def query_active_by_company(self, company_id: int):
    return self.env['my.model'].search([
        ('state', '=', 'active'),
        ('company_id', '=', company_id),
    ])

# services/ — writes only, after guards pass
def _apply_activate(self, record):
    record.write({'state': 'active', 'processed_at': fields.Datetime.now()})
```

### Batch Isolation with Savepoints

One failure in a batch should not roll back the whole transaction:

```python
def process_batch(self, record_ids: list[int]):
    results = {'success': [], 'failed': []}
    for record_id in record_ids:
        try:
            with self.env.cr.savepoint():
                record = self.activate_record(record_id)
                results['success'].append(record.id)
        except Exception as e:
            _logger.warning('Record %s failed: %s', record_id, e)
            results['failed'].append({'id': record_id, 'error': str(e)})
    return results
```

### Context Threading (Immutable-style)

`with_context()` returns a new recordset — it does not mutate the original. Use it to thread configuration down a call chain without global state:

```python
# Never: self._context['key'] = value
# Always:
localized = self.with_context(lang=self.partner_id.lang)
elevated  = self.env['ir.config_parameter'].sudo()
```

### Input Validation at the Boundary

Validate before touching the ORM, not after:

```python
@dataclass(frozen=True)
class ActivateRecordInput:
    record_id: int

    def __post_init__(self):
        if self.record_id <= 0:
            raise ValidationError('record_id must be a positive integer.')

    @classmethod
    def from_json(cls, data: dict) -> 'ActivateRecordInput':
        try:
            return cls(record_id=int(data['record_id']))
        except (KeyError, TypeError, ValueError) as e:
            raise ValidationError(f'Invalid payload: {e}') from e
```

---

## Scaffold Script

Every module in this repo was bootstrapped with [`new_odoo_module.sh`](./new_odoo_module.sh). It generates the full directory tree with stub files pre-wired to these conventions.

```bash
bash new_odoo_module.sh <module_name> [addons_path]

# Example
bash new_odoo_module.sh sale_custom ./custom_addons
```

---

## Running Tests

```bash
# Single module
./odoo-bin -d <your_db> --test-enable -i my_module

# With log output
./odoo-bin -d <your_db> --test-enable --log-level=test -i my_module
```

Tests live in `tests/` and target the service layer directly. Controllers and views are not unit tested here — integration tests via Odoo's `HttpCase` are kept separate.

---

## References

- [Odoo 19 Developer Documentation](https://www.odoo.com/documentation/19.0/developer.html)
- [OWL Framework](https://github.com/odoo/owl)
- [Odoo ORM API](https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html)
