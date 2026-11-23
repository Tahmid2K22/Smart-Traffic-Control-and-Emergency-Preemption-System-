-- ============================================================
-- E-Ambulance: user profiles in Supabase
-- Firebase Auth keeps handling authentication; this table is the
-- single source of truth for user/profile data (role, approval,
-- contact details, officer assignment, FCM tokens).
--
-- Run in: Supabase Console -> SQL Editor -> New Query
-- ============================================================

create table if not exists public.users (
  id                      uuid primary key default gen_random_uuid(),
  firebase_uid            text unique not null,
  name                    text not null default '',
  full_name               text not null default '',
  email                   text not null default '',
  phone                   text not null default '',
  city                    text,
  address                 text,
  role                    text not null default 'user'
                            check (role in ('user','patient','driver','traffic_police','admin','hospital')),
  is_approved             boolean not null default false,
  is_verified             boolean not null default false,
  verification_status     text not null default 'NONE',
  is_active               boolean not null default false,
  police_id               text,
  assigned_intersection   text,
  assigned_intersection_id text,
  intersection_lat        double precision,
  intersection_lng        double precision,
  driving_license         text,
  vehicle_type            text,
  vehicle_number          text,
  license_image_path      text,
  fcm_tokens              jsonb not null default '{}'::jsonb,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create index if not exists idx_users_role        on public.users (role);
create index if not exists idx_users_approval    on public.users (role, is_approved);
create index if not exists idx_users_phone       on public.users (phone);

-- Keep updated_at fresh on every write.
create or replace function public.touch_users_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_users_updated_at on public.users;
create trigger trg_users_updated_at
  before update on public.users
  for each row execute function public.touch_users_updated_at();

-- Row Level Security: the app authenticates with Firebase Auth, so Supabase
-- only sees the anon key. Allow the app to read/write profiles.
alter table public.users enable row level security;

drop policy if exists "Allow all via anon key" on public.users;
create policy "Allow all via anon key" on public.users
  for all using (true) with check (true);

-- Realtime: role / approval changes must reach the app live (AuthGate).
alter publication supabase_realtime add table public.users;
