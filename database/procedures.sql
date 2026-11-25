
-- ============================================================
-- SENTINEL
-- DATABASE FUNCTIONS & PROCEDURES
-- Database: PostgreSQL (Supabase)
-- ============================================================


-- ============================================================
-- 1. FUNCTION: Get Shelter Availability
-- Purpose:
-- Calculate the current occupancy and remaining capacity
-- of a shelter using active shelter assignments.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_shelter_availability(
    p_shelter_id UUID
)
RETURNS TABLE (
    shelter_capacity INTEGER,
    occupied_spots BIGINT,
    available_spots INTEGER,
    occupancy_percentage NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INTEGER;
    v_occupied BIGINT;
BEGIN
    SELECT s.capacity
    INTO v_capacity
    FROM public.shelters AS s
    WHERE s.id = p_shelter_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shelter % does not exist', p_shelter_id;
    END IF;

    SELECT COUNT(*)
    INTO v_occupied
    FROM public.shelter_assignments AS sa
    WHERE sa.shelter_id = p_shelter_id
      AND sa.checked_out_at IS NULL;

    RETURN QUERY
    SELECT
        v_capacity,
        v_occupied,
        GREATEST(v_capacity::BIGINT - v_occupied, 0)::INTEGER,
        ROUND(
            v_occupied * 100.0 / NULLIF(v_capacity, 0),
            2
        );
END;
$$;


-- ============================================================
-- 2. FUNCTION: Get Resource Stock Status
-- Purpose:
-- Retrieve the current stock of a resource at a location
-- and classify it as Out of Stock, Low Stock, or Sufficient.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_resource_stock_status(
    p_resource_item_id UUID,
    p_resource_location_id UUID
)
RETURNS TABLE (
    quantity_on_hand NUMERIC,
    minimum_stock_level NUMERIC,
    stock_status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_quantity NUMERIC;
    v_minimum_stock NUMERIC;
BEGIN
    SELECT
        COALESCE(ib.quantity_on_hand, 0),
        ri.minimum_stock_level
    INTO
        v_quantity,
        v_minimum_stock
    FROM public.resource_items AS ri

    INNER JOIN public.resource_locations AS rl
        ON rl.organization_id = ri.organization_id

    LEFT JOIN public.inventory_balances AS ib
        ON ib.resource_item_id = ri.id
        AND ib.resource_location_id = rl.id

    WHERE ri.id = p_resource_item_id
      AND rl.id = p_resource_location_id
      AND ri.is_active = TRUE
      AND rl.is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Resource item or location does not exist, is inactive, or belongs to a different organization';
    END IF;

    RETURN QUERY
    SELECT
        v_quantity,
        v_minimum_stock,
        CASE
            WHEN v_quantity = 0 THEN 'Out of Stock'
            WHEN v_quantity <= v_minimum_stock THEN 'Low Stock'
            ELSE 'Sufficient Stock'
        END;
END;
$$;


-- ============================================================
-- 3. PROCEDURE: Record Inventory Transaction
-- Purpose:
-- Insert an inventory transaction through one controlled
-- database operation.
--
-- IMPORTANT:
-- The inventory trigger will update inventory_balances
-- automatically after this transaction is inserted.
-- ============================================================

CREATE OR REPLACE PROCEDURE public.record_inventory_transaction(
    p_resource_item_id UUID,
    p_resource_location_id UUID,
    p_transaction_type TEXT,
    p_quantity NUMERIC,
    p_reference_type TEXT DEFAULT NULL,
    p_reference_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_performed_by UUID DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Transaction quantity must be greater than zero';
    END IF;

    IF p_transaction_type NOT IN (
        'receipt',
        'dispatch',
        'transfer_in',
        'transfer_out',
        'adjustment',
        'return'
    ) THEN
        RAISE EXCEPTION 'Invalid inventory transaction type: %',
            p_transaction_type;
    END IF;

    INSERT INTO public.inventory_transactions (
        resource_item_id,
        resource_location_id,
        transaction_type,
        quantity,
        reference_type,
        reference_id,
        notes,
        performed_by
    )
    VALUES (
        p_resource_item_id,
        p_resource_location_id,
        p_transaction_type,
        p_quantity,
        p_reference_type,
        p_reference_id,
        p_notes,
        p_performed_by
    );
END;
$$;


-- ============================================================
-- END OF SENTINEL FUNCTIONS & PROCEDURES
-- ============================================================
