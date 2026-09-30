-- ============================================================
-- E-Ambulance Supabase Schema
-- Run this in: Supabase Console → SQL Editor → New Query
-- ============================================================

-- ── drivers table ────────────────────────────────────────────
create table if not exists public.drivers (
  id                 uuid primary key default gen_random_uuid(),
  firebase_uid       text unique not null,
  name               text not null,
  phone              text not null default '',
  vehicle_type       text not null default 'Basic',
  vehicle_number     text not null default '',
  is_online          boolean not null default false,
  is_approved        boolean not null default false,
  current_lat        double precision,
  current_lng        double precision,
  current_request_id uuid,
  updated_at         timestamptz not null default now()
);

-- ── requests table ───────────────────────────────────────────
create table if not exists public.requests (
  id                   uuid primary key default gen_random_uuid(),
  user_firebase_uid    text not null,
  driver_id            uuid references public.drivers(id),
  status               text not null default 'pending'
                         check (status in ('pending','accepted','en_route','arrived','completed','cancelled')),
  ambulance_type       text not null,
  pickup_lat           double precision not null,
  pickup_lng           double precision not null,
  pickup_address       text not null,
  destination_lat      double precision not null,
  destination_lng      double precision not null,
  destination_address  text not null,
  estimated_fare       integer not null,
  distance_km          double precision not null,
  user_name            text not null,
  user_phone           text not null,
  created_at           timestamptz not null default now(),
  accepted_at          timestamptz,
  completed_at         timestamptz
);

-- ── indexes ──────────────────────────────────────────────────
create index if not exists idx_requests_status
  on public.requests(status);

create index if not exists idx_requests_user
  on public.requests(user_firebase_uid, created_at desc);

create index if not exists idx_requests_driver
  on public.requests(driver_id, status);

-- ── Enable Realtime ──────────────────────────────────────────
-- Run these manually in the Supabase Dashboard:
--   Database → Replication → Tables → enable for "requests" and "drivers"
-- Or via SQL:
alter publication supabase_realtime add table public.requests;
alter publication supabase_realtime add table public.drivers;

-- ── Row Level Security (RLS) ─────────────────────────────────
-- Note: Since we use Firebase Auth (not Supabase Auth), we use
-- the anon key with service-level trust. Enable RLS only if you
-- add JWT verification via Supabase Edge Functions in future.

-- For now, allow all operations via anon key (safe behind Firebase Auth):
alter table public.drivers  enable row level security;
alter table public.requests enable row level security;

create policy "Allow all via anon key" on public.drivers
  for all using (true) with check (true);

create policy "Allow all via anon key" on public.requests
  for all using (true) with check (true);
