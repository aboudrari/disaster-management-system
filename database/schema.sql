
begin;

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- 1. ORGANIZATIONS, USERS & ROLES
-- -----------------------------------------------------------------------------

create table public.organizations (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    slug text not null unique,
    organization_type text not null default 'emergency_service'
        check (organization_type in ('government','ngo','emergency_service','hospital','other')),
    email text,
    phone text,
    address text,
    country text,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- One profile per Supabase Auth user. Never store password hashes here.
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text not null,
    phone text,
    avatar_url text,
    is_active boolean not null default true,
    last_seen_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.roles (
    id smallint generated always as identity primary key,
    code text not null unique,
    name text not null,
    description text
);

insert into public.roles (code, name, description) values
 ('ADMIN','Administrator','Manages organization accounts, users, and system settings.'),
 ('COMMANDER','Incident Commander','Coordinates incidents, teams, missions, and operational decisions.'),
 ('RESPONDER','Field Responder','Receives assignments and submits field progress and reports.'),
 ('ANALYST','Analyst / Viewer','Reads operational information and prepares analysis and reports.')
on conflict (code) do nothing;

-- A user can belong to multiple organizations and hold a different role in each.
create table public.organization_members (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    user_id uuid not null references public.profiles(id) on delete cascade,
    role_id smallint not null references public.roles(id) on delete restrict,
    membership_status text not null default 'active'
        check (membership_status in ('invited','active','suspended','removed')),
    joined_at timestamptz,
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, user_id)
);

-- -----------------------------------------------------------------------------
-- 2. RESPONSE TEAMS
-- -----------------------------------------------------------------------------

create table public.teams (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    name text not null,
    team_code text,
    team_type text not null default 'general'
        check (team_type in ('medical','search_and_rescue','fire','logistics','security','engineering','general','other')),
    status text not null default 'available'
        check (status in ('available','deployed','unavailable','inactive')),
    base_location text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    contact_phone text,
    notes text,
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, team_code)
);

create table public.team_members (
    id uuid primary key default gen_random_uuid(),
    team_id uuid not null references public.teams(id) on delete cascade,
    organization_member_id uuid not null references public.organization_members(id) on delete restrict,
    team_position text,
    is_team_lead boolean not null default false,
    joined_at timestamptz not null default now(),
    left_at timestamptz,
    created_at timestamptz not null default now(),
    check (left_at is null or left_at >= joined_at),
    unique (team_id, organization_member_id, joined_at)
);

-- -----------------------------------------------------------------------------
-- 3. INCIDENTS / DISASTERS & INCIDENT INTELLIGENCE
-- -----------------------------------------------------------------------------

create table public.incidents (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_code text not null,
    title text not null,
    disaster_type text not null
        check (disaster_type in ('earthquake','flood','wildfire','storm','landslide','industrial','epidemic','other')),
    severity smallint not null check (severity between 1 and 5),
    priority text not null default 'medium'
        check (priority in ('low','medium','high','critical')),
    status text not null default 'reported'
        check (status in ('reported','verified','active','contained','resolved','closed','cancelled')),
    location_name text not null,
    address text,
    country text,
    region text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    description text,
    estimated_affected integer check (estimated_affected is null or estimated_affected >= 0),
    reported_by uuid references public.profiles(id) on delete set null,
    commander_membership_id uuid references public.organization_members(id) on delete set null,
    occurred_at timestamptz,
    reported_at timestamptz not null default now(),
    resolved_at timestamptz,
    closed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, incident_code),
    check (resolved_at is null or resolved_at >= reported_at),
    check (closed_at is null or resolved_at is null or closed_at >= resolved_at)
);

create table public.incident_status_history (
    id uuid primary key default gen_random_uuid(),
    incident_id uuid not null references public.incidents(id) on delete cascade,
    previous_status text,
    new_status text not null,
    changed_by uuid references public.profiles(id) on delete set null,
    reason text,
    changed_at timestamptz not null default now()
);

