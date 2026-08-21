-- ذائقتي — Supabase schema v4 (multi-user, production-ready baseline)
-- Frontend uses only Project URL + publishable key. Never expose service_role/secret keys.

create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

-- =========================
-- Profiles
-- =========================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null check (char_length(display_name) between 1 and 80),
  bio text not null default '' check (char_length(bio) <= 500),
  avatar_url text not null default '',
  role text not null default 'creator' check (role in ('creator','admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_profiles_username_lower
  on public.profiles (lower(username));

-- Admin lookup used inside RLS without recursive profile-policy evaluation.
create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.is_active = true
  );
$$;

revoke all on function private.is_admin() from public, anon, authenticated;
grant execute on function private.is_admin() to anon, authenticated;

-- True when current user is an active owner of target_owner, or an active admin.
create or replace function private.can_manage_owner(target_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and (p.id = target_owner or p.role = 'admin')
  );
$$;

revoke all on function private.can_manage_owner(uuid) from public, anon, authenticated;
grant execute on function private.can_manage_owner(uuid) to anon, authenticated;

-- Automatically create a profile after email/password signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_username text;
  requested_name text;
begin
  requested_username := lower(coalesce(new.raw_user_meta_data->>'username',''));
  requested_name := coalesce(
    nullif(new.raw_user_meta_data->>'display_name',''),
    nullif(split_part(coalesce(new.email,''),'@',1),''),
    'User'
  );

  if requested_username !~ '^[a-z0-9_]{3,24}$'
     or exists (select 1 from public.profiles p where lower(p.username)=requested_username) then
    requested_username := 'user_' || substr(replace(new.id::text,'-',''),1,10);
  end if;

  insert into public.profiles (id, username, display_name)
  values (new.id, requested_username, left(requested_name,80));

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Creators can edit their public profile, but cannot promote/disable themselves.
create or replace function public.protect_profile_privileged_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) = old.id and not private.is_admin() then
    if new.role is distinct from old.role then
      raise exception 'role cannot be changed by this user';
    end if;
    if new.is_active is distinct from old.is_active then
      raise exception 'is_active cannot be changed by this user';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.protect_profile_privileged_fields() from public, anon, authenticated;

drop trigger if exists protect_profile_privileged_fields on public.profiles;
create trigger protect_profile_privileged_fields
before update on public.profiles
for each row execute function public.protect_profile_privileged_fields();

