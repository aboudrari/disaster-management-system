
-- ============================================================
-- SENTINEL
-- MANAGEMENT QUERIES
-- Total Queries: 7
-- Database: PostgreSQL (Supabase)
-- ============================================================


-- ============================================================
-- QUERY 01: Incident Overview
-- Purpose: Summarize incidents by type, status, and priority.
-- Concepts: INNER JOIN, COUNT, AVG, SUM, GROUP BY, ORDER BY
-- ============================================================

SELECT
    o.name AS organization_name,
    i.disaster_type,
    i.status,
    i.priority,

    COUNT(i.id) AS total_incidents,
    ROUND(AVG(i.severity), 2) AS average_severity,
    COALESCE(SUM(i.estimated_affected), 0) AS total_estimated_affected

FROM public.incidents AS i

INNER JOIN public.organizations AS o
    ON i.organization_id = o.id

GROUP BY
    o.id,
    o.name,
    i.disaster_type,
    i.status,
    i.priority

ORDER BY
    o.name,
    total_incidents DESC,
    average_severity DESC;


-- ============================================================
-- QUERY 02: Incident Severity Analysis
-- Purpose: Classify incidents by severity and summarize impact.
-- Concepts: CASE, COUNT, AVG, SUM, GROUP BY
-- ============================================================

SELECT
    o.name AS organization_name,

    CASE
        WHEN i.severity = 1 THEN 'Very Low'
        WHEN i.severity = 2 THEN 'Low'
        WHEN i.severity = 3 THEN 'Moderate'
        WHEN i.severity = 4 THEN 'High'
        WHEN i.severity = 5 THEN 'Critical'
        ELSE 'Unclassified'
    END AS severity_level,

    COUNT(i.id) AS total_incidents,
    ROUND(AVG(i.severity), 2) AS average_severity,
    COALESCE(SUM(i.estimated_affected), 0) AS total_estimated_affected

FROM public.incidents AS i

INNER JOIN public.organizations AS o
    ON i.organization_id = o.id

GROUP BY
    o.id,
    o.name,
    severity_level

ORDER BY
    o.name,
    average_severity DESC;


-- ============================================================
-- QUERY 03: Team & Mission Performance
-- Purpose: Measure team assignments and mission completion.
-- Concepts: LEFT JOIN, COUNT DISTINCT, CASE, GROUP BY
-- ============================================================

SELECT
    o.name AS organization_name,
    t.name AS team_name,

    COUNT(DISTINCT m.id) AS total_missions,

    COUNT(
        DISTINCT CASE
            WHEN m.status = 'completed' THEN m.id
        END
    ) AS completed_missions,

    COUNT(
        DISTINCT CASE
            WHEN m.status = 'in_progress' THEN m.id
        END
    ) AS active_missions

FROM public.teams AS t

INNER JOIN public.organizations AS o
    ON t.organization_id = o.id

LEFT JOIN public.mission_assignments AS ma
    ON t.id = ma.team_id

LEFT JOIN public.missions AS m
    ON ma.mission_id = m.id

GROUP BY
    o.id,
    o.name,
    t.id,
    t.name

ORDER BY
    total_missions DESC,
    t.name;


-- ============================================================
-- QUERY 04: Resource Inventory Analysis
-- Purpose: Monitor stock levels and identify resources
--          requiring replenishment.
-- Concepts: INNER JOIN, LEFT JOIN, COALESCE, CASE
-- ============================================================

SELECT
    o.name AS organization_name,
    rl.name AS location_name,
    ri.item_name,
    ri.unit,

    COALESCE(ib.quantity_on_hand, 0) AS quantity_on_hand,
    ri.minimum_stock_level,

    CASE
        WHEN COALESCE(ib.quantity_on_hand, 0) = 0
            THEN 'Out of Stock'

        WHEN COALESCE(ib.quantity_on_hand, 0) <= ri.minimum_stock_level
            THEN 'Low Stock'

        ELSE 'Sufficient Stock'
    END AS stock_status

FROM public.resource_items AS ri

INNER JOIN public.organizations AS o
    ON ri.organization_id = o.id

INNER JOIN public.resource_locations AS rl
    ON rl.organization_id = ri.organization_id

LEFT JOIN public.inventory_balances AS ib
    ON ri.id = ib.resource_item_id
    AND rl.id = ib.resource_location_id

WHERE
    rl.is_active = TRUE
    AND ri.is_active = TRUE

ORDER BY
    rl.name,
    stock_status,
    ri.item_name;


-- ============================================================
-- QUERY 05: Resource Request Fulfillment Analysis
-- Purpose: Track requested, approved, and fulfilled resources.
-- Concepts: INNER JOIN, CASE, Calculated Columns
-- ============================================================

