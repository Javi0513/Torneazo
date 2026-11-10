// Configuración pública de TORNEAZO. Aquí NUNCA va la clave service_role ni ningún secreto.
window.APP_CONFIG={
  supabaseUrl:'https://qflfsqomewjxebvdhgfo.supabase.co',  // proyecto Supabase propio de TORNEAZO
  supabaseAnonKey:'sb_publishable_4cszRtaDQvAb5liivovoog_DdJYj1oD',  // clave pública (publishable): es pública por diseño
  turnstileSiteKey:'',     // opcional: captcha de Cloudflare Turnstile (recomendado en producción)
  proUrl:'',               // enlace de pago de Stripe (Payment Link) del plan Premium
  portalUrl:'',            // portal de cliente de Stripe (gestionar/cancelar)
  legalNombre:'Francisco Javier Casado García',
  legalNif:'15471491N',
  legalDir:'Granada, España',
  contactEmail:'javiadsense@gmail.com'
};
