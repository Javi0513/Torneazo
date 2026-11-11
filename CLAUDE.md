# Instrucciones para Claude en este repositorio (TORNEAZO)

- **Flujo de trabajo:** cada cambio se hace en una rama y se abre una pull request (PR) hacia `main`. No se fusiona nada sin que Javi lo pida ("fusiónala"). `main` se publica solo en https://torneazo.monetizaplus.com (GitHub Pages).
- **Versión y novedades (obligatorio en cada cambio visible para el usuario):**
  1. Sube `APP_VERSION` en `index.html`.
  2. Añade una entrada al principio de `historial` en `version.json` (y pon su `version` arriba), con frases cortas y sencillas en español.
  3. Pon la misma versión en `VERSION` de `sw.js`.
  Con eso, a los usuarios les sale el aviso «Hay una versión nueva» y, al actualizar, la ventana de novedades.
- **Seguridad:** nunca subir claves secretas (`service_role`, secreto de Stripe). `config.js` solo lleva la URL y la clave pública de Supabase. Las reglas de acceso están en `supabase/migrations`.
- **Base de datos:** proyecto Supabase `torneazo` (id `qflfsqomewjxebvdhgfo`, UE). No usar el proyecto `mi-futbol-cliente`, que es de otra app.
- **Marca:** JAVI AI. Negro `#070807`, verde lima `#9BEA1C`, títulos en Exo 2 cursiva. Sin emojis en la interfaz.
- Hablar con Javi en español sencillo y avisarle de cualquier coste antes de crear recursos de pago.
