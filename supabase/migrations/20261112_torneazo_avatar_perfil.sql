-- TORNEAZO · foto de perfil. La app reduce la imagen a 160x160 y la guarda como texto (data URL).
alter table public.profiles add column if not exists avatar text;
alter table public.profiles drop constraint if exists profiles_avatar_valido;
alter table public.profiles add constraint profiles_avatar_valido
  check (avatar is null or (char_length(avatar) <= 40000 and avatar ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$'));
-- Cada usuario solo puede cambiar su apodo y su foto (nunca is_premium ni los datos de pago).
grant update (display_name, avatar) on public.profiles to authenticated;
