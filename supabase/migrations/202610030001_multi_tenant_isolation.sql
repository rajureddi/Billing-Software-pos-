-- =========================================================================
-- INDUSTRIAL MULTI-TENANT ISOLATION MIGRATION (V3 - Compound Primary Key)
-- Run this in Supabase Dashboard > SQL Editor (>_) > Run
-- =========================================================================

-- 1. Create or update the shops table
create table if not exists public.shops (
  id uuid primary key references auth.users(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete cascade,
  shop_name text not null default 'My Shop',
  owner_name text,
  email text,
  phone text,
  gstin text,
  address text,
  state text,
  created_at timestamptz default now()
);

-- Backfill all existing auth users into shops table
insert into public.shops (id, owner_id, shop_name)
select id, id, 'My Shop'
from auth.users
on conflict (id) do nothing;

-- 2. Clear old test data completely so schema modifications succeed cleanly
truncate table public.billing_records cascade;
truncate table public.billing_operations cascade;

-- 3. Update billing_records to use MULTI-TENANT primary key: (shop_id, kind, id)
alter table public.billing_records 
add column if not exists shop_id uuid;

-- Drop old single-tenant primary key constraint (kind, id)
alter table public.billing_records 
drop constraint if exists billing_records_pkey cascade;

-- Set shop_id to NOT NULL
alter table public.billing_records 
alter column shop_id set not null;

-- Add new multi-tenant compound primary key
alter table public.billing_records 
add constraint billing_records_pkey primary key (shop_id, kind, id);

-- Recreate foreign key to shops(id) with CASCADE
alter table public.billing_records 
drop constraint if exists billing_records_shop_id_fkey cascade;

alter table public.billing_records 
add constraint billing_records_shop_id_fkey 
foreign key (shop_id) references public.shops(id) on delete cascade;

-- Optimize index for scoped cursor queries
create index if not exists idx_billing_records_shop_cursor 
on public.billing_records (shop_id, cursor);

-- 4. Rewrite pull_billing_records to return records for the logged-in shop ONLY
create or replace function public.pull_billing_records(p_after bigint, p_limit integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  result jsonb;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(r order by r.cursor), '[]'::jsonb) into result from (
    select id, kind, payload, revision, cursor 
    from public.billing_records 
    where shop_id = current_user_id
      and cursor > greatest(coalesce(p_after, 0), 0) 
    order by cursor 
    limit least(greatest(coalesce(p_limit, 250), 1), 250)
  ) r;

  return result;
end; $$;

-- 5. Rewrite push_billing_records with Auto-Provisioning & Tenant Key Isolation
create or replace function public.push_billing_records(p_device_id text, p_records jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  op jsonb;
  current_record billing_records;
  saved billing_records;
  previous jsonb;
  accepted jsonb := '[]';
  conflicts jsonb := '[]';
  answer jsonb;
  operation_key text;
  expected bigint;
  client_revision bigint;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Unauthorized: Must be logged in to sync records';
  end if;

  -- Ensure shop exists for current user so FK is 100% guaranteed
  insert into public.shops (id, owner_id, shop_name)
  values (current_user_id, current_user_id, 'My Shop')
  on conflict (id) do nothing;

  insert into billing_devices(device_id)
  values(p_device_id)
  on conflict do nothing;

  if jsonb_typeof(p_records) <> 'array' or jsonb_array_length(p_records) > 1000 then
    raise exception 'Invalid batch';
  end if;

  -- User-scoped concurrency lock
  perform pg_advisory_xact_lock(hashtextextended('shop_sync_' || current_user_id::text, 0));

  for op in select value from jsonb_array_elements(p_records) loop
    client_revision := (op->>'revision')::bigint;
    expected := coalesce((op->>'baseRevision')::bigint, 0);
    operation_key := current_user_id::text || ':' || p_device_id || ':' || (op->>'kind') || ':' || (op->>'id') || ':' || client_revision;

    select result into previous from billing_operations where operation_id = operation_key;
    if found then
      accepted := accepted || jsonb_build_array(previous);
      continue;
    end if;

    select * into current_record 
    from billing_records 
    where shop_id = current_user_id and kind = op->>'kind' and id = op->>'id' 
    for update;

    if found then
      if current_record.payload = op->'payload' then
        saved := current_record;
      else
        update billing_records
        set payload = op->'payload',
            revision = greatest(revision + 1, client_revision),
            cursor = nextval(pg_get_serial_sequence('public.billing_records', 'cursor')),
            updated_at = now()
        where shop_id = current_user_id and kind = op->>'kind' and id = op->>'id'
        returning * into saved;
      end if;
    else
      insert into billing_records(shop_id, kind, id, payload, revision)
      values(current_user_id, op->>'kind', op->>'id', op->'payload', client_revision)
      returning * into saved;
    end if;

    answer := jsonb_build_object(
      'id', saved.id,
      'kind', saved.kind,
      'payload', saved.payload,
      'revision', client_revision,
      'serverRevision', saved.revision,
      'cursor', saved.cursor
    );
    insert into billing_operations(operation_id, result) values(operation_key, answer);
    accepted := accepted || jsonb_build_array(answer);
  end loop;

  return jsonb_build_object('accepted', accepted, 'conflicts', conflicts);
end; $$;

-- 6. Grant execute permissions
grant execute on function public.pull_billing_records(bigint, integer) to authenticated, anon;
grant execute on function public.push_billing_records(text, jsonb) to authenticated, anon;
grant all on public.shops to authenticated;
