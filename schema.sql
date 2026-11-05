-- Ejecutar en Supabase > SQL Editor. Requiere una cuenta creada en Authentication > Users.
create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.app_folders (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 70),
  icon text not null default '📁',
  visibility text not null default 'public' check (visibility in ('public','private')),
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.app_links (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 100),
  url text not null check (url ~* '^https?://[^ ]+$'),
  description text not null default '',
  icon text not null default '🔗',
  kind text not null default 'app' check (kind in ('app','web')),
  visibility text not null default 'private' check (visibility in ('public','private')),
  folder_id uuid references public.app_folders(id) on delete set null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.app_preferences (
  id integer primary key default 1 check (id=1),
  title text not null default 'Mi muro de aplicaciones',
  subtitle text not null default 'Todas mis herramientas en un solo lugar',
  accent text not null default '#7c77d9',
  bg text not null default '#f7f7ff',
  font text not null default 'system',
  density text not null default 'cards',
  updated_at timestamptz not null default now()
);
insert into public.app_preferences (id) values (1) on conflict (id) do nothing;

create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.app_admins where user_id = (select auth.uid()));
$$;

alter table public.app_admins enable row level security;
alter table public.app_folders enable row level security;
alter table public.app_links enable row level security;
alter table public.app_preferences enable row level security;

-- Las listas públicas no revelan datos privados; el administrador ve todos.
create policy "admin_identity_self" on public.app_admins for select to authenticated
  using (user_id = (select auth.uid()));
create policy "folders_read" on public.app_folders for select to anon, authenticated
  using (visibility = 'public' or (select public.is_app_admin()));
create policy "folders_insert" on public.app_folders for insert to authenticated
  with check ((select public.is_app_admin()));
create policy "folders_update" on public.app_folders for update to authenticated
  using ((select public.is_app_admin())) with check ((select public.is_app_admin()));
create policy "folders_delete" on public.app_folders for delete to authenticated
  using ((select public.is_app_admin()));
create policy "links_read" on public.app_links for select to anon, authenticated
  using ((visibility = 'public' and (folder_id is null or exists (
      select 1 from public.app_folders f where f.id = folder_id and f.visibility = 'public'
    ))) or (select public.is_app_admin()));
create policy "links_insert" on public.app_links for insert to authenticated
  with check ((select public.is_app_admin()));
create policy "links_update" on public.app_links for update to authenticated
  using ((select public.is_app_admin())) with check ((select public.is_app_admin()));
create policy "links_delete" on public.app_links for delete to authenticated
  using ((select public.is_app_admin()));
create policy "preferences_read" on public.app_preferences for select to anon, authenticated using (true);
create policy "preferences_insert" on public.app_preferences for insert to authenticated
  with check ((select public.is_app_admin()));
create policy "preferences_update" on public.app_preferences for update to authenticated
  using ((select public.is_app_admin())) with check ((select public.is_app_admin()));
create policy "preferences_delete" on public.app_preferences for delete to authenticated
  using ((select public.is_app_admin()));

-- IMPORTANTE: sustituye el UUID siguiente por el identificador del usuario
-- creado en Supabase > Authentication > Users. Ejecuta esta línea por separado:
-- insert into public.app_admins (user_id) values ('TU-UUID-DE-USUARIO') on conflict do nothing;

-- Solicitudes de visitantes (incluido acceso anónimo).
create table if not exists public.app_requests (
 id uuid primary key default gen_random_uuid(),
 type text not null check(type in ('app','web','folder')),
 title text not null check(char_length(title) between 1 and 100),
 url text check(url is null or url ~* '^https?://[^ ]+$'),
 description text not null default '' check(char_length(description)<=500),
 requester text not null default '' check(char_length(requester)<=80),
 folder_id uuid references public.app_folders(id) on delete set null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 constraint request_valid_url check((type='folder' and url is null) or (type in ('app','web') and url is not null))
);
alter table public.app_requests enable row level security;
create policy "requests_admin_read" on public.app_requests for select to authenticated using ((select public.is_app_admin()));
-- INSERT abierto y limitado a campos propuestos: status debe permanecer pendiente.
create policy "requests_public_submit" on public.app_requests for insert to anon, authenticated
 with check (status='pending' and reviewed_at is null and (
  folder_id is null or exists(select 1 from public.app_folders f where f.id=folder_id and f.visibility='public')
 ));
