// Supabase Edge Function. Deploy with JWT verification enabled.
// Secrets: RESEND_API_KEY, MAIL_FROM (verified sender), SUPABASE_URL,
// SUPABASE_SERVICE_ROLE_KEY. Do not expose secrets in index.html/config.js.
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function result(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}
function escapeHtml(value: unknown) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[ch] ?? ch));
}
Deno.serve(async (req) => {
  if(req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if(req.method !== 'POST') return result({ error: 'Método no permitido' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const mailFrom = Deno.env.get('MAIL_FROM');
  if(!url || !serviceKey) return result({ error:'Faltan secretos Supabase' }, 503);
  const auth = req.headers.get('authorization') ?? '';
  if(!auth.startsWith('Bearer ')) return result({ error: 'Autenticación requerida' }, 401);
  const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = auth.slice(7);
  const { data: userData, error: userError } = await db.auth.getUser(token);
  if(userError || !userData.user) return result({ error:'Sesión inválida' }, 401);
  const { data: isAdmin, error: adminError } = await db.from('app_admins').select('user_id').eq('user_id', userData.user.id).maybeSingle();
  if(adminError || !isAdmin) return result({ error:'Solo el administrador puede enviar avisos' }, 403);
  let id: string;
  try {
    const json = await req.json();
    id = String(json.request_id ?? '');
    if(!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/.test(id)) return result({ error:'Identificador incorrecto' }, 400);
  } catch { return result({ error:'JSON incorrecto' }, 400); }
  const { data: r, error } = await db.from('app_requests')
    .select('id,title,approved_resource_title,requester,requester_email,status,assigned_folder_title,email_status')
    .eq('id', id).maybeSingle();
  if(error || !r) return result({ error:'Solicitud no encontrada' }, 404);
  if(r.status === 'pending') return result({ error:'La solicitud aún no se ha revisado' }, 409);
  if(!r.requester_email) return result({ error:'Solicitud antigua sin dirección de correo' }, 422);
  if(r.email_status === 'sent') return result({ sent:true, already_sent:true });
  if(!resendKey || !mailFrom) return result({ error:'Configura RESEND_API_KEY y MAIL_FROM antes de enviar' }, 503);
  // Conditional update is an optimistic lock to avoid concurrent sends.
  const { data: claimed, error: claimError } = await db.from('app_requests')
    .update({ email_status: 'sending' }).eq('id',id).in('email_status',['pending','failed']).select('id');
  if(claimError) return result({ error:'No se pudo reservar el correo' }, 500);
  if(!claimed?.length) return result({ error:'Correo en proceso de envío o ya enviado' }, 409);
  const approved = r.status === 'approved';
  const resource = r.approved_resource_title || r.title;
  const folder = r.assigned_folder_title || 'Sin carpeta';
  const subject = approved ? 'Tu recurso ha sido aceptado' : 'Respuesta a tu propuesta de recurso';
  const body = approved
    ? `Tu propuesta «${resource}» ha sido aceptada. Carpeta asignada: ${folder}.`
    : `Tu propuesta «${resource}» no ha sido aceptada y no se ha asignado a ninguna carpeta.`;
  const html = `<p>Hola, ${escapeHtml(r.requester)}:</p><p>${escapeHtml(body)}</p><p>Gracias por colaborar con nuestro muro de recursos.</p>`;
  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${resendKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': `muro-request-${id}` },
      body: JSON.stringify({ from: mailFrom, to:[r.requester_email], subject, html, text:`Hola, ${r.requester}:\n\n${body}\n\nGracias por colaborar con nuestro muro de recursos.` }),
    });
    const message = await response.json().catch(() => ({}));
    if(!response.ok) throw Error(typeof message.message === 'string' ? message.message : 'Error del proveedor de correo');
    await db.from('app_requests').update({ email_status:'sent', email_sent_at: new Date().toISOString() }).eq('id',id).eq('email_status','sending');
    return result({ sent:true });
  } catch(err) {
    await db.from('app_requests').update({ email_status:'failed' }).eq('id',id).eq('email_status','sending');
    return result({ error:'Fallo al enviar correo: '+(err instanceof Error ? err.message : 'desconocido'), sent:false }, 502);
  }
});
