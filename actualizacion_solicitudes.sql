-- Ejecuta este archivo si ya instalaste la versión anterior del muro.
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
