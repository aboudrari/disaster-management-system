
-- ============================================================
-- SENTINEL
-- DATABASE TRIGGERS
-- Database: PostgreSQL (Supabase)
-- ============================================================


-- ============================================================
-- 1. INVENTORY BALANCE TRIGGER
-- Purpose:
-- Automatically update inventory_balances whenever a new
-- inventory transaction is inserted.
--
-- Positive movements:
-- receipt, return, transfer_in, adjustment
--
-- Negative movements:
-- dispatch, transfer_out
--
-- Adjustment is treated as a positive stock correction.
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_inventory_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_item_org UUID;
    v_location_org UUID;
    v_new_balance NUMERIC(14,3);
BEGIN
    -- Verify that the resource item and location
    -- belong to the same organization.
    SELECT organization_id
    INTO v_item_org
    FROM public.resource_items
    WHERE id = NEW.resource_item_id;

    SELECT organization_id
    INTO v_location_org
    FROM public.resource_locations
    WHERE id = NEW.resource_location_id;

    IF v_item_org IS NULL OR v_location_org IS NULL THEN
        RAISE EXCEPTION 'Invalid resource item or location';
    END IF;

    IF v_item_org <> v_location_org THEN
        RAISE EXCEPTION
            'Resource item and location must belong to the same organization';
    END IF;

    -- Positive stock movements.
    IF NEW.transaction_type IN (
        'receipt',
        'return',
        'transfer_in',
        'adjustment'
    ) THEN

        INSERT INTO public.inventory_balances (
            resource_item_id,
            resource_location_id,
            quantity_on_hand,
            updated_at
        )
        VALUES (
            NEW.resource_item_id,
            NEW.resource_location_id,
            NEW.quantity,
            now()
        )

        ON CONFLICT (
            resource_item_id,
            resource_location_id
        )

        DO UPDATE SET
            quantity_on_hand =
                public.inventory_balances.quantity_on_hand
                + EXCLUDED.quantity_on_hand,
            updated_at = now();

    -- Negative stock movements.
    ELSIF NEW.transaction_type IN (
        'dispatch',
        'transfer_out'
    ) THEN

        UPDATE public.inventory_balances
        SET
            quantity_on_hand = quantity_on_hand - NEW.quantity,
            updated_at = now()
        WHERE resource_item_id = NEW.resource_item_id
          AND resource_location_id = NEW.resource_location_id
          AND quantity_on_hand >= NEW.quantity
        RETURNING quantity_on_hand INTO v_new_balance;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Insufficient stock for resource item % at location %',
                NEW.resource_item_id,
                NEW.resource_location_id;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER trg_update_inventory_balance
AFTER INSERT ON public.inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION public.update_inventory_balance();


-- ============================================================
-- 2. INVENTORY TRANSACTION IMMUTABILITY
-- Purpose:
-- Prevent modification or deletion of inventory transactions.
-- Corrections must be recorded as new transactions.
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_inventory_transaction_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Inventory transactions cannot be updated or deleted. Create a correcting transaction instead.';
END;
$$;


CREATE TRIGGER trg_prevent_inventory_transaction_changes
BEFORE UPDATE OR DELETE ON public.inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION public.prevent_inventory_transaction_changes();


-- ============================================================
-- 3. INCIDENT STATUS HISTORY TRIGGER
-- Purpose:
-- Automatically record incident status changes.
-- Initial incident creation is also recorded.
-- ============================================================

CREATE OR REPLACE FUNCTION public.record_incident_status_history()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor UUID;
    v_reason TEXT;
