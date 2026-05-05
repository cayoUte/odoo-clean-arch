# sale_custom

## Architecture Layers

```
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
```

## Conventions

| Prefix       | Rule                                           |
|--------------|------------------------------------------------|
| `_assert_*`  | Pure guard — raises or passes, never mutates   |
| `_compute_*` | Pure derivation — only assigns computed fields |
| `_apply_*`   | All `write()` calls live here                  |
| `_notify_*`  | Explicit side effects — emails, webhooks, logs |
| `_query_*`   | Read-only search — never calls `write()`       |

## Pattern: Ensure → Assert → Execute

```python
def my_use_case(self, record_id):
    record = self._load_record(record_id)   # 1. fetch
    record._assert_precondition()           # 2. guard (pure)
    self._apply_mutation(record)            # 3. mutate (explicit)
    self._notify_stakeholders(record)       # 4. side effects (last)
    return record                           # 5. return
```

