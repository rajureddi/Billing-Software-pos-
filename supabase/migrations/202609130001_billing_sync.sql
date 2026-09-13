-- Owner-scoped sync. Execute once using the Supabase SQL editor or CLI.
create table public.billing_devices (
 owner_id uuid not null references auth.users(id) on delete cascade,
 device_id text not null,
 registered_at timestamptz not null default now(),
 primary key(owner_id,device_id)
);
create table public.billing_records (
 owner_id uuid not null references auth.users(id) on delete cascade,
 kind text not null,
 id text not null,
 payload jsonb not null,
 revision bigint not null default 1,
 cursor bigint generated always as identity,
 updated_at timestamptz not null default now(),
 primary key(owner_id,kind,id)
);
create table public.billing_operations (
 owner_id uuid not null references auth.users(id) on delete cascade,
 operation_id text not null,
 result jsonb not null,
 primary key(owner_id,operation_id)
);
alter table public.billing_devices enable row level security;
alter table public.billing_records enable row level security;
alter table public.billing_operations enable row level security;
create policy own_devices on public.billing_devices for select to authenticated using(owner_id=auth.uid());
create policy own_records on public.billing_records for select to authenticated using(owner_id=auth.uid());
create policy own_operations on public.billing_operations for select to authenticated using(owner_id=auth.uid());
-- Writes are allowed only through validating functions below.
revoke all on public.billing_devices,public.billing_records,public.billing_operations from anon,authenticated;
grant select on public.billing_devices,public.billing_records,public.billing_operations to authenticated;

create function public.register_billing_device(p_device_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(p_device_id) not between 1 and 128 then raise exception 'Invalid device'; end if;
 insert into billing_devices(owner_id,device_id) values(auth.uid(),p_device_id) on conflict do nothing;
end; $$;

create function public.push_billing_records(p_device_id text,p_records jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
 op jsonb; current_record billing_records; saved billing_records; previous jsonb;
 accepted jsonb := '[]'; conflicts jsonb := '[]'; answer jsonb;
 operation_key text; expected bigint; client_revision bigint; uid uuid := auth.uid();
begin
 if uid is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from billing_devices where owner_id=uid and device_id=p_device_id) then raise exception 'Register device first'; end if;
 if jsonb_typeof(p_records) <> 'array' or jsonb_array_length(p_records)>100 then raise exception 'Invalid batch'; end if;
 -- Serialize pushes per owner, including competing inserts of the same new ID.
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 for op in select value from jsonb_array_elements(p_records) loop
  if coalesce(op->>'kind','') not in ('product','category','customer','settings','shop','invoice','payment','movement','stockMovement','cancellation','draft') then raise exception 'Invalid record kind'; end if;
  if length(coalesce(op->>'id','')) not between 1 and 200 or jsonb_typeof(op->'payload') <> 'object' then raise exception 'Invalid record'; end if;
  client_revision := coalesce((op->>'revision')::bigint,1);
  expected := coalesce((op->>'baseRevision')::bigint,0);
  operation_key := p_device_id || ':' || (op->>'kind') || ':' || (op->>'id') || ':' || client_revision::text;
  select result into previous from billing_operations where owner_id=uid and operation_id=operation_key;
  if found then accepted := accepted || jsonb_build_array(previous); continue; end if;
  select * into current_record from billing_records where owner_id=uid and kind=op->>'kind' and id=op->>'id' for update;
  if found then
   if current_record.payload = op->'payload' then
    saved := current_record;
   elsif current_record.kind in ('invoice','payment','movement','stockMovement','cancellation') or current_record.revision <> expected then
    conflicts := conflicts || jsonb_build_array(jsonb_build_object('id',current_record.id,'kind',current_record.kind,'payload',current_record.payload,'revision',current_record.revision,'cursor',current_record.cursor,'conflict',true));
    continue;
   else
    update billing_records set payload=op->'payload',revision=revision+1,cursor=nextval(pg_get_serial_sequence('public.billing_records','cursor')),updated_at=now()
     where owner_id=uid and kind=op->>'kind' and id=op->>'id' returning * into saved;
   end if;
  else
   if expected <> 0 then raise exception 'Missing base record'; end if;
   insert into billing_records(owner_id,kind,id,payload) values(uid,op->>'kind',op->>'id',op->'payload') returning * into saved;
  end if;
  answer := jsonb_build_object('id',saved.id,'kind',saved.kind,'payload',saved.payload,'revision',client_revision,'serverRevision',saved.revision,'cursor',saved.cursor);
  insert into billing_operations(owner_id,operation_id,result) values(uid,operation_key,answer);
  accepted := accepted || jsonb_build_array(answer);
 end loop;
 return jsonb_build_object('accepted',accepted,'conflicts',conflicts);
end; $$;

create function public.pull_billing_records(p_after bigint default 0,p_limit integer default 250) returns jsonb
language sql security definer set search_path = public as $$
 select coalesce(jsonb_agg(r order by r.cursor),'[]'::jsonb) from (
  select id,kind,payload,revision,cursor from billing_records where owner_id=auth.uid() and cursor>p_after order by cursor limit least(greatest(p_limit,1),250)
 ) r;
$$;
revoke execute on function public.register_billing_device(text),public.push_billing_records(text,jsonb),public.pull_billing_records(bigint,integer) from public,anon;
grant execute on function public.register_billing_device(text),public.push_billing_records(text,jsonb),public.pull_billing_records(bigint,integer) to authenticated;

