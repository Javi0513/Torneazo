// Configuración pública de TORNEAZO. Aquí NUNCA va la clave service_role ni ningún secreto.
window.APP_CONFIG={
  supabaseUrl:'https://qflfsqomewjxebvdhgfo.supabase.co',  // proyecto Supabase propio de TORNEAZO
  supabaseAnonKey:'sb_publishable_4cszRtaDQvAb5liivovoog_DdJYj1oD',  // clave pública (publishable): es pública por diseño
  turnstileSiteKey:'',     // opcional: captcha de Cloudflare Turnstile (recomendado en producción)
  proUrl:'https://buy.stripe.com/aFafZh2JSeM7g6WfAmcbC05',       // Premium mensual 2,99 €
  proUrlAnual:'https://buy.stripe.com/7sYaEXgAIeM7g6Wbk6cbC06',  // Premium anual 19,99 €
  vapidPublicKey:'BNkON7SpuNyfKjmISkkJ9DrWaPkwvu1GLtWjX8Uo0Xrgtq_WiXkUOGnF8xxofAva_WaxXzumSatboK-Go3O0RKg',  // clave pública de los avisos al móvil (la privada solo está en Supabase)
  portalUrl:'https://billing.stripe.com/p/login/7sY6oH3NWavR3kaewicbC01',  // portal de cliente de Stripe (gestionar/cancelar)
  legalNombre:'Francisco Javier Casado García',
  legalNif:'15471491N',
  legalDir:'Granada, España',
  contactEmail:'javiadsense@gmail.com'
};
