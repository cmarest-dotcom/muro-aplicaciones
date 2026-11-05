// Inspección limitada de metadatos públicos. No es un clasificador completo de contenido.
// Usar un proveedor de reputación/clasificación especializado para mayor fiabilidad.
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{...cors,'Content-Type':'application/json'}});
const offensive = /\b(?:puta|putas|puto|putos|mierda|mierdas|joder|jodete|coño|cojones|cabron|cabrona|cabrones|gilipollas|imbecil|imbeciles|idiota|idiotas|subnormal|subnormales|maricon|maricones|zorra|zorras|hijoputa|hijadeputa|fuck|shit|bitch|asshole)\b/i;
const adult = /\b(?:porn|porno|pornografia|pornografico|xxx|xvideos|xnxx|xhamster|pornhub|redtube|youporn|brazzers|onlyfans|sexcam|camgirl|hentai|rule34|adultvideo|adultvideos)\b/i;
const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[-_./?=&]+/g,' ').replace(/[^a-z0-9ñ ]/g,' ');
function isForbiddenNetworkHost(host:string){
  const h=host.toLowerCase().replace(/\.$/,'');
  if(h==='localhost'||h.endsWith('.localhost')||h.endsWith('.local')||h.endsWith('.internal')||h.endsWith('.test')||h.endsWith('.invalid')||h.endsWith('.onion')||h==='metadata.google.internal')return true;
  if(h.includes(':')) return true; // IPv6 literals excluded for SSRF protection.
  if(/^\d+(?:\.\d+){0,3}$/.test(h))return true; // IP/alternative IP literals excluded.
  return false;
}
function decodeEntities(s:string){return s.replace(/&(?:amp|quot|apos|lt|gt|nbsp|#(\d+)|#x([0-9a-f]+));/gi,(_m,dec,hex)=>dec?String.fromCodePoint(+dec):hex?String.fromCodePoint(parseInt(hex,16)):({amp:'&',quot:'"',apos:"'",lt:'<',gt:'>',nbsp:' '} as Record<string,string>)[_m.slice(1,-1).toLowerCase()]||' ')}
function extractMeta(html:string,name:string){
  const tags=html.match(/<meta\s+[^>]*>/gi)||[];
  for(const tag of tags){const key=tag.match(/(?:name|property)\s*=\s*["']([^"']+)["']/i)?.[1]?.toLowerCase();if(key!==name)continue;return decodeEntities(tag.match(/content\s*=\s*["']([^"']*)["']/i)?.[1]||'')}
  return '';
}
function sanitize(s:string){return s.replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim()}
// Obtiene un resumen verificable mediante snippets de Google (Serper) cuando no hay metadatos.
// La clave se configura exclusivamente como secreto SERPER_API_KEY de Supabase.
function descriptionUsable(s:string,host:string){
 const v=sanitize(s);
 if(v.length<45||v.length>240||/^\s*(página web|acceso al sitio|home|inicio|welcome|just a moment)/i.test(v))return false;
 if(normalize(v).includes('enable javascript')||normalize(v).includes('cookies to continue'))return false;
 return !offensive.test(normalize(v))&&!adult.test(normalize(v));
}
function conciseSnippet(raw:string){
 let s=sanitize(raw).replace(/\s*(?:\.\.\.|…)\s*/g,'. ').replace(/^[·•\-\s]+/,'');
 s=s.replace(/^.{0,30}?\s[—–|]\s/,'');
 // Avoid cutting in the middle of a word.
 if(s.length>220){let cut=s.lastIndexOf(' ',220);s=s.slice(0,cut>90?cut:220).replace(/[,:;\-\s.]+$/,'')+'.';}
 return s;
}
async function descriptionFromGoogle(host:string,title:string):Promise<string>{
 const apiKey=Deno.env.get('SERPER_API_KEY');
 if(!apiKey)return '';
 const searchQuery=`site:${host} ${title&&title.length<65?title:'para qué sirve'}`.slice(0,180);
 try{
   const response=await fetch('https://google.serper.dev/search',{
     method:'POST',headers:{'X-API-KEY':apiKey,'Content-Type':'application/json'},
     body:JSON.stringify({q:searchQuery,gl:'es',hl:'es',num:5}),signal:AbortSignal.timeout(6500)
   });
   if(!response.ok)return '';
   const data=await response.json();
   const matches=(Array.isArray(data.organic)?data.organic:[]).filter((entry:Record<string,unknown>)=>{
     try{const h=new URL(String(entry.link||'')).hostname.toLowerCase().replace(/^www\./,'');const base=host.toLowerCase().replace(/^www\./,'');return h===base||h.endsWith('.'+base)}catch{return false}
   });
   for(const item of matches){const candidate=conciseSnippet(String(item.snippet||''));if(descriptionUsable(candidate,host))return candidate;}
 }catch{/* No se expone error del proveedor ni su clave. */}
 return '';
}
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response(null,{headers:cors});
  if(req.method!=='POST')return json({error:'Método no permitido'},405);
  let href='';try{href=String((await req.json()).url||'')}catch{return json({error:'Solicitud incorrecta'},400)}
  let url:URL;try{url=new URL(href)}catch{return json({allowed:false,error:'Dirección web incorrecta'},400)}
  if(!['https:','http:'].includes(url.protocol)||url.username||url.password||isForbiddenNetworkHost(url.hostname)||url.port&&!['80','443'].includes(url.port))return json({allowed:false,error:'Dirección web no admitida'},422);
  const classification=normalize(url.hostname+' '+decodeURIComponent(url.pathname+url.search));
  if(adult.test(classification))return json({allowed:false,error:'No se permiten enlaces con contenido sexual o pornográfico.'},422);
  // Only accept a public DNS hostname; reject private/reserved IPv4 DNS results.
  try{
    const ips=await Deno.resolveDns(url.hostname,'A');
    if(!ips.length||ips.some(ip=>{const a=ip.split('.').map(Number);return a[0]===0||a[0]===10||a[0]===127||a[0]>=224||a[0]===169&&a[1]===254||a[0]===172&&a[1]>=16&&a[1]<=31||a[0]===192&&a[1]===168||a[0]===100&&a[1]>=64&&a[1]<=127||a[0]===192&&a[1]===0||a[0]===198&&[18,19].includes(a[1])}))return json({allowed:false,error:'El enlace no es una web pública'},422);
  }catch{return json({allowed:false,error:'No se pudo comprobar el dominio'},422)}
  let body='';let pageTitle='',description='';
  try{
    const r=await fetch(url.toString(),{redirect:'manual',signal:AbortSignal.timeout(7000),headers:{'Accept':'text/html','User-Agent':'Mozilla/5.0 (compatible; MuroRecursos/1.0)'}});
    if(r.status>=300&&r.status<400)return json({allowed:false,error:'La web redirige a otra dirección; introduce directamente la URL final'},422);
    if(!r.ok)return json({allowed:false,error:'La web no permite verificar su contenido (HTTP '+r.status+')'},422);
    if(!String(r.headers.get('content-type')||'').toLowerCase().includes('text/html'))return json({allowed:true,description:'',description_source:'none',needs_manual_description:true});
    const reader=r.body?.getReader();const chunks:Uint8Array[]=[];let size=0;
    if(reader){while(size<150000){const {value,done}=await reader.read();if(done)break;chunks.push(value);size+=value.length;}await reader.cancel().catch(()=>{});}
    const out=new Uint8Array(Math.min(size,150000));let pos=0;for(const c of chunks){out.set(c.slice(0,out.length-pos),pos);pos+=Math.min(c.length,out.length-pos);if(pos>=out.length)break}
    body=new TextDecoder().decode(out);
    pageTitle=sanitize(decodeEntities(body.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]||'')).slice(0,150);
    description=sanitize(extractMeta(body,'description')||extractMeta(body,'og:description')||extractMeta(body,'twitter:description')).slice(0,240);
    const keywords=extractMeta(body,'keywords');
    const text=normalize([pageTitle,description,keywords,body.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1]||''].join(' '));
    if(adult.test(text))return json({allowed:false,error:'El contenido de la web presenta indicios de material sexual o pornográfico.'},422);
    if(offensive.test(normalize(description)))description='';
  }catch{return json({allowed:false,error:'No se pudo inspeccionar la web; revisa el enlace o inténtalo después'},422)}
  if(!descriptionUsable(description,url.hostname))description='';
  let source=description?'website':'none';
  if(!description){description=await descriptionFromGoogle(url.hostname,pageTitle);if(description)source='google-search';}
  return json({allowed:true,title:pageTitle,description,description_source:source,needs_manual_description:!description});
});
