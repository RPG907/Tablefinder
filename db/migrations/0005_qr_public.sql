-- ============================================================
-- TableFinder — 0005 : API publique pour le rendu du QR Code
--
-- get_public_event() (migration 0004) n'expose pas les couleurs ni
-- la clé de logo : elles ne servaient à rien à la page /e/[slug].
-- La route /api/qr/[slug], elle, en a besoin pour générer l'image —
-- d'où cette fonction dédiée plutôt qu'un élargissement de 0004
-- (migration déjà potentiellement appliquée, on n'y touche pas).
-- ============================================================

create or replace function public.get_public_qr_settings(p_slug text)
returns table (
  qr_foreground text,
  qr_background text,
  qr_logo_key   text
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.qr_foreground, e.qr_background, e.qr_logo_key
  from public.events e
  where e.slug = p_slug
    and e.is_published
  limit 1;
$$;

revoke all on function public.get_public_qr_settings(text) from public;
grant execute on function public.get_public_qr_settings(text) to tablefinder_app;