BEGIN
    -- Identify the authenticated user when available.
    SELECT id
    INTO v_actor
    FROM public.profiles
    WHERE id = auth.uid();

    -- Optional reason supplied by the application.
    v_reason := NULLIF(
        current_setting('app.incident_change_reason', true),
        ''
    );

    IF TG_OP = 'INSERT' THEN

        INSERT INTO public.incident_status_history (
            incident_id,
            previous_status,
            new_status,
            changed_by,
            reason
        )
        VALUES (
            NEW.id,
            NULL,
            NEW.status,
            v_actor,
            'Initial incident status'
        );

    ELSIF OLD.status IS DISTINCT FROM NEW.status THEN

        INSERT INTO public.incident_status_history (
            incident_id,
            previous_status,
            new_status,
            changed_by,
            reason
        )
        VALUES (
            NEW.id,
            OLD.status,
            NEW.status,
            v_actor,
            v_reason
        );

    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER trg_record_incident_status_history
AFTER INSERT OR UPDATE OF status
ON public.incidents
FOR EACH ROW
EXECUTE FUNCTION public.record_incident_status_history();


-- ============================================================
-- 4. AUDIT LOG TRIGGER
-- Purpose:
-- Record INSERT, UPDATE, and DELETE operations on incidents.
-- Store previous and new row values as JSONB.
-- ============================================================

CREATE OR REPLACE FUNCTION public.audit_incident_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor UUID;
    v_organization_id UUID;
    v_entity_id UUID;
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    -- Get the authenticated user if a matching profile exists.
    SELECT id
    INTO v_actor
    FROM public.profiles
    WHERE id = auth.uid();

    IF TG_OP = 'DELETE' THEN

        v_organization_id := OLD.organization_id;
        v_entity_id := OLD.id;
        v_old_values := to_jsonb(OLD);
        v_new_values := NULL;

    ELSIF TG_OP = 'UPDATE' THEN

        v_organization_id := NEW.organization_id;
        v_entity_id := NEW.id;
        v_old_values := to_jsonb(OLD);
        v_new_values := to_jsonb(NEW);

    ELSE

        v_organization_id := NEW.organization_id;
        v_entity_id := NEW.id;
        v_old_values := NULL;
        v_new_values := to_jsonb(NEW);

    END IF;

    INSERT INTO public.audit_logs (
        organization_id,
        actor_user_id,
        action,
        entity_table,
        entity_id,
        old_values,
        new_values
    )
    VALUES (
        v_organization_id,
        v_actor,
        TG_OP,
        'incidents',
        v_entity_id,
        v_old_values,
        v_new_values
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER trg_audit_incident_changes
AFTER INSERT OR UPDATE OR DELETE
ON public.incidents
FOR EACH ROW
EXECUTE FUNCTION public.audit_incident_changes();


-- ============================================================
-- 5. SHELTER CAPACITY VALIDATION TRIGGER
-- Purpose:
-- Prevent active shelter assignments from exceeding capacity.
--
-- Lock the shelter row to prevent concurrent assignments
-- from exceeding its available capacity.
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_shelter_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INTEGER;
    v_occupied BIGINT;
    v_shelter_status TEXT;
BEGIN
    -- Only validate assignments that are active.
    IF NEW.checked_out_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Lock the shelter row to serialize concurrent assignments.
    SELECT capacity, status
    INTO v_capacity, v_shelter_status
    FROM public.shelters
    WHERE id = NEW.shelter_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shelter does not exist';
    END IF;

    IF v_shelter_status <> 'open' THEN
        RAISE EXCEPTION
            'Cannot assign a person to a shelter that is not open';
    END IF;

    -- Count active assignments, excluding the current row
    -- when an existing assignment is being updated.
    SELECT COUNT(*)
    INTO v_occupied
    FROM public.shelter_assignments
    WHERE shelter_id = NEW.shelter_id
      AND checked_out_at IS NULL
      AND id IS DISTINCT FROM NEW.id;

    IF v_occupied >= v_capacity THEN
        RAISE EXCEPTION
            'Shelter capacity exceeded. Capacity: %, Occupied: %',
            v_capacity,
            v_occupied;
    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER trg_validate_shelter_capacity
BEFORE INSERT OR UPDATE OF shelter_id, checked_out_at
ON public.shelter_assignments
FOR EACH ROW
EXECUTE FUNCTION public.validate_shelter_capacity();


-- ============================================================
-- END OF SENTINEL DATABASE TRIGGERS
-- ============================================================
