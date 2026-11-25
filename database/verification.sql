
-- ============================================================
-- SENTINEL
-- DATABASE VERIFICATION
-- Purpose:
-- Verify PL/pgSQL functions, procedures, triggers,
-- inventory consistency, incident history and shelter capacity.
--
-- This file is designed for read-only verification.
-- Trigger behavior tests use temporary changes inside
-- exception-safe subtransactions.
-- ============================================================


-- ============================================================
-- TEST 01: Verify Functions and Procedure
-- Expected: 8 routines.
-- ============================================================

SELECT
    routine_name,
    routine_type,
    routine_schema
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
      'get_shelter_availability',
      'get_resource_stock_status',
      'record_inventory_transaction',
      'update_inventory_balance',
      'prevent_inventory_transaction_changes',
      'record_incident_status_history',
      'audit_incident_changes',
      'validate_shelter_capacity'
  )
ORDER BY routine_type, routine_name;


-- ============================================================
-- TEST 02: Verify Triggers
-- Expected: 5 triggers.
-- ============================================================

SELECT
    trigger_name,
    event_object_table AS table_name,
    event_manipulation AS event,
    action_timing AS timing,
    action_orientation AS orientation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name IN (
      'trg_update_inventory_balance',
      'trg_prevent_inventory_transaction_changes',
      'trg_record_incident_status_history',
      'trg_audit_incident_changes',
      'trg_validate_shelter_capacity'
  )
ORDER BY event_object_table, trigger_name;


-- ============================================================
-- TEST 03: Verify Shelter Availability Function
-- ============================================================

SELECT
    s.name AS shelter_name,
    availability.shelter_capacity,
    availability.occupied_spots,
    availability.available_spots,
    availability.occupancy_percentage
FROM public.shelters AS s
CROSS JOIN LATERAL
    public.get_shelter_availability(s.id) AS availability
ORDER BY s.name
LIMIT 5;


-- ============================================================
-- TEST 04: Verify Resource Stock Status Function
-- ============================================================

SELECT
    ri.item_name,
    rl.name AS location_name,
    stock.quantity_on_hand,
    stock.minimum_stock_level,
    stock.stock_status
FROM public.resource_items AS ri
INNER JOIN public.resource_locations AS rl
    ON rl.organization_id = ri.organization_id
CROSS JOIN LATERAL
    public.get_resource_stock_status(ri.id, rl.id) AS stock
WHERE ri.is_active = TRUE
  AND rl.is_active = TRUE
ORDER BY ri.item_name, rl.name
LIMIT 10;


-- ============================================================
-- TEST 05: Verify Inventory Ledger Consistency
-- Compare stored balances with transaction history.
--
-- NOTE:
-- Adjustment is treated as a positive movement.
-- ============================================================

WITH transaction_totals AS (
    SELECT
        resource_item_id,
        resource_location_id,
        SUM(
            CASE
                WHEN transaction_type IN (
                    'receipt',
                    'return',
                    'transfer_in',
                    'adjustment'
                )
                THEN quantity

                WHEN transaction_type IN (
                    'dispatch',
                    'transfer_out'
                )
                THEN -quantity

                ELSE 0
            END
        ) AS ledger_balance
    FROM public.inventory_transactions
    GROUP BY
        resource_item_id,
        resource_location_id
)
SELECT
    ri.item_name,
    rl.name AS location_name,
    ib.quantity_on_hand,
    COALESCE(tt.ledger_balance, 0) AS ledger_balance,
    CASE
        WHEN ib.quantity_on_hand =
             COALESCE(tt.ledger_balance, 0)
        THEN 'MATCH'
        ELSE 'MISMATCH'
    END AS verification_status
FROM public.inventory_balances AS ib
INNER JOIN public.resource_items AS ri
    ON ib.resource_item_id = ri.id
INNER JOIN public.resource_locations AS rl
    ON ib.resource_location_id = rl.id
LEFT JOIN transaction_totals AS tt
    ON tt.resource_item_id = ib.resource_item_id
   AND tt.resource_location_id = ib.resource_location_id
