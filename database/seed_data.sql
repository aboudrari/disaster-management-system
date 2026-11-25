-- SENTINEL - Sample Seed Data

-- PREREQUISITES:
-- 1. Run database/schema.sql.
-- 2. Create the four demo users in Supabase Authentication:
--      sentinel.admin@example.com
--      sentinel.commander@example.com
--      sentinel.responder@example.com
--      sentinel.analyst@example.com
-- 3. Ensure the matching records already exist in:
--      public.organizations
--      public.profiles
--      public.organization_members
--    This file intentionally does not recreate those base records.
--
-- IMPORTANT:
-- - Run this file only once on a clean operational-data database.
-- - This seed file is not idempotent; do not run it again on populated tables.
-- - The sample dispatch is in_transit, so dispatched quantities are deducted
--   from the source warehouse and recorded in inventory_transactions.
-- - incident_media.storage_path is a demonstration path only. The actual
--   image must be uploaded separately to Supabase Storage.
-- - The audit_logs row below is sample data, not an automatically generated
--   audit event. Automatic auditing will be implemented separately.
--


BEGIN;

-- Base organization, profiles, roles and organization memberships are
-- prerequisites and are intentionally managed separately.

-- 1. TEAMS
-- ---------------------------------------------------------

INSERT INTO public.teams
(id, organization_id, name, team_code, team_type, status, base_location)
VALUES
('30000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 'North Rescue Team', 'TEAM-RES-01',
 'search_and_rescue', 'available', 'Nicosia'),

('30000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000001',
 'Emergency Medical Team', 'TEAM-MED-01',
 'medical', 'available', 'Nicosia');


-- ---------------------------------------------------------
-- 2. TEAM MEMBERS
-- ---------------------------------------------------------

INSERT INTO public.team_members
(id, team_id, organization_member_id, team_position, is_team_lead)
VALUES
('31000000-0000-0000-0000-000000000001',
 '30000000-0000-0000-0000-000000000001',
 '20000000-0000-0000-0000-000000000003',
 'Rescue Responder', false),

('31000000-0000-0000-0000-000000000002',
 '30000000-0000-0000-0000-000000000002',
 '20000000-0000-0000-0000-000000000004',
 'Team Coordinator', true);


-- ---------------------------------------------------------
-- 3. INCIDENTS
-- ---------------------------------------------------------

INSERT INTO public.incidents
(id, organization_id, incident_code, title, disaster_type, severity,
 priority, status, location_name, country, region, description,
 estimated_affected, reported_by, commander_membership_id, occurred_at)
VALUES
('40000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 'INC-2026-001', 'Central District Earthquake',
 'earthquake', 4, 'critical', 'active',
 'Central District', 'Cyprus', 'Nicosia',
 'An earthquake was reported in the central district.',
 120,
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'),
 '20000000-0000-0000-0000-000000000002',
 now()),

('40000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000001',
 'INC-2026-002', 'Riverside Flood Warning',
 'flood', 3, 'high', 'verified',
 'Riverside Area', 'Cyprus', 'Nicosia',
 'A flood warning was reported near the riverside.',
 45,
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 '20000000-0000-0000-0000-000000000002',
 now());


-- ---------------------------------------------------------
-- 4. INCIDENT STATUS HISTORY
-- ---------------------------------------------------------

INSERT INTO public.incident_status_history
(id, incident_id, previous_status, new_status, changed_by, reason)
VALUES
('41000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 NULL, 'reported',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'),
 'The incident was reported.'),

('41000000-0000-0000-0000-000000000002',
 '40000000-0000-0000-0000-000000000001',
 'reported', 'active',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'Response teams were activated.'),

('41000000-0000-0000-0000-000000000003',
 '40000000-0000-0000-0000-000000000002',
 NULL, 'reported',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'The flood incident was reported.'),

('41000000-0000-0000-0000-000000000004',
 '40000000-0000-0000-0000-000000000002',
 'reported', 'verified',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'The flood report was verified.');


