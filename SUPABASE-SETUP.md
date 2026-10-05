# PTUT Hub — Supabase Setup

## 1. Create the Supabase project

Create one Supabase project for PTUT Hub. Keep the project credentials private.

## 2. Run the schema

Open **SQL Editor** in Supabase and paste/run `supabase-schema.sql`.

This creates the one-university PTUT structure:

`Department → Program → Semester → Section → Student`

plus subjects, teachers, rooms, timetable, tasks, exams, announcements and notifications.

## 3. Authentication

Enable Email/Password in Supabase Authentication.

A database trigger automatically creates `profiles` after a successful signup.

## 4. First administrator

For the first admin, create the account normally, then change only that user's `profiles.role` to `admin` from the Supabase SQL editor. Do not expose role editing to the public client.

Example:

```sql
update public.profiles
set role = 'admin'
where email = 'YOUR_ADMIN_EMAIL';
```

## 5. Frontend configuration

The next frontend build will read:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Never put the Supabase `service_role` key in browser code.

## 6. Security model

Students can:
- read the academic structure
- read only their section timetable/exams/announcements
- create/read/update/delete only their own tasks
- read/update their own notifications

Staff can manage academic data and publish announcements.

## 7. Important

Do not add real student information until the authentication and RLS policies have been tested with at least two separate student accounts.
