-- ============================================================
-- E-Ambulance: Bangladeshi NID verification
-- Run this in: Supabase Console -> SQL Editor -> New Query
-- ============================================================

-- 1. Table that mirrors the Bangladesh Election Commission NID record
--    (name, father's name, phone, date of birth, NID number).
create table if not exists public.nid_records (
  id              uuid primary key default gen_random_uuid(),
  nid_number      text unique not null,
  full_name       text not null,
  father_name     text,
  mother_name     text,
  date_of_birth   date not null,
  phone_number    text not null,
  gender          text check (gender in ('male','female','other')),
  address         text,
  created_at      timestamptz not null default now()
);

-- 2. Index for fast lookup by NID number / phone / name.
create index if not exists idx_nid_records_number on public.nid_records (nid_number);
create index if not exists idx_nid_records_phone  on public.nid_records (phone_number);

-- 3. Row Level Security: anon key can read for verification only.
alter table public.nid_records enable row level security;
create policy "Allow read nid_records via anon key"
  on public.nid_records for select
  using (true);

-- 4. Dummy data (Bangladeshi citizens) for testing sign-up verification.
insert into public.nid_records
  (nid_number, full_name, father_name, mother_name, date_of_birth, phone_number, gender, address)
values
  ('1234567890',  'Rahim Uddin',      'Karim Uddin',    'Fatema Begum', '1990-05-12', '01712345678', 'male',   'Dhaka'),
  ('199012345678901', 'Ayesha Akter', 'Abdul Karim',   'Rahima Khatun','1995-11-23', '01812345678', 'female', 'Chittagong'),
  ('9876543210',  'Md. Hasan Ali',    'Ali Hossain',    'Nasima Begum', '1988-02-14', '01912345678', 'male',   'Khulna'),
  ('2001123456789', 'Nusrat Jahan',  'Jahangir Alam',  'Shirin Akter', '2001-07-30', '01612345678', 'female', 'Rajshahi'),
  ('5566778899',  'Tariq Rahman',     'Mizanur Rahman', 'Salma Begum',  '1992-09-09', '01512345678', 'male',   'Sylhet')
on conflict (nid_number) do nothing;