-- ---------------------------------------------------------
-- 5. INCIDENT UPDATES
-- ---------------------------------------------------------

INSERT INTO public.incident_updates
(id, incident_id, update_type, title, body, visibility, created_by)
VALUES
('42000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'situation', 'First Situation Update',
 'Rescue teams are checking the affected buildings.',
 'organization',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'));


-- ---------------------------------------------------------
-- 6. INCIDENT MEDIA
-- This is an example storage path, not an uploaded image.
-- ---------------------------------------------------------

INSERT INTO public.incident_media
(id, incident_id, storage_path, file_name, media_type, caption, uploaded_by)
VALUES
('43000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'incident-media/demo/earthquake.jpg',
 'earthquake.jpg', 'image',
 'Example incident image path.',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'));


-- ---------------------------------------------------------
-- 7. MISSIONS
-- ---------------------------------------------------------

INSERT INTO public.missions
(id, organization_id, incident_id, mission_code, title, description,
 mission_type, priority, status, target_location, created_by)
VALUES
('50000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'MIS-2026-001', 'Search Building A',
 'Search the building and report people who need help.',
 'rescue', 'critical', 'assigned', 'Central District',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander')),

('50000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'MIS-2026-002', 'First Aid Support',
 'Provide first aid to affected people.',
 'medical', 'high', 'assigned', 'Central District',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'));


-- ---------------------------------------------------------
-- 8. MISSION ASSIGNMENTS
-- ---------------------------------------------------------

INSERT INTO public.mission_assignments
(id, mission_id, team_id, assigned_by, assignment_status, notes)
VALUES
('51000000-0000-0000-0000-000000000001',
 '50000000-0000-0000-0000-000000000001',
 '30000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'assigned', 'The rescue team is assigned to Building A.'),

('51000000-0000-0000-0000-000000000002',
 '50000000-0000-0000-0000-000000000002',
 '30000000-0000-0000-0000-000000000002',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'assigned', 'The medical team will provide first aid.');


-- ---------------------------------------------------------
-- 9. MISSION UPDATES
-- ---------------------------------------------------------

INSERT INTO public.mission_updates
(id, mission_id, status, progress_percent, message, submitted_by)
VALUES
('52000000-0000-0000-0000-000000000001',
 '50000000-0000-0000-0000-000000000001',
 'in_progress', 40,
 'The first part of the building search is complete.',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'));


-- ---------------------------------------------------------
-- 10. FIELD REPORTS
-- ---------------------------------------------------------

INSERT INTO public.field_reports
(id, organization_id, incident_id, mission_id, submitted_by,
 report_type, title, details, people_affected, review_status)
VALUES
('53000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 '50000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'),
 'situation', 'Initial Field Report',
 'The team checked the first area and reported people needing assistance.',
 12, 'submitted');


-- ---------------------------------------------------------
-- 11. SHELTERS
-- ---------------------------------------------------------

INSERT INTO public.shelters
(id, organization_id, incident_id, name, address, country,
 capacity, contact_name, contact_phone, status)
VALUES
('60000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'Community Emergency Shelter',
 'Community Centre, Nicosia', 'Cyprus',
 150, 'Shelter Coordinator', '+90 555 300 0001', 'open');


-- ---------------------------------------------------------
-- 12. AFFECTED PEOPLE
-- ---------------------------------------------------------

INSERT INTO public.affected_persons
(id, organization_id, incident_id, full_name, age, phone,
 triage_status, person_status, registered_by)
VALUES
('61000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'Jamie Wilson', 34, '+90 555 400 0001',
 'yellow', 'registered',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder')),

('61000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 'Taylor Smith', 67, '+90 555 400 0002',
 'green', 'sheltered',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'));


-- ---------------------------------------------------------
-- 13. SHELTER ASSIGNMENTS
-- ---------------------------------------------------------

INSERT INTO public.shelter_assignments
(id, person_id, shelter_id, assigned_by, notes)
VALUES
('62000000-0000-0000-0000-000000000001',
 '61000000-0000-0000-0000-000000000002',
 '60000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'The person checked in to the emergency shelter.');


-- ---------------------------------------------------------
-- 14. RESOURCE CATEGORIES
-- ---------------------------------------------------------

INSERT INTO public.resource_categories (id, name, description)
VALUES
('70000000-0000-0000-0000-000000000001',
 'Food and Water', 'Food and drinking water supplies.'),
('70000000-0000-0000-0000-000000000002',
 'Medical Supplies', 'First aid and medical equipment.');


-- ---------------------------------------------------------
-- 15. RESOURCE ITEMS
-- ---------------------------------------------------------

INSERT INTO public.resource_items
(id, organization_id, category_id, item_name, item_code, unit, minimum_stock_level)
VALUES
('71000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '70000000-0000-0000-0000-000000000001',
 'Bottled Water', 'RES-WAT-001', 'bottles', 50),

('71000000-0000-0000-0000-000000000002',
 '10000000-0000-0000-0000-000000000001',
 '70000000-0000-0000-0000-000000000002',
 'First Aid Kit', 'RES-MED-001', 'kits', 10);


-- ---------------------------------------------------------
-- 16. RESOURCE LOCATIONS
-- ---------------------------------------------------------

INSERT INTO public.resource_locations
(id, organization_id, name, location_type, address)
VALUES
('72000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 'Central Emergency Warehouse', 'warehouse', 'Nicosia');


-- ---------------------------------------------------------
-- 17. INVENTORY BALANCES
-- ---------------------------------------------------------

INSERT INTO public.inventory_balances
(id, resource_item_id, resource_location_id, quantity_on_hand)
VALUES
('73000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000001',
 '72000000-0000-0000-0000-000000000001', 230),

('73000000-0000-0000-0000-000000000002',
 '71000000-0000-0000-0000-000000000002',
 '72000000-0000-0000-0000-000000000001', 23);


-- ---------------------------------------------------------
-- 18. INVENTORY TRANSACTIONS
-- ---------------------------------------------------------

INSERT INTO public.inventory_transactions
(id, resource_item_id, resource_location_id, transaction_type,
 quantity, reference_type, notes, performed_by)
VALUES
('74000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000001',
 '72000000-0000-0000-0000-000000000001',
 'receipt', 250, 'opening_stock', 'Initial water stock.',
 (SELECT id FROM public.profiles WHERE full_name = 'Alex Morgan - Administrator')),

('74000000-0000-0000-0000-000000000002',
 '71000000-0000-0000-0000-000000000002',
 '72000000-0000-0000-0000-000000000001',
 'receipt', 28, 'opening_stock', 'Initial first aid kit stock.',
 (SELECT id FROM public.profiles WHERE full_name = 'Alex Morgan - Administrator'));


-- ---------------------------------------------------------
-- 19. RESOURCE REQUESTS
-- ---------------------------------------------------------

INSERT INTO public.resource_requests
(id, organization_id, incident_id, requested_by, request_code,
 priority, status, notes, reviewed_by, reviewed_at)
VALUES
('75000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'REQ-2026-001', 'high', 'approved',
 'Request for water and first aid kits.',
 (SELECT id FROM public.profiles WHERE full_name = 'Alex Morgan - Administrator'),
 now());


-- ---------------------------------------------------------
-- 20. RESOURCE REQUEST ITEMS
-- ---------------------------------------------------------

INSERT INTO public.resource_request_items
(id, request_id, resource_item_id, quantity_requested,
 quantity_approved, quantity_fulfilled)
VALUES
('76000000-0000-0000-0000-000000000001',
 '75000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000001', 20, 20, 0),

('76000000-0000-0000-0000-000000000002',
 '75000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000002', 5, 5, 0);


-- ---------------------------------------------------------
-- 21. DISPATCHES
-- ---------------------------------------------------------

INSERT INTO public.dispatches
(id, organization_id, incident_id, request_id, source_location_id,
 destination_shelter_id, destination_location, dispatch_code,
 status, dispatched_by, approved_by, dispatched_at)
VALUES
('77000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 '75000000-0000-0000-0000-000000000001',
 '72000000-0000-0000-0000-000000000001',
 '60000000-0000-0000-0000-000000000001',
 'Community Emergency Shelter',
 'DSP-2026-001', 'in_transit',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 (SELECT id FROM public.profiles WHERE full_name = 'Alex Morgan - Administrator'),
 now());


-- ---------------------------------------------------------
-- 22. DISPATCH ITEMS
-- ---------------------------------------------------------

INSERT INTO public.dispatch_items
(id, dispatch_id, resource_item_id, quantity_sent)
VALUES
('78000000-0000-0000-0000-000000000001',
 '77000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000001', 20),

('78000000-0000-0000-0000-000000000002',
 '77000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000002', 5);


-- ---------------------------------------------------------
-- INVENTORY DISPATCH TRANSACTIONS
-- These ledger entries record quantities removed from the
-- source warehouse by DSP-2026-001.
-- ---------------------------------------------------------

INSERT INTO public.inventory_transactions
(id, resource_item_id, resource_location_id, transaction_type,
 quantity, reference_type, reference_id, notes, performed_by)
VALUES
('74000000-0000-0000-0000-000000000003',
 '71000000-0000-0000-0000-000000000001',
 '72000000-0000-0000-0000-000000000001',
 'dispatch', 20, 'dispatch',
 '77000000-0000-0000-0000-000000000001',
 '20 Bottled Water dispatched through DSP-2026-001.',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander')),

('74000000-0000-0000-0000-000000000004',
 '71000000-0000-0000-0000-000000000002',
 '72000000-0000-0000-0000-000000000001',
 'dispatch', 5, 'dispatch',
 '77000000-0000-0000-0000-000000000001',
 '5 First Aid Kits dispatched through DSP-2026-001.',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'));


-- ---------------------------------------------------------
-- 23. ALERTS
-- ---------------------------------------------------------

INSERT INTO public.alerts
(id, organization_id, incident_id, issued_by, title, message,
 severity, target_scope, status, expires_at)
VALUES
('80000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 '40000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Jordan Lee - Incident Commander'),
 'Earthquake Response Active',
 'A response operation is active in the Central District. Follow official instructions.',
 'critical', 'organization', 'published', now() + interval '1 day');


-- ---------------------------------------------------------
-- 24. ALERT RECIPIENTS
-- ---------------------------------------------------------


INSERT INTO public.alert_recipients (id, alert_id, user_id)
VALUES
('81000000-0000-0000-0000-000000000001',
 '80000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Alex Morgan - Administrator')),

('81000000-0000-0000-0000-000000000002',
 '80000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'));


-- ---------------------------------------------------------
-- 25. NOTIFICATIONS
-- ---------------------------------------------------------

INSERT INTO public.notifications
(id, user_id, organization_id, notification_type, title, message,
 related_entity_type, related_entity_id)
VALUES
('82000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Sam Taylor - Field Responder'),
 '10000000-0000-0000-0000-000000000001',
 'mission_assigned', 'New Mission Assigned',
 'You have been assigned to Search Building A.',
 'mission', '50000000-0000-0000-0000-000000000001');


-- ---------------------------------------------------------
-- 26. AUDIT LOGS
-- ---------------------------------------------------------

INSERT INTO public.audit_logs
(id, organization_id, actor_user_id, action, entity_table, entity_id, new_values)
VALUES
('83000000-0000-0000-0000-000000000001',
 '10000000-0000-0000-0000-000000000001',
 (SELECT id FROM public.profiles WHERE full_name = 'Alex Morgan - Administrator'),
 'INSERT', 'organizations',
 '10000000-0000-0000-0000-000000000001',
 '{"name":"Sentinel Emergency Response"}'::jsonb);


COMMIT;
