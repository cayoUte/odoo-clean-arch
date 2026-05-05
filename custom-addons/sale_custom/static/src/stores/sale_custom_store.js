/** @odoo-module **/
/**
 * SaleCustom Store — reactive state for OWL components.
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

export function useSaleCustomStore() {
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
            const res = await rpc('/api/sale_custom/activate', { record_id: recordId });
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
            const res = await rpc('/api/sale_custom/cancel', { record_id: recordId, reason });
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
                model:  'sale_custom.record',
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