SELECT
    rr.request_code,
    rr.status AS request_status,
    rr.priority,

    ri.item_name,
    ri.unit,

    rri.quantity_requested,
    rri.quantity_approved,
    rri.quantity_fulfilled,

    (
        rri.quantity_approved - rri.quantity_fulfilled
    ) AS remaining_quantity,

    CASE
        WHEN rri.quantity_approved = 0
            THEN 'Not Approved'

        WHEN rri.quantity_fulfilled = rri.quantity_approved
            THEN 'Fully Fulfilled'

        WHEN rri.quantity_fulfilled > 0
            THEN 'Partially Fulfilled'

        ELSE 'Pending Fulfillment'
    END AS fulfillment_status

FROM public.resource_requests AS rr

INNER JOIN public.resource_request_items AS rri
    ON rr.id = rri.request_id

INNER JOIN public.resource_items AS ri
    ON rri.resource_item_id = ri.id

ORDER BY
    rr.request_code,
    ri.item_name;


-- ============================================================
-- QUERY 06: Shelter Occupancy Analysis
-- Purpose: Monitor shelter capacity and current occupancy.
-- Concepts: LEFT JOIN, COUNT DISTINCT, GREATEST, NULLIF,
--           CEIL, CASE, NULLS LAST
-- ============================================================

SELECT
    o.name AS organization_name,
    s.name AS shelter_name,
    s.status AS shelter_status,

    s.capacity,

    COUNT(DISTINCT sa.person_id) AS occupied_spots,

    CASE
        WHEN s.capacity IS NULL THEN NULL
        ELSE GREATEST(
            s.capacity - COUNT(DISTINCT sa.person_id),
            0
        )
    END AS available_spots,

    ROUND(
        COUNT(DISTINCT sa.person_id) * 100.0
        / NULLIF(s.capacity, 0),
        2
    ) AS occupancy_percentage,

    CASE
        WHEN s.capacity IS NULL OR s.capacity <= 0
            THEN 'Capacity Not Set'

        WHEN COUNT(DISTINCT sa.person_id) >= s.capacity
            THEN 'Full'

        WHEN COUNT(DISTINCT sa.person_id) >= CEIL(s.capacity * 0.80)
            THEN 'Near Capacity'

        ELSE 'Available'
    END AS occupancy_status

FROM public.shelters AS s

INNER JOIN public.organizations AS o
    ON s.organization_id = o.id

LEFT JOIN public.shelter_assignments AS sa
    ON s.id = sa.shelter_id
    AND sa.checked_out_at IS NULL

GROUP BY
    o.id,
    o.name,
    s.id,
    s.name,
    s.status,
    s.capacity

ORDER BY
    occupancy_percentage DESC NULLS LAST,
    s.name;


-- ============================================================
-- QUERY 07: Incident Response Overview
-- Purpose: Provide a complete operational summary for each
--          incident.
-- Concepts: Correlated Subqueries, COUNT, DISTINCT, IN, JOIN
-- ============================================================

SELECT
    o.name AS organization_name,
    i.incident_code,
    i.title AS incident_title,
    i.status AS incident_status,
    i.priority,

    -- Total missions linked to the incident
    (
        SELECT COUNT(*)
        FROM public.missions AS m
        WHERE m.incident_id = i.id
    ) AS total_missions,

    -- Number of distinct teams assigned to those missions
    (
        SELECT COUNT(DISTINCT ma.team_id)
        FROM public.missions AS m

        INNER JOIN public.mission_assignments AS ma
            ON m.id = ma.mission_id

        WHERE m.incident_id = i.id
          AND ma.team_id IS NOT NULL
    ) AS participating_teams,

    -- Total affected persons registered for the incident
    (
        SELECT COUNT(*)
        FROM public.affected_persons AS ap
        WHERE ap.incident_id = i.id
    ) AS total_affected_persons,

    -- Total resource requests
    (
        SELECT COUNT(*)
        FROM public.resource_requests AS rr
        WHERE rr.incident_id = i.id
    ) AS total_resource_requests,

    -- Requests currently submitted, approved, or partially fulfilled
    (
        SELECT COUNT(*)
        FROM public.resource_requests AS rr
        WHERE rr.incident_id = i.id
          AND rr.status IN (
              'submitted',
              'approved',
              'partially_fulfilled'
          )
    ) AS open_resource_requests

FROM public.incidents AS i

INNER JOIN public.organizations AS o
    ON i.organization_id = o.id

ORDER BY
    CASE i.priority
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        WHEN 'low' THEN 4
        ELSE 5
    END,
    i.reported_at DESC;


-- ============================================================
-- THE END
-- ============================================================