ORDER BY ri.item_name;


-- ============================================================
-- TEST 06: Verify Incident Status History
-- Displays the latest recorded status transitions.
-- ============================================================

SELECT
    i.incident_code,
    h.previous_status,
    h.new_status,
    h.reason,
    h.changed_at
FROM public.incident_status_history AS h
INNER JOIN public.incidents AS i
    ON i.id = h.incident_id
ORDER BY h.changed_at DESC
LIMIT 10;


-- ============================================================
-- TEST 07: Verify Incident Audit Logs
-- Displays the latest incident audit records.
-- ============================================================

SELECT
    action,
    entity_table,
    entity_id,
    old_values->>'status' AS old_status,
    new_values->>'status' AS new_status,
    occurred_at
FROM public.audit_logs
WHERE entity_table = 'incidents'
ORDER BY occurred_at DESC
LIMIT 10;


-- ============================================================
-- TEST 08: Verify Inventory Transaction Immutability
-- Expected: UPDATE is rejected by the trigger.
--
-- The nested exception block rolls back the attempted update.
-- No permanent data modification occurs.
-- ============================================================

DO $$
DECLARE
    v_transaction_id UUID;
    v_error_message TEXT;
    v_blocked BOOLEAN := FALSE;
BEGIN
    SELECT id
    INTO v_transaction_id
    FROM public.inventory_transactions
    LIMIT 1;

    IF v_transaction_id IS NULL THEN
        RAISE EXCEPTION 'No inventory transaction available for testing';
    END IF;

    BEGIN
        UPDATE public.inventory_transactions
        SET notes = COALESCE(notes, '') || ' verification test'
        WHERE id = v_transaction_id;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_message = MESSAGE_TEXT;

        IF v_error_message LIKE '%cannot be updated or deleted%'
           OR v_error_message LIKE '%immutable%'
        THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION
            'FAIL: Inventory transaction update was not blocked';
    END IF;

    RAISE NOTICE
        'PASS: Inventory transaction update was blocked';
END $$;


-- ============================================================
-- TEST 09: Verify Shelter Capacity Protection
-- Expected: An additional active assignment is rejected
-- when the shelter is already at capacity.
--
-- Changes inside the nested exception block are rolled back.
-- ============================================================

DO $$
DECLARE
    v_shelter_id UUID;
    v_person_id UUID;
    v_assigned_by UUID;
    v_error_message TEXT;
    v_blocked BOOLEAN := FALSE;
BEGIN
    SELECT
        s.id,
        ap.id,
        sa.assigned_by
    INTO
        v_shelter_id,
        v_person_id,
        v_assigned_by
    FROM public.shelters AS s
    INNER JOIN public.affected_persons AS ap
        ON ap.incident_id = s.incident_id
       AND ap.full_name = 'Jamie Wilson'
    INNER JOIN public.shelter_assignments AS sa
        ON sa.shelter_id = s.id
       AND sa.checked_out_at IS NULL
    WHERE s.name = 'Community Emergency Shelter'
    LIMIT 1;

    IF v_shelter_id IS NULL
       OR v_person_id IS NULL
       OR v_assigned_by IS NULL
    THEN
        RAISE NOTICE
            'SKIPPED: Required shelter test records were not found';
        RETURN;
    END IF;

    BEGIN
        UPDATE public.shelters
        SET capacity = 1
        WHERE id = v_shelter_id;

        INSERT INTO public.shelter_assignments (
            person_id,
            shelter_id,
            assigned_by
        )
        VALUES (
            v_person_id,
            v_shelter_id,
            v_assigned_by
        );

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_message = MESSAGE_TEXT;

        IF v_error_message LIKE '%Shelter capacity exceeded%'
        THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;

    IF NOT v_blocked THEN
        RAISE EXCEPTION
            'FAIL: Shelter capacity trigger did not block the assignment';
    END IF;

    RAISE NOTICE
        'PASS: Shelter capacity trigger blocked the extra assignment';
END $$;


-- ============================================================
-- END OF VERIFICATION
-- ============================================================
