# TORNEAZO · Seguridad

Ninguna app tiene "seguridad máxima" absoluta. Esto es lo que ya está hecho y lo que falta antes de abrirla al público.

## Ya hecho
- **Cuentas con Supabase Auth:** las contraseñas nunca pasan por nuestro código ni se guardan en la app; las gestiona Supabase (hash seguro). Confirmación de email al registrarse.
- **Reglas de acceso en el servidor (RLS):** cada usuario solo puede leer y editar sus propios torneos. Hecho en `supabase/migrations/20261110_torneazo_inicial.sql`.
- **Nadie puede darse Premium a sí mismo:** `is_premium` no es editable desde la app; solo lo cambiará el servidor de pagos.
- **Límites gratis aplicados en la base de datos** (3 torneos guardados, 32 participantes), no solo en pantalla.
- **Validación:** email y contraseña (10+ caracteres con letras y números), longitudes máximas en todos los campos, texto siempre escapado al mostrarlo (contra XSS).
- **Mensajes de error genéricos** al entrar ("email o contraseña incorrectos") para no revelar qué emails existen, y pausa de 3 s entre intentos.
- **Cabeceras de seguridad** (`vercel.json`): CSP, HSTS, anti-iframe, no-referrer, permisos del navegador cerrados.
- **Copiado de Mi Fútbol JV32 (ya probado en producción):** librería de Supabase en local (`supabase.js`, sin depender de un CDN), webhook de Stripe con firma HMAC y protección contra avisos desordenados (`supabase/functions/stripe-webhook`), aceptación de términos guardada en el perfil, captcha opcional (Cloudflare Turnstile), descargar mis datos, borrar mi cuenta (`borrar_mi_cuenta`), política de privacidad y página de borrado, instalación como app y modo sin conexión (`sw.js`, `manifest.webmanifest`).
- **Solo la clave pública** (`anon`) va en la app. La clave `service_role` nunca.

## Falta antes de publicar (en este orden)
1. Proyecto Supabase `torneazo` creado (UE, plan gratuito, 0 €) y primera migración aplicada. Falta aplicar `20261111_torneazo_pagos_y_cuenta.sql`.
2. `config.js` ya tiene la URL y la clave pública del proyecto.
3. En Supabase → Authentication: activar confirmación de email, protección contra contraseñas filtradas y límites de intentos; restringir las URLs de redirección al dominio real. Crear el sitio Turnstile y poner `turnstileSiteKey`.
4. Stripe: crear el Payment Link de Premium (`proUrl`), el portal de cliente (`portalUrl`) y desplegar `stripe-webhook` con "Verify JWT" desactivado y el secreto `STRIPE_WEBHOOK_SECRET`.
5. Quitar `'unsafe-inline'` del CSP: hay que mover los `onclick` a un archivo JS propio (Mi Fútbol ya lo tiene así).
6. Pasar `get_advisors` de Supabase y una prueba de intrusión básica antes del lanzamiento. Revisar el texto legal con un profesional.
