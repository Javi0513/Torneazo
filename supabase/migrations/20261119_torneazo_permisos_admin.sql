-- TORNEAZO · las funciones de moderación y de borrar cuenta no las puede llamar nadie sin cuenta.
-- (Ya comprobaban dentro que el usuario es administrador o está identificado; esto es una capa más.)
revoke execute on function public.moderar(text, boolean) from anon, public;
revoke execute on function public.moderacion_lista() from anon, public;
revoke execute on function public.borrar_mi_cuenta() from anon, public;
