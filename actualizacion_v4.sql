-- Ejecutar una vez en SQL Editor de Supabase. Conserva las solicitudes y recursos.
-- Validación adicional de texto y URL en la base de datos, que no puede omitirse cambiando el HTML.
-- IMPORTANTE: detectar TODAS las expresiones ofensivas o sitios para adultos requiere
-- un clasificador externo y revisión humana. Este filtro actúa como mínimo preventivo.
create or replace function public.validate_app_request_insert() returns trigger
language plpgsql set search_path = '' as $$
declare txt text; loc text;
begin
 if new.type not in ('app','web') then raise exception 'Solo se pueden proponer recursos'; end if;
 if length(trim(new.requester))=0 or new.requester_email is null or length(trim(new.requester_email))=0 then
   raise exception 'Nombre y correo electrónico son obligatorios';
 end if;
 if new.proposed_folder_title is not null and new.folder_id is not null then
   raise exception 'Selecciona una carpeta existente o propone una nueva, no ambas';
 end if;
 txt=lower(translate(coalesce(new.title,'')||' '||coalesce(new.description,'')||' '||coalesce(new.proposed_folder_title,''),'áéíóúüÁÉÍÓÚÜ','aeiouuAEIOUU'));
 if txt ~* '(^|[^[:alpha:]])(puta|putas|puto|putos|mierda|mierdas|joder|jodete|coño|cojones|cabron|cabrona|cabrones|gilipollas|imbecil|imbeciles|idiota|idiotas|subnormal|subnormales|maricon|maricones|zorra|zorras|hijoputa|hijadeputa|fuck|shit|bitch|asshole)([^[:alpha:]]|$)' then
   raise exception 'El título o la descripción contienen expresiones ofensivas';
 end if;
 loc=lower(regexp_replace(coalesce(new.url,''),'[-_./?=&%]+',' ','g'));
 if loc ~* '(^|[^[:alpha:]])(porn|porno|pornografia|pornografico|xxx|xvideos|xnxx|xhamster|pornhub|redtube|youporn|brazzers|onlyfans|sexcam|camgirl|hentai|rule34|adultvideo|adultvideos)([^[:alpha:]]|$)' then
   raise exception 'No se permiten enlaces a contenido sexual o pornográfico';
 end if;
 return new;
end; $$;
