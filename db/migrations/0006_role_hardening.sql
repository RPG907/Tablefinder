-- ============================================================
-- TableFinder — 0006 : recréation sûre du rôle applicatif
--
-- PIÈGE NEON : un rôle créé via la console, le CLI ou l'API
-- (`Roles -> New Role`, ce que demandait jusqu'ici ce projet) hérite
-- par défaut de BYPASSRLS, CREATEDB et CREATEROLE — les mêmes
-- attributs que le rôle propriétaire du projet. Rien dans l'UI ni la
-- CLI ne prévient de ça.
--
-- BYPASSRLS est le plus grave des trois : avec cet attribut,
-- `tablefinder_app` ignore purement et simplement les policies de la
-- migration 0003. La RLS n'est alors plus un filet de sécurité, elle
-- n'existe plus du tout pour ce rôle — un `WHERE owner_id` oublié
-- dans repositories/ fuiterait TOUTES les lignes, pas zéro.
--
-- Un rôle créé en SQL pur (par un rôle qui a CREATEROLE, comme
-- `neondb_owner`) reçoit en revanche les attributs par défaut
-- normaux de Postgres : NOBYPASSRLS, NOCREATEDB, NOCREATEROLE. D'où
-- cette migration, qui recrée le rôle en SQL plutôt que de se fier à
-- une création manuelle côté console.
--
-- IMPORTANT — si `tablefinder_app` existe déjà avec les attributs
-- élevés (créé via la console/CLI/API, comme le recommandait
-- jusqu'ici le README), cette migration NE PEUT PAS le corriger
-- elle-même : Neon interdit à `neondb_owner` d'altérer ou de
-- supprimer en SQL un rôle géré par son plan de contrôle, même avec
-- CREATEROLE (« permission denied to drop objects / to alter role »).
-- Il faut d'abord le supprimer par ce même canal : console Neon, ou
-- `neon roles delete tablefinder_app`. Cette migration s'en assure et
-- lève une erreur explicite sinon plutôt que de continuer en silence
-- avec un rôle toujours trop privilégié.
-- ============================================================

do $$
begin
  if exists (
    select 1 from pg_roles
    where rolname = 'tablefinder_app'
      and (rolbypassrls or rolcreatedb or rolcreaterole)
  ) then
    raise exception using
      errcode = '55006',
      message = 'Le rôle "tablefinder_app" existe déjà avec des attributs élevés (BYPASSRLS/CREATEDB/CREATEROLE).',
      hint    = 'Supprimez-le via la console Neon ou `neon roles delete tablefinder_app --project-id ... --branch ...`, puis relancez cette migration : elle le recrée en SQL pur, ce qui produit des attributs sûrs par défaut sur Neon.';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'tablefinder_app') then
    -- Mot de passe de démarrage : à faire tourner immédiatement après
    -- coup (ALTER ROLE tablefinder_app PASSWORD '...') plutôt que de
    -- garder celui-ci, qui est désormais visible dans l'historique
    -- des migrations.
    create role tablefinder_app login password 'ZAw737QYz@TRMTpjYbQ&qUYa';
  end if;
end $$;

-- ------------------------------------------------------------
-- Reprise des concessions de 0003/0004/0005 : si le rôle vient
-- d'être recréé ci-dessus, c'est un objet neuf sans aucun des
-- privilèges déjà accordés à l'ancien.
-- ------------------------------------------------------------

grant usage on schema public to tablefinder_app;

grant select, insert, update, delete
  on public.users, public.sessions, public.accounts, public.verifications
  to tablefinder_app;

grant select, insert, update, delete
  on public.events, public.event_tables, public.guests
  to tablefinder_app;
grant select on public.event_tables_with_counts to tablefinder_app;

drop policy if exists events_owner_all on public.events;
create policy events_owner_all
  on public.events for all
  to tablefinder_app
  using      (owner_id = public.current_app_user())
  with check (owner_id = public.current_app_user());

drop policy if exists event_tables_owner_all on public.event_tables;
create policy event_tables_owner_all
  on public.event_tables for all
  to tablefinder_app
  using (exists (
    select 1 from public.events e
    where e.id = event_tables.event_id
      and e.owner_id = public.current_app_user()
  ))
  with check (exists (
    select 1 from public.events e
    where e.id = event_tables.event_id
      and e.owner_id = public.current_app_user()
  ));

drop policy if exists guests_owner_all on public.guests;
create policy guests_owner_all
  on public.guests for all
  to tablefinder_app
  using (exists (
    select 1 from public.events e
    where e.id = guests.event_id
      and e.owner_id = public.current_app_user()
  ))
  with check (exists (
    select 1 from public.events e
    where e.id = guests.event_id
      and e.owner_id = public.current_app_user()
  ));

grant execute on function public.get_public_event(text)          to tablefinder_app;
grant execute on function public.search_event_guests(text, text) to tablefinder_app;
grant execute on function public.import_guests(uuid, jsonb, boolean, integer) to tablefinder_app;
grant execute on function public.get_public_qr_settings(text)    to tablefinder_app;