-- =========================
-- Places / Items
-- =========================
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  city text not null check (char_length(city) between 1 and 80),
  type text not null check (type in ('restaurant','cafe')),
  cover_url text not null default '',
  notes text not null default '' check (char_length(notes) <= 3000),
  rating_override numeric(3,2) check (rating_override is null or (rating_override >= 0 and rating_override <= 5)),
  receipt_url text not null default '',
  total_override numeric(10,2) check (total_override is null or total_override >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  photo_url text not null default '',
  rating numeric(2,1) not null check (rating >= 0 and rating <= 5),
  price numeric(10,2) not null default 0 check (price >= 0),
  notes text not null default '' check (char_length(notes) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_places_owner on public.places(owner_id);
create index if not exists idx_places_owner_city_type on public.places(owner_id, city, type);
create index if not exists idx_places_updated_at on public.places(updated_at desc);
create index if not exists idx_items_place on public.items(place_id);
create index if not exists idx_items_owner on public.items(owner_id);

-- Ensure an item's owner always matches its parent place.
create or replace function public.enforce_item_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_owner uuid;
begin
  select p.owner_id into parent_owner
  from public.places p
  where p.id = new.place_id;

  if parent_owner is null then
    raise exception 'place not found';
  end if;

  new.owner_id := parent_owner;
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.enforce_item_owner() from public, anon, authenticated;

drop trigger if exists enforce_item_owner on public.items;
create trigger enforce_item_owner
before insert or update on public.items
for each row execute function public.enforce_item_owner();

create or replace function public.touch_place_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.touch_place_updated_at() from public, anon, authenticated;

drop trigger if exists touch_place_updated_at on public.places;
create trigger touch_place_updated_at
before update on public.places
for each row execute function public.touch_place_updated_at();

-- =========================
-- Row Level Security
-- =========================
alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.items enable row level security;

-- Public can see active profiles. A disabled user may still read their own profile.
drop policy if exists "Profiles public read" on public.profiles;
create policy "Profiles public read" on public.profiles
for select to anon, authenticated
using (
  is_active = true
  or id = (select auth.uid())
  or private.is_admin()
);

-- Only active owner or admin may update. Trigger protects role/is_active from self-escalation.
drop policy if exists "Profile owner or admin update" on public.profiles;
create policy "Profile owner or admin update" on public.profiles
for update to authenticated
using (private.can_manage_owner(id))
with check (private.can_manage_owner(id));

-- Public sees places belonging to active profiles; owners/admin also see their managed rows.
drop policy if exists "Places public read" on public.places;
create policy "Places public read" on public.places
for select to anon, authenticated
using (
  private.can_manage_owner(owner_id)
  or exists (
    select 1 from public.profiles p
    where p.id = owner_id and p.is_active = true
  )
);

drop policy if exists "Place owner insert" on public.places;
create policy "Place owner insert" on public.places
for insert to authenticated
with check (private.can_manage_owner(owner_id));

drop policy if exists "Place owner update" on public.places;
create policy "Place owner update" on public.places
for update to authenticated
using (private.can_manage_owner(owner_id))
with check (private.can_manage_owner(owner_id));

drop policy if exists "Place owner delete" on public.places;
create policy "Place owner delete" on public.places
for delete to authenticated
using (private.can_manage_owner(owner_id));

-- Items follow the same ownership/public visibility model.
drop policy if exists "Items public read" on public.items;
create policy "Items public read" on public.items
for select to anon, authenticated
using (
  private.can_manage_owner(owner_id)
  or exists (
    select 1 from public.profiles p
    where p.id = owner_id and p.is_active = true
  )
);

drop policy if exists "Item owner insert" on public.items;
create policy "Item owner insert" on public.items
for insert to authenticated
with check (
  private.can_manage_owner(owner_id)
  and exists (
    select 1 from public.places p
    where p.id = place_id and p.owner_id = owner_id
  )
);

drop policy if exists "Item owner update" on public.items;
create policy "Item owner update" on public.items
for update to authenticated
using (private.can_manage_owner(owner_id))
with check (
  private.can_manage_owner(owner_id)
  and exists (
    select 1 from public.places p
    where p.id = place_id and p.owner_id = owner_id
  )
);

drop policy if exists "Item owner delete" on public.items;
create policy "Item owner delete" on public.items
for delete to authenticated
using (private.can_manage_owner(owner_id));

-- Explicit Data API grants. RLS still determines which rows are accessible.
revoke all on table public.profiles, public.places, public.items from anon, authenticated;
grant select on table public.profiles, public.places, public.items to anon;
grant select, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.places, public.items to authenticated;

-- =========================
-- Storage
-- =========================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'blog-media',
  'blog-media',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- A creator writes only beneath /<their-auth-uid>/...; admin may manage all media.
drop policy if exists "Blog media upload" on storage.objects;
create policy "Blog media upload" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'blog-media'
  and (
    (
      (storage.foldername(name))[1] = (select auth.uid())::text
      and private.can_manage_owner((select auth.uid()))
    )
    or private.is_admin()
  )
);

drop policy if exists "Blog media update" on storage.objects;
create policy "Blog media update" on storage.objects
for update to authenticated
using (
  bucket_id = 'blog-media'
  and (
    ((storage.foldername(name))[1] = (select auth.uid())::text
      and private.can_manage_owner((select auth.uid())))
    or private.is_admin()
  )
)
with check (
  bucket_id = 'blog-media'
  and (
    ((storage.foldername(name))[1] = (select auth.uid())::text
      and private.can_manage_owner((select auth.uid())))
    or private.is_admin()
  )
);

drop policy if exists "Blog media delete" on storage.objects;
create policy "Blog media delete" on storage.objects
for delete to authenticated
using (
  bucket_id = 'blog-media'
  and (
    ((storage.foldername(name))[1] = (select auth.uid())::text
      and private.can_manage_owner((select auth.uid())))
    or private.is_admin()
  )
);

-- =========================
-- Realtime (Postgres Changes)
-- =========================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='places'
  ) then
    alter publication supabase_realtime add table public.places;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='items'
  ) then
    alter publication supabase_realtime add table public.items;
  end if;
end $$;

notify pgrst, 'reload schema';

-- =========================
-- Admin bootstrap (run only after you create your own account from the website)
-- =========================
-- Replace YOUR_EMAIL and run this one statement manually or ask ChatGPT to do it:
-- update public.profiles
-- set role='admin', is_active=true
-- where id=(select id from auth.users where email='YOUR_EMAIL');
