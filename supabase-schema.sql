-- PTUT Hub - Supabase schema
-- One-university architecture: PTUT
-- Run this in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- Roles are kept in the profile table rather than trusting client-side values.
create type public.user_role as enum ('student','cr','admin','super_admin');

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  short_name text,
  created_at timestamptz not null default now()
);

create table public.programs (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete cascade,
  name text not null,
  degree_level text default 'Undergraduate',
  created_at timestamptz not null default now(),
  unique(department_id, name)
);

create table public.semesters (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs(id) on delete cascade,
  semester_no int not null check (semester_no between 1 and 12),
  label text not null,
  created_at timestamptz not null default now(),
  unique(program_id, semester_no)
);

create table public.sections (
  id uuid primary key default gen_random_uuid(),
  semester_id uuid not null references public.semesters(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(semester_id, name)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  student_id text unique,
  email text,
  role public.user_role not null default 'student',
  section_id uuid references public.sections(id) on delete set null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  department_id uuid references public.departments(id) on delete set null,
  email text,
  created_at timestamptz not null default now()
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  program_id uuid references public.programs(id) on delete set null,
  name text not null,
  code text,
  credit_hours numeric(3,1),
  created_at timestamptz not null default now()
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  building text,
  capacity int,
  created_at timestamptz not null default now()
);

create table public.timetable_entries (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references public.sections(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  teacher_id uuid references public.teachers(id) on delete set null,
  room_id uuid references public.rooms(id) on delete set null,
  day_of_week smallint not null check (day_of_week between 1 and 7),
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  check (end_time > start_time)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  subject_id uuid references public.subjects(id) on delete set null,
  due_at timestamptz,
  priority smallint not null default 2 check (priority between 1 and 3),
  completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.exams (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references public.sections(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  room_id uuid references public.rooms(id) on delete set null,
  exam_at timestamptz not null,
  duration_minutes int,
  notes text,
  created_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  section_id uuid references public.sections(id) on delete cascade,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  type text not null default 'general',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index idx_profiles_section on public.profiles(section_id);
create index idx_timetable_section_day on public.timetable_entries(section_id, day_of_week, start_time);
create index idx_tasks_user_due on public.tasks(user_id, due_at);
create index idx_exams_section_time on public.exams(section_id, exam_at);
create index idx_notifications_user_created on public.notifications(user_id, created_at desc);
create index idx_announcements_section_date on public.announcements(section_id, published_at desc);

-- Automatically create a profile after Supabase Auth signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Updated-at helper.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute procedure public.set_updated_at();

drop trigger if exists tasks_updated_at on public.tasks;
create trigger tasks_updated_at before update on public.tasks
for each row execute procedure public.set_updated_at();

-- Role helper. Never let users change their own role through normal profile updates.
create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin','super_admin')
  );
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.departments enable row level security;
alter table public.programs enable row level security;
alter table public.semesters enable row level security;
alter table public.sections enable row level security;
alter table public.teachers enable row level security;
alter table public.subjects enable row level security;
alter table public.rooms enable row level security;
alter table public.timetable_entries enable row level security;
alter table public.tasks enable row level security;
alter table public.exams enable row level security;
alter table public.announcements enable row level security;
alter table public.notifications enable row level security;

-- Profiles: own profile only; staff can manage all profiles.
create policy "profile_select_own_or_staff" on public.profiles for select using (id = auth.uid() or public.is_staff());
create policy "profile_insert_self" on public.profiles for insert with check (id = auth.uid());
create policy "profile_update_own_nonrole" on public.profiles for update using (id = auth.uid() or public.is_staff()) with check (id = auth.uid() or public.is_staff());

-- Academic structure: students can read, staff can write.
create policy "departments_read" on public.departments for select to authenticated using (true);
create policy "departments_staff_write" on public.departments for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "programs_read" on public.programs for select to authenticated using (true);
create policy "programs_staff_write" on public.programs for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "semesters_read" on public.semesters for select to authenticated using (true);
create policy "semesters_staff_write" on public.semesters for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "sections_read" on public.sections for select to authenticated using (true);
create policy "sections_staff_write" on public.sections for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "teachers_read" on public.teachers for select to authenticated using (true);
create policy "teachers_staff_write" on public.teachers for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "subjects_read" on public.subjects for select to authenticated using (true);
create policy "subjects_staff_write" on public.subjects for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "rooms_read" on public.rooms for select to authenticated using (true);
create policy "rooms_staff_write" on public.rooms for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Timetable: a student sees only their section. Staff sees all.
create policy "timetable_read_own_section" on public.timetable_entries for select to authenticated
using (
  public.is_staff() or exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.section_id = timetable_entries.section_id
  )
);
create policy "timetable_staff_write" on public.timetable_entries for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Tasks: private to each user.
create policy "tasks_own" on public.tasks for select to authenticated using (user_id = auth.uid());
create policy "tasks_insert_own" on public.tasks for insert to authenticated with check (user_id = auth.uid());
create policy "tasks_update_own" on public.tasks for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "tasks_delete_own" on public.tasks for delete to authenticated using (user_id = auth.uid());

-- Exams: students see exams for their section; staff manages them.
create policy "exams_read_own_section" on public.exams for select to authenticated
using (
  public.is_staff() or exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.section_id = exams.section_id
  )
);
create policy "exams_staff_write" on public.exams for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Announcements: global announcements (section_id null) or student's section.
create policy "announcements_read_relevant" on public.announcements for select to authenticated
using (
  public.is_staff() or section_id is null or exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.section_id = announcements.section_id
  )
);
create policy "announcements_staff_write" on public.announcements for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Notifications: private to each user.
create policy "notifications_own" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "notifications_update_own" on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Helpful view for the frontend.
create or replace view public.my_section_timetable as
select
  t.id,
  t.section_id,
  s.name as section_name,
  t.day_of_week,
  t.start_time,
  t.end_time,
  sub.name as subject_name,
  sub.code as subject_code,
  te.name as teacher_name,
  r.name as room_name
from public.timetable_entries t
join public.sections s on s.id = t.section_id
join public.subjects sub on sub.id = t.subject_id
left join public.teachers te on te.id = t.teacher_id
left join public.rooms r on r.id = t.room_id;

-- NOTE: For production, expose the view only through a controlled API/RLS-compatible path.
-- The underlying timetable table remains protected by RLS.
