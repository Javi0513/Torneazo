// Configuración pública de TORNEAZO. Aquí NUNCA va la clave service_role ni ningún secreto.
window.APP_CONFIG={
  supabaseUrl:'https://qflfsqomewjxebvdhgfo.supabase.co',  // proyecto Supabase propio de TORNEAZO
  supabaseAnonKey:'sb_publishable_4cszRtaDQvAb5liivovoog_DdJYj1oD',  // clave pública (publishable): es pública por diseño
  turnstileSiteKey:'',     // opcional: captcha de Cloudflare Turnstile (recomendado en producción)
  proUrl:'https://buy.stripe.com/aFafZh2JSeM7g6WfAmcbC05',       // Premium mensual 2,99 €
  proUrlAnual:'https://buy.stripe.com/7sYaEXgAIeM7g6Wbk6cbC06',  // Premium anual 19,99 €
  portalUrl:'https://billing.stripe.com/p/login/00w4gz4S06fBaMC2NAcbC00',  // portal de cliente de Stripe (gestionar/cancelar)
  legalNombre:'Francisco Javier Casado García',
  legalNif:'15471491N',
  legalDir:'Granada, España',
  contactEmail:'javiadsense@gmail.com'
};
