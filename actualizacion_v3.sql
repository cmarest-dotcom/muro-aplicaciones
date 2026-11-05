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
