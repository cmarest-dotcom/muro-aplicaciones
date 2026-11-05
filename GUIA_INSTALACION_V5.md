# Mi muro de aplicaciones — V5

## Cambios
- Si la web publica una descripción informativa (metadatos), se utiliza.
- Si no la publica o es genérica, la función `inspect-resource` busca en Google a través de Serper.dev. Solo usa fragmentos de resultados del mismo dominio, no inventa descripciones.
- Si tampoco obtiene una descripción fiable, el usuario debe escribirla manualmente.
- Aplicación web instalable (PWA) en Android, iPhone y ordenador: manifest, iconos y service worker.

## A. Publicación en GitHub Pages
1. Extrae el ZIP y abre la carpeta `muro_apps`.
2. En tu repositorio de GitHub Pages, sube **todos** los archivos de `muro_apps` manteniendo su estructura, especialmente `index.html`, `config.js`, `manifest.webmanifest`, `service-worker.js` y `icons/`. No subas solo `index.html`.
3. Revisa que `config.js` conserva la URL y la clave pública (anon/publishable) de tu proyecto Supabase. No añadas claves privadas.
4. Abre la URL HTTPS de GitHub Pages y recarga; el nuevo aspecto puede requerir recarga forzada por caché.

## B. Base de datos y autenticación
Si ya usas Supabase con la V4, **no ejecutes de nuevo `schema.sql`**. Esta actualización no cambia tablas ni datos. Sigue usando tu proyecto Supabase actual.
Si todavía no configuraste Supabase, configura un proyecto, aplica `schema.sql` y posteriores actualizaciones según `README.txt`, crea el usuario administrador y habilita las políticas. Prueba la sesión y las solicitudes antes de abrir el muro a otros usuarios.

## C. Búsqueda en Google para completar descripciones
Google Custom Search JSON API está cerrada a nuevas altas. Se utiliza **Serper.dev** (API externa que entrega resultados de Google); puede exigir una cuenta y tener límites de uso o costes.
1. Crea una cuenta en https://serper.dev y copia su API Key desde el panel.
2. En Supabase Dashboard: Project Settings → Edge Functions → Secrets (o `supabase secrets set SERPER_API_KEY=...` desde CLI). Crea el secreto `SERPER_API_KEY` y pega la clave. **No lo pongas en config.js ni en GitHub.**
3. Actualiza/despliega `supabase/functions/inspect-resource/index.ts` desde Supabase CLI: `supabase functions deploy inspect-resource`. Comprueba que `supabase/config.toml` mantiene la verificación JWT.
4. Prueba añadir una URL cuya página carezca de metadatos descriptivos. La descripción resultante debe explicar para qué sirve, o solicitar descripción manual si no hay un resultado fiable.
5. No hay cambios SQL en V5; conserva la base de datos de V4.

**Privacidad y seguridad:** las funciones públicas pueden consumir cuota del buscador. Considera rate limiting en una instalación abierta a muchos usuarios. La clasificación de contenidos no detecta todo: mantén la aprobación del administrador.

## D. Instalar en móvil
**Android (Chrome):** abre el enlace HTTPS → menú de tres puntos → Instalar aplicación o Añadir a pantalla de inicio → confirma.
**iPhone (Safari):** abre el enlace HTTPS → Compartir → Añadir a pantalla de inicio → activa «Abrir como app» si aparece → Añadir.
No se necesita App Store ni Play Store. Requiere conexión para consultar y actualizar recursos; no es una app nativa ni un servicio completamente offline.

## E. Comprobación rápida
1. Abre el muro en el ordenador: comprueba recursos y carpetas.
2. Entra como administrador con correo y contraseña.
3. Desde otro navegador o móvil, envía una solicitud de prueba.
4. Aprueba la solicitud y verifica la carpeta y el correo (para el correo debe seguir configurada la función de V3 con el proveedor de correo).
5. Instala en el móvil y comprueba que aparece el icono «Mi muro».