-- Bloqueo de atributos internos en las peticiones INSERT anónimas.
revoke insert on public.app_requests from anon,authenticated;
grant insert(type,title,url,description,requester,folder_id) on public.app_requests to anon,authenticated;
grant select on public.app_requests to authenticated;

-- Resolver en una sola transacción, y con comprobación en servidor de la identidad.
create or replace function public.review_app_request(p_id uuid,p_decision text,p_payload jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.app_requests%rowtype;
declare f uuid;
declare vis text;
declare nm text;
declare ico text;
declare pos integer;
begin
 if not public.is_app_admin() then raise exception 'Solo el administrador puede revisar solicitudes'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Decisión no válida'; end if;
 select * into r from public.app_requests where id=p_id for update;
 if not found or r.status <> 'pending' then raise exception 'Solicitud no pendiente'; end if;
 if p_decision='approved' then
  if p_payload is null then raise exception 'Faltan datos para aprobar'; end if;
  nm=trim(p_payload->>'title');ico=coalesce(nullif(trim(p_payload->>'icon'),''),'📁');
  vis=p_payload->>'visibility';pos=coalesce((p_payload->>'position')::bigint,0)::integer;
  if nm is null or nm='' or vis not in ('public','private') then raise exception 'Datos incompletos'; end if;
  if r.type='folder' then
   insert into public.app_folders(title,icon,visibility,position) values(nm,ico,vis,pos);
  else
   f=nullif(p_payload->>'folder_id','')::uuid;
   if f is not null and not exists(select 1 from public.app_folders where id=f) then raise exception 'Carpeta inexistente'; end if;
   if f is not null and vis='public' and exists(select 1 from public.app_folders where id=f and visibility='private') then raise exception 'Carpeta privada'; end if;
   insert into public.app_links(title,url,description,icon,kind,visibility,folder_id,position)
    values(nm,p_payload->>'url',coalesce(p_payload->>'description',''),ico,r.type,vis,f,pos);
  end if;
 end if;
 update public.app_requests set status=p_decision,reviewed_at=now() where id=p_id;
end;$$;
revoke execute on function public.review_app_request(uuid,text,jsonb) from public,anon;
grant execute on function public.review_app_request(uuid,text,jsonb) to authenticated;
-- VERSION 3. Ejecutar UNA VEZ en Supabase SQL Editor sobre la base de V2.
-- No contiene claves privadas de correo.
alter table public.app_requests
 add column if not exists requester_email text,
 add column if not exists proposed_folder_title text,
 add column if not exists assigned_folder_title text,
 add column if not exists approved_resource_title text,
 add column if not exists email_status text default 'pending',
 add column if not exists email_sent_at timestamptz;

-- Facilita migrar solicitudes antiguas sin correo sin rechazarlas.
alter table public.app_requests drop constraint if exists app_requests_requester_email_format;
alter table public.app_requests add constraint app_requests_requester_email_format
 check (requester_email is null or (char_length(requester_email)<=254 and requester_email ~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$'));
alter table public.app_requests drop constraint if exists app_requests_proposed_folder_title_length;
alter table public.app_requests add constraint app_requests_proposed_folder_title_length
 check (proposed_folder_title is null or char_length(proposed_folder_title) between 1 and 70);
alter table public.app_requests drop constraint if exists app_requests_email_status_enum;
alter table public.app_requests add constraint app_requests_email_status_enum
 check(email_status in ('pending','sending','sent','failed'));

-- Todo nuevo recurso solicitado debe incluir nombre y correo. Mantiene los registros anteriores.
create or replace function public.validate_app_request_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
 if new.type not in ('app','web') then raise exception 'Solo se pueden proponer recursos'; end if;
 if length(trim(new.requester))=0 or new.requester_email is null or length(trim(new.requester_email))=0 then
   raise exception 'Nombre y correo electrónico son obligatorios';
 end if;
 if new.proposed_folder_title is not null and new.folder_id is not null then
   raise exception 'Selecciona una carpeta existente o propone una nueva, no ambas';
 end if;
 return new;
end; $$;
drop trigger if exists validate_app_request_new on public.app_requests;
create trigger validate_app_request_new before insert on public.app_requests
for each row execute function public.validate_app_request_insert();

-- Limitar las columnas de inserción a los campos del visitante.
revoke insert on public.app_requests from anon,authenticated;
grant insert(type,title,url,description,requester,requester_email,folder_id,proposed_folder_title) on public.app_requests to anon,authenticated;

-- Aprobación atómica: crea la nueva carpeta si el administrador la elige,
-- crea el recurso y guarda la carpeta realmente asignada para el correo.
create or replace function public.review_app_request(p_id uuid,p_decision text,p_payload jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.app_requests%rowtype;
declare f uuid;
declare vis text;
declare nm text;
declare ico text;
declare pos integer;
declare folder_name text;
declare new_folder_name text;
begin
 if not public.is_app_admin() then raise exception 'Solo el administrador puede revisar solicitudes'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Decisión no válida'; end if;
 select * into r from public.app_requests where id=p_id for update;
 if not found or r.status <> 'pending' then raise exception 'Solicitud no pendiente'; end if;
 if p_decision='approved' then
  if p_payload is null then raise exception 'Faltan datos para aprobar'; end if;
  nm=trim(p_payload->>'title');ico=coalesce(nullif(trim(p_payload->>'icon'),''),'📱');
  vis=p_payload->>'visibility';pos=coalesce((p_payload->>'position')::bigint,0)::integer;
  if nm is null or nm='' or vis not in ('public','private') then raise exception 'Datos incompletos'; end if;
  if r.type='folder' then
    -- Compatibilidad con solicitudes de carpeta creadas con V2.
    insert into public.app_folders(title,icon,visibility,position)
    values(nm,ico,vis,pos) returning title into folder_name;
  else
    f=nullif(p_payload->>'folder_id','')::uuid;
    new_folder_name=nullif(trim(coalesce(p_payload->>'new_folder_title','')),'');
    if f is not null and new_folder_name is not null then raise exception 'Dos carpetas de destino'; end if;
    if new_folder_name is not null then
      if char_length(new_folder_name)>70 then raise exception 'Título de carpeta demasiado largo'; end if;
      insert into public.app_folders(title,icon,visibility,position)
      values(new_folder_name,'📁',vis,pos) returning id,title into f,folder_name;
    elsif f is not null then
      select title into folder_name from public.app_folders where id=f;
      if folder_name is null then raise exception 'Carpeta inexistente'; end if;
    end if;
    if f is not null and vis='public' and exists(
      select 1 from public.app_folders where id=f and visibility='private'
    ) then raise exception 'Una carpeta privada no admite recursos públicos'; end if;
    insert into public.app_links(title,url,description,icon,kind,visibility,folder_id,position)
    values(nm,p_payload->>'url',coalesce(p_payload->>'description',''),ico,r.type,vis,f,pos);
    folder_name=coalesce(folder_name,'Sin carpeta');
  end if;
 end if;
 update public.app_requests set status=p_decision,reviewed_at=now(),
   assigned_folder_title=case when p_decision='approved' then folder_name else null end,
   approved_resource_title=case when p_decision='approved' then nm else null end,
   email_status='pending',email_sent_at=null
 where id=p_id;
end;$$;
revoke execute on function public.review_app_request(uuid,text,jsonb) from public,anon;
grant execute on function public.review_app_request(uuid,text,jsonb) to authenticated;
