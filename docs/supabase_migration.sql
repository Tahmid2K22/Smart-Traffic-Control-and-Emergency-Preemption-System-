-- ============================================================
-- E-Ambulance: Driver ↔ User Chat System Migration
-- Run this in your Supabase SQL Editor (Dashboard → SQL Editor)
-- ============================================================

-- 1. Create the messages table
create table if not exists messages (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null references requests(id) on delete cascade,
  sender_role   text not null check (sender_role in ('user', 'driver')),
  sender_name   text not null,
  body          text not null,
  created_at    timestamptz not null default now()
);

-- 2. Index for fast per-request chat queries (sorted chronologically)
create index if not exists messages_request_created_idx
  on messages (request_id, created_at asc);

-- 3. Track when the last message was sent on a request (for unread badges)
alter table requests
  add column if not exists last_message_at timestamptz;

-- 4. Enable Supabase Realtime on the messages table
--    (If you get "already a member" error you can safely ignore it)
alter publication supabase_realtime add table messages;

-- 5. Row-Level Security: allow anon/service-role to insert & select
--    Adjust policies to match your existing RLS setup.
alter table messages enable row level security;

-- Allow anyone with a valid anon key to read messages for a given request
create policy "Allow read messages"
  on messages for select
  using (true);

-- Allow anyone with a valid anon key to insert messages
create policy "Allow insert messages"
  on messages for insert
  with check (true);
