MI MURO DE APLICACIONES — INSTRUCCIONES
=======================================

INICIO RÁPIDO (DEMOSTRACIÓN)
1. Abre index.html en un navegador de ordenador.
2. Pulsa «Administrador» para activar la edición local.
3. Crea carpetas y enlaces. Los datos se guardan solo en ese navegador.
ATENCIÓN: este modo NO ofrece seguridad, sincronización ni enlace público compartible.

VERSIÓN REAL COMPARTIDA (recomendada)
1. Crea un proyecto gratuito en https://supabase.com.
2. En Supabase, abre SQL Editor y ejecuta el contenido de schema.sql.
3. En Authentication > Users, crea tu cuenta de correo electrónico con contraseña.
   Usa una contraseña larga, única y privada.
4. Copia el UUID (ID) de tu usuario de Authentication > Users.
5. En SQL Editor, ejecuta lo siguiente (sustituye TU-UUID):
   insert into public.app_admins (user_id) values ('TU-UUID') on conflict do nothing;
6. En Supabase > Project Settings > API o API Keys, copia la URL del proyecto
   y la clave PUBLICABLE / ANON (NUNCA service_role ni secret).
7. Edita config.js introduciendo esos dos datos entre comillas.
8. Sube index.html y config.js a un hosting estático por HTTPS como GitHub Pages,
   Netlify o Cloudflare Pages. No hace falta publicar schema.sql ni README.txt.
9. Abre el enlace publicado. Entra en «Administrador», con tu correo y contraseña.
10. Publica carpetas y aplicaciones, o márcalas «Solo administrador».
    Pulsa «Compartir» para enviar el enlace. Los visitantes no necesitan cuenta.

IMPORTANTE
- Config.js lleva únicamente una clave pública, protegida por políticas RLS del servidor.
- NO insertes contraseñas ni claves secretas en el HTML/JavaScript.
- La creación de cuentas de usuarios no está disponible en esta aplicación;
  la cuenta administradora la creas tú en Supabase.
- En Supabase > Authentication > Providers deshabilita nuevos registros
  públicos (sign-ups) si no deseas permitirlos.
- Los enlaces privados se protegen en la base de datos por RLS. Sin embargo,
  la propia aplicación web externa a la que apuntan podría seguir siendo pública
  si alguien conoce su URL. Para proteger también esa aplicación externa,
  esta necesitaría un control de acceso propio.
- No guardes enlaces con tokens de acceso o información sensible en la URL.
- Todos los dispositivos conectados al enlace público comparten los mismos datos;
  solo tu usuario administrador puede modificarlos.
- Para agregar una aplicación HTML nueva, primero publícala (ej. GitHub Pages)
  y después pega su URL en «Nueva aplicación».
- Puedes añadir una aplicación a la pantalla de inicio de iPhone o Android
  desde las opciones del navegador, para tener acceso rápido al muro.
- La función de copia JSON exporta todos los enlaces visibles para el administrador.
- Si la conexión a Supabase no funciona, comprueba configuración, políticas y HTTPS.

NOVEDADES DE ESTA VERSIÓN
- Al abrir una carpeta, su icono aparece junto al título.
- Carpetas públicas o privadas y aplicaciones públicas o privadas.
- Acceso administrador mediante correo y contraseña de Supabase.
- Los visitantes proponen recursos o carpetas con «Proponer recurso».
- El administrador recibe un contador de solicitudes pendientes en el muro
  y una bandeja donde puede revisar, editar los campos, aprobar o denegar.
- La bandeja se actualiza al volver a abrir la pestaña, cada 45 segundos
  mientras hay una sesión administradora activa, o al pulsar Actualizar.
- Las solicitudes no se añaden a las carpetas o recursos hasta su aprobación.
- Para una instalación NUEVA: ejecuta schema.sql en Supabase.
- Para ACTUALIZAR una instalación anterior: ejecuta solamente
  actualizacion_solicitudes.sql (NO ejecutes de nuevo schema.sql completo,
  porque contiene políticas de seguridad ya existentes).
- En modo demostración local las solicitudes solo existen en ese navegador,
  y el botón Administrador NO requiere autenticación real.
- Para que los otros usuarios te envíen solicitudes y tú las recibas desde
  otro dispositivo es INDISPENSABLE activar Supabase y publicar el muro.
- Las notificaciones son un contador visible dentro del muro; NO son alertas
  push ni correos y requieren que el administrador abra la aplicación.
- Los formularios públicos pueden recibir spam: si el enlace se comparte
  ampliamente, conviene poner un control antispam (Captcha/rate limiting).

NOVEDADES V3 — SOLICITUDES Y CORREO ELECTRÓNICO
================================================
- El formulario «Añadir recurso» admite solo aplicaciones HTML o páginas web.
- El solicitante debe indicar nombre y correo electrónico.
- La ubicación sugerida puede ser: sin indicar, carpeta pública existente,
  o propuesta de nueva carpeta (título); nada se crea sin aprobación.
