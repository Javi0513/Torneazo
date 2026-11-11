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

## Página pública de un torneo
- El dueño publica poniendo un código al azar (12 caracteres) en su torneo; sin código, nadie lo ve. Cualquiera con el enlace puede ver **solo ese torneo** (nombres, resultados, premios e información) con la función `ver_torneo` y solo en lectura: no puede escribir nada.
- El navegador de quien mira escapa todo el texto y valida enlaces (solo `http`/`https`), colores e imágenes, para que un torneo mal intencionado no pueda ejecutar código.
- Supabase marca `ver_torneo` como «ejecutable por usuarios anónimos»: es intencionado, es lo que permite ver la página sin cuenta.

## Inscripciones con enlace
- Los jugadores se apuntan **sin cuenta** solo a través de la función `inscribirse()`; no hay acceso directo a la tabla. La función comprueba el enlace, que las inscripciones estén abiertas, la fecha límite, el cupo, que no haya nombres repetidos y limita los intentos (5 por hora y dispositivo, 30 por minuto en el torneo).
- Solo el dueño del torneo puede **ver, aprobar, rechazar o borrar** las inscripciones de sus torneos (reglas de acceso por fila). La página pública solo enseña **cuántos** hay, nunca los nombres ni los contactos.
- Los datos del jugador (nombre y, si se piden, contacto y nivel) se tratan como no fiables: se escapan al mostrarlos y se limpian los símbolos especiales al pasarlos a la lista de participantes.
- Revisado en una transacción de prueba (sin dejar datos): éxito, duplicado, cupo lleno, enlace inválido, cerradas, plazo vencido, aprobación automática, nombre vacío o demasiado largo y datos de configuración raros.

## Falta antes de publicar (en este orden)
1. Proyecto Supabase `torneazo` creado (UE, plan gratuito, 0 €) y primera migración aplicada. Falta aplicar `20261111_torneazo_pagos_y_cuenta.sql`.
2. `config.js` ya tiene la URL y la clave pública del proyecto.
3. En Supabase → Authentication: activar confirmación de email, protección contra contraseñas filtradas y límites de intentos; restringir las URLs de redirección al dominio real. Crear el sitio Turnstile y poner `turnstileSiteKey`.
4. Stripe: crear el Payment Link de Premium (`proUrl`), el portal de cliente (`portalUrl`) y desplegar `stripe-webhook` con "Verify JWT" desactivado y el secreto `STRIPE_WEBHOOK_SECRET`.
5. ~~Quitar `'unsafe-inline'` del CSP~~ Hecho: el código está en `app.js`, los eventos usan `data-click` y la CSP solo admite scripts propios (`script-src 'self'`). Queda `style-src 'unsafe-inline'` porque la app usa estilos dentro de los elementos.
6. Pasar `get_advisors` de Supabase y una prueba de intrusión básica antes del lanzamiento. Revisar el texto legal con un profesional.
