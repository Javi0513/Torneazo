# TORNEAZO · by JAVI AI

Sorteos y torneos de videojuegos desde el móvil: grupos al azar, partidos cruzados entre grupos, siguiente fase a tu gusto y eliminatoria.

🌐 torneazo.monetizaplus.com

Web estática (HTML, CSS y JavaScript puro, instalable como app) con [Supabase](https://supabase.com) para cuentas y base de datos, con seguridad por filas (RLS).

```
index.html            La app
config.js             Configuración PÚBLICA (URL y clave pública de Supabase)
supabase.js           Librería de Supabase en local
sw.js, manifest       Instalación como app y modo sin conexión
privacidad.html       Política de privacidad
borrar-datos.html     Cómo borrar la cuenta
supabase/migrations   Tablas, reglas de seguridad y límites del plan gratis
supabase/functions    Webhook de Stripe (plan Premium)
SEGURIDAD.md          Qué está protegido y qué falta
```

Nunca se suben claves secretas (`service_role`, secreto de Stripe): viven solo en Supabase y Stripe.