- En la revisión, el administrador puede elegir carpeta existente, ninguna,
  o crear una nueva; también puede corregir título, enlace y visibilidad.
- La decisión guarda el nombre de la carpeta FINALMENTE asignada.
- Aceptación y rechazo generan un correo al solicitante (solo en versión publicada,
  con Supabase + proveedor de correo correctamente configurados).
- Si el envío falla, aparece en «Correos pendientes de enviar» y puede
  reintentarse. La aprobación/rechazo no se deshace por un fallo del correo.

ACTUALIZAR V2 A V3 (no elimina tus carpetas ni recursos)
1. Haz una copia de seguridad desde Supabase antes de actualizar.
2. Supabase > SQL Editor: ejecuta SOLAMENTE actualizacion_v3.sql.
   schema.sql ya incluye todo y se utiliza para INSTALACIONES NUEVAS,
   pero no debe ejecutarse otra vez sobre una instalación existente.
3. Sustituye el index.html del alojamiento por el nuevo. Mantén tu config.js.
4. Configura un proveedor de envío de correos, por ejemplo Resend
   (https://resend.com). Verifica el dominio del remitente para poder enviar
   correos a otras personas. Comprueba límites y políticas del plan elegido.
5. Instala Supabase CLI (https://supabase.com/docs/guides/local-development/cli).
   Desde la carpeta muro_apps, con el proyecto enlazado:
      supabase login
      supabase link --project-ref TU_PROJECT_REF
      supabase secrets set RESEND_API_KEY=TU_CLAVE MAIL_FROM="Muro de aplicaciones <avisos@tudominio.es>"
      supabase functions deploy notify-request-result
   SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY suelen estar disponibles como
   secretos reservados del entorno Edge Functions. No los escribas en HTML.
   Verifica que la función tenga JWT verification activada (config.toml).
6. Entra al muro como administrador, propón un recurso con un correo de prueba,
   apruébalo o recházalo y comprueba la entrega. Un 200 del proveedor de
   email solo confirma aceptación para envío, no necesariamente entrega final.
7. Si una notificación falla, abre Bandeja > Correos pendientes > Reintentar.

PRIVACIDAD Y SEGURIDAD
- Las direcciones de los solicitantes solo son visibles al administrador
  mediante las políticas RLS de Supabase; no las muestres en el muro público.
- Se deben informar la finalidad de recogida del correo y el tratamiento de datos
  personales, e incorporar aviso de privacidad adecuado al responsable del muro.
- Si recibes solicitudes de menores, revisa las exigencias aplicables del centro
  y la normativa de protección de datos antes de habilitar formularios abiertos.
- No añadas claves RESEND_API_KEY o SUPABASE_SERVICE_ROLE_KEY en config.js.
- Las pruebas en modo HTML local NO envían correos reales.
- El envío se intenta al revisar una solicitud con sesión de administrador.
  Si la aplicación se cierra durante el envío, el correo podría quedar
  pendiente. Revisa la bandeja y reintenta los que figuren fallidos.

============================================================
VERSIÓN 4 - MODIFICACIONES DE SEGURIDAD Y DESCRIPCIONES
============================================================
1. Sustituye index.html en GitHub Pages por este archivo nuevo.
2. Ejecuta actualizacion_v4.sql en el editor SQL de Supabase.
3. Despliega la función nueva inspect-resource:
   supabase functions deploy inspect-resource
   Usa el mismo proyecto que ya emplea notify-request-result.
4. Comprueba que config.js mantiene las mismas credenciales públicas de Supabase.
5. Prueba el alta de una web permitida, un título ofensivo y una URL para adultos.

El formulario Añadir recurso solo se cierra usando la X, Cancelar o tras
Enviar solicitud correctamente. Pulsar fuera no lo cierra; tampoco Escape.

Si la descripción está vacía, la función inspect-resource intenta obtener
la descripción pública (metadatos HTML) o el título de la página. Una web
que no permite inspección se rechaza preventivamente para nuevos envíos
con Supabase; algunas webs legítimas podrían resultar bloqueadas.

IMPORTANTE: los filtros por palabras y metadatos son preventivos, no pueden
garantizar la detección de todo tipo de lenguaje ofensivo, pornografía ni
contenido alojado en dominios neutrales. El administrador debe revisar
personalmente las propuestas antes de aprobarlas. Para restricciones fuertes,
integrar un servicio especializado de clasificación de URLs/contenido y
controles en servidor, con registro y límites de solicitudes.

Modo demostración: no puede leer metadatos externos de forma fiable ni
aplicar las restricciones del servidor; aplica los filtros locales.