create table public.incident_updates (
    id uuid primary key default gen_random_uuid(),
    incident_id uuid not null references public.incidents(id) on delete cascade,
    update_type text not null default 'general'
        check (update_type in ('general','situation','casualty','weather','road_access','safety','decision','other')),
    title text,
    body text not null,
    visibility text not null default 'organization'
        check (visibility in ('organization','response_teams','command_only')),
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

create table public.incident_media (
    id uuid primary key default gen_random_uuid(),
    incident_id uuid not null references public.incidents(id) on delete cascade,
    storage_path text not null,
    file_name text,
    media_type text not null check (media_type in ('image','video','audio','document','other')),
    caption text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    uploaded_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 4. MISSIONS, TEAM DEPLOYMENT & FIELD REPORTING
-- -----------------------------------------------------------------------------

create table public.missions (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid not null references public.incidents(id) on delete restrict,
    mission_code text not null,
    title text not null,
    description text,
    mission_type text not null default 'general'
        check (mission_type in ('rescue','medical','evacuation','fire_suppression','assessment','supply_delivery','security','repair','general','other')),
    priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
    status text not null default 'draft'
        check (status in ('draft','assigned','accepted','in_progress','on_hold','completed','cancelled')),
    target_location text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    scheduled_start timestamptz,
    scheduled_end timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, mission_code),
    check (scheduled_end is null or scheduled_start is null or scheduled_end >= scheduled_start),
    check (completed_at is null or started_at is null or completed_at >= started_at)
);

create table public.mission_assignments (
    id uuid primary key default gen_random_uuid(),
    mission_id uuid not null references public.missions(id) on delete cascade,
    team_id uuid references public.teams(id) on delete restrict,
    organization_member_id uuid references public.organization_members(id) on delete restrict,
    assigned_by uuid references public.profiles(id) on delete set null,
    assignment_status text not null default 'assigned'
        check (assignment_status in ('assigned','accepted','declined','in_progress','completed','cancelled')),
    assigned_at timestamptz not null default now(),
    responded_at timestamptz,
    completed_at timestamptz,
    notes text,
    check (num_nonnulls(team_id, organization_member_id) = 1),
    check (completed_at is null or completed_at >= assigned_at)
);

create table public.mission_updates (
    id uuid primary key default gen_random_uuid(),
    mission_id uuid not null references public.missions(id) on delete cascade,
    status text not null check (status in ('assigned','accepted','in_progress','on_hold','completed','cancelled')),
    progress_percent smallint check (progress_percent between 0 and 100),
    message text,
    location_text text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    submitted_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

create table public.field_reports (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid not null references public.incidents(id) on delete restrict,
    mission_id uuid references public.missions(id) on delete set null,
    submitted_by uuid references public.profiles(id) on delete set null,
    report_type text not null default 'situation'
        check (report_type in ('situation','casualty','damage_assessment','resource_need','safety','completion','other')),
    title text not null,
    details text not null,
    people_affected integer check (people_affected is null or people_affected >= 0),
    report_latitude numeric(9,6) check (report_latitude between -90 and 90),
    report_longitude numeric(9,6) check (report_longitude between -180 and 180),
    review_status text not null default 'submitted'
        check (review_status in ('submitted','reviewed','needs_followup','rejected')),
    reviewed_by uuid references public.profiles(id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 5. SHELTERS & AFFECTED PEOPLE
-- -----------------------------------------------------------------------------

create table public.shelters (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid references public.incidents(id) on delete set null,
    name text not null,
    address text not null,
    country text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    capacity integer not null check (capacity >= 0),
    contact_name text,
    contact_phone text,
    status text not null default 'open' check (status in ('open','full','closed','maintenance')),
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.affected_persons (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid not null references public.incidents(id) on delete restrict,
    full_name text not null,
    age smallint check (age between 0 and 125),
    phone text,
    triage_status text not null default 'unassessed'
        check (triage_status in ('unassessed','green','yellow','red','black')),
    person_status text not null default 'registered'
        check (person_status in ('registered','missing','located','sheltered','released','deceased')),
    special_needs text,
    emergency_contact text,
    registered_by uuid references public.profiles(id) on delete set null,
    registered_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.shelter_assignments (
    id uuid primary key default gen_random_uuid(),
    person_id uuid not null references public.affected_persons(id) on delete restrict,
    shelter_id uuid not null references public.shelters(id) on delete restrict,
    assigned_by uuid references public.profiles(id) on delete set null,
    checked_in_at timestamptz not null default now(),
    checked_out_at timestamptz,
    notes text,
    created_at timestamptz not null default now(),
    check (checked_out_at is null or checked_out_at >= checked_in_at)
);

create unique index shelter_assignments_one_active_per_person
    on public.shelter_assignments(person_id) where checked_out_at is null;

-- -----------------------------------------------------------------------------
-- 6. RESOURCE CATALOGUE, LOCATIONS, INVENTORY & DISPATCH
-- -----------------------------------------------------------------------------

create table public.resource_categories (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    description text,
    created_at timestamptz not null default now()
);

create table public.resource_items (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    category_id uuid references public.resource_categories(id) on delete set null,
    item_name text not null,
    item_code text,
    unit text not null,
    minimum_stock_level numeric(14,3) not null default 0 check (minimum_stock_level >= 0),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, item_code)
);

create table public.resource_locations (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    name text not null,
    location_type text not null default 'warehouse'
        check (location_type in ('warehouse','shelter','field_depot','vehicle','other')),
    address text,
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    unique (organization_id, name)
);

-- Current stock by item and location. Maintain through inventory transactions.
create table public.inventory_balances (
    id uuid primary key default gen_random_uuid(),
    resource_item_id uuid not null references public.resource_items(id) on delete restrict,
    resource_location_id uuid not null references public.resource_locations(id) on delete restrict,
    quantity_on_hand numeric(14,3) not null default 0 check (quantity_on_hand >= 0),
    updated_at timestamptz not null default now(),
    unique (resource_item_id, resource_location_id)
);

create table public.inventory_transactions (
    id uuid primary key default gen_random_uuid(),
    resource_item_id uuid not null references public.resource_items(id) on delete restrict,
    resource_location_id uuid not null references public.resource_locations(id) on delete restrict,
    transaction_type text not null
        check (transaction_type in ('receipt','dispatch','transfer_in','transfer_out','adjustment','return')),
    quantity numeric(14,3) not null check (quantity > 0),
    reference_type text,
    reference_id uuid,
    notes text,
    performed_by uuid references public.profiles(id) on delete set null,
    occurred_at timestamptz not null default now(),
    created_at timestamptz not null default now()
);

create table public.resource_requests (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid references public.incidents(id) on delete set null,
    requested_by uuid references public.profiles(id) on delete set null,
    request_code text not null,
    priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
    status text not null default 'submitted'
        check (status in ('draft','submitted','approved','partially_fulfilled','fulfilled','rejected','cancelled')),
    needed_by timestamptz,
    notes text,
    reviewed_by uuid references public.profiles(id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, request_code)
);

create table public.resource_request_items (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.resource_requests(id) on delete cascade,
    resource_item_id uuid not null references public.resource_items(id) on delete restrict,
    quantity_requested numeric(14,3) not null check (quantity_requested > 0),
    quantity_approved numeric(14,3) not null default 0 check (quantity_approved >= 0),
    quantity_fulfilled numeric(14,3) not null default 0 check (quantity_fulfilled >= 0),
    notes text,
    unique (request_id, resource_item_id),
    check (quantity_approved <= quantity_requested),
    check (quantity_fulfilled <= quantity_approved)
);

create table public.dispatches (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid references public.incidents(id) on delete set null,
    request_id uuid references public.resource_requests(id) on delete set null,
    source_location_id uuid not null references public.resource_locations(id) on delete restrict,
    destination_shelter_id uuid references public.shelters(id) on delete set null,
    destination_location text,
    dispatch_code text not null,
    status text not null default 'prepared'
        check (status in ('prepared','approved','in_transit','delivered','partially_delivered','cancelled')),
    dispatched_by uuid references public.profiles(id) on delete set null,
    approved_by uuid references public.profiles(id) on delete set null,
    dispatched_at timestamptz,
    delivered_at timestamptz,
    delivery_notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, dispatch_code),
    check (delivered_at is null or dispatched_at is null or delivered_at >= dispatched_at)
);

create table public.dispatch_items (
    id uuid primary key default gen_random_uuid(),
    dispatch_id uuid not null references public.dispatches(id) on delete cascade,
    resource_item_id uuid not null references public.resource_items(id) on delete restrict,
    quantity_sent numeric(14,3) not null check (quantity_sent > 0),
    quantity_delivered numeric(14,3) check (quantity_delivered is null or (quantity_delivered >= 0 and quantity_delivered <= quantity_sent)),
    notes text,
    unique (dispatch_id, resource_item_id)
);

-- -----------------------------------------------------------------------------
-- 7. ALERTS, RECIPIENTS & IN-APP NOTIFICATIONS
-- -----------------------------------------------------------------------------

create table public.alerts (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete restrict,
    incident_id uuid references public.incidents(id) on delete set null,
    issued_by uuid references public.profiles(id) on delete set null,
    title text not null,
    message text not null,
    severity text not null default 'information'
        check (severity in ('information','warning','critical')),
    target_scope text not null default 'organization'
        check (target_scope in ('organization','commanders','responders','analysts','incident_teams')),
    status text not null default 'published' check (status in ('draft','published','expired','cancelled')),
    issued_at timestamptz not null default now(),
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    check (expires_at is null or expires_at > issued_at)
);

create table public.alert_recipients (
    id uuid primary key default gen_random_uuid(),
    alert_id uuid not null references public.alerts(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    delivered_at timestamptz,
    read_at timestamptz,
    unique (alert_id, user_id)
);

create table public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    organization_id uuid references public.organizations(id) on delete cascade,
    notification_type text not null,
    title text not null,
    message text not null,
    related_entity_type text,
    related_entity_id uuid,
    read_at timestamptz,
    created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 8. AUDIT TRAIL
-- -----------------------------------------------------------------------------

create table public.audit_logs (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid references public.organizations(id) on delete set null,
    actor_user_id uuid references public.profiles(id) on delete set null,
    action text not null,
    entity_table text not null,
    entity_id uuid,
    old_values jsonb,
    new_values jsonb,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 9. UPDATED_AT TRIGGER & INDEXES
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'organizations','profiles','organization_members','teams','incidents','missions',
        'shelters','affected_persons','resource_items','inventory_balances',
        'resource_requests','dispatches'
    ] loop
        execute format('drop trigger if exists set_updated_at on public.%I', table_name);
        execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name);
    end loop;
end;
$$;

create index idx_org_members_user on public.organization_members(user_id);
create index idx_org_members_org_role on public.organization_members(organization_id, role_id);
create index idx_teams_org_status on public.teams(organization_id, status);
create index idx_team_members_member on public.team_members(organization_member_id);
create index idx_incidents_org_status on public.incidents(organization_id, status);
create index idx_incidents_org_reported on public.incidents(organization_id, reported_at desc);
create index idx_incidents_location on public.incidents(latitude, longitude);
create index idx_incident_updates_incident_date on public.incident_updates(incident_id, created_at desc);
create index idx_missions_incident_status on public.missions(incident_id, status);
create index idx_missions_org_status on public.missions(organization_id, status);
create index idx_mission_assignments_mission on public.mission_assignments(mission_id);
create index idx_mission_assignments_team on public.mission_assignments(team_id) where team_id is not null;
create index idx_mission_assignments_member on public.mission_assignments(organization_member_id) where organization_member_id is not null;
create index idx_mission_updates_mission_date on public.mission_updates(mission_id, created_at desc);
create index idx_field_reports_incident_date on public.field_reports(incident_id, created_at desc);
create index idx_shelters_org_status on public.shelters(organization_id, status);
create index idx_affected_persons_incident on public.affected_persons(incident_id);
create index idx_shelter_assignments_shelter_active on public.shelter_assignments(shelter_id) where checked_out_at is null;
create index idx_inventory_balance_location on public.inventory_balances(resource_location_id);
create index idx_inventory_transactions_item_date on public.inventory_transactions(resource_item_id, occurred_at desc);
create index idx_resource_requests_org_status on public.resource_requests(organization_id, status);
create index idx_dispatches_incident_status on public.dispatches(incident_id, status);
create index idx_alerts_org_issued on public.alerts(organization_id, issued_at desc);
create index idx_notifications_user_unread on public.notifications(user_id, created_at desc) where read_at is null;
create index idx_audit_logs_org_date on public.audit_logs(organization_id, occurred_at desc);

commit;

-- IMPORTANT IMPLEMENTATION NOTES
-- 1. This migration creates the relational schema, not the complete security model.
-- 2. Enable RLS on every exposed table and add role + organization-scoped policies
--    before connecting the production frontend.
-- 3. Create Auth users through a trusted server/Edge Function using the service-role
--    key. Never expose that key in React or store passwords in public.profiles.
-- 4. Update inventory_balances and inventory_transactions atomically in a trusted
--    database function/transaction; do not let clients directly edit stock totals.
-- 5. Enforce shelter capacity atomically when creating active shelter assignments.
-- 6. Store uploaded files in private Supabase Storage buckets; save object paths here.
