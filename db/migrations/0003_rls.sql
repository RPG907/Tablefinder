-- ============================================================
-- TableFinder — 0003 : rôle applicatif + RLS
--
-- CE QUI CHANGE PAR RAPPORT À SUPABASE
--
-- Avec Supabase, le navigateur parlait directement à Postgres via
-- PostgREST : la RLS était la SEULE barrière. Ici le navigateur ne
-- voit jamais la base — tout passe par les Server Actions. La
-- barrière principale devient donc le code applicatif
-- (repositories/), et la RLS passe en défense en profondeur : elle
-- rattrape un WHERE oublié, elle ne le remplace pas.
--
-- Mécanique : l'application se connecte avec le rôle
-- `tablefinder_app` (non propriétaire, donc soumis à la RLS) et
-- pose `app.user_id` en début de transaction. Voir withUser()
-- dans db/client.ts.
-- ============================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'tablefinder_app') then
    raise exception using
      errcode = '42704',
      message = 'Rôle "tablefinder_app" absent.',
      hint    = 'Créez-le dans la console Neon (Roles -> New Role), puis relancez la migration. Voir db/README.md.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Identité courante
--
-- Lève une erreur si le GUC n'est pas posé, plutôt que de renvoyer
-- NULL. Sans ça, oublier withUser() donnerait zéro ligne en
-- silence — un bug bien plus pénible à diagnostiquer qu'un plantage.
-- ------------------------------------------------------------

create or replace function public.current_app_user()
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v text;
begin
  v := nullif(current_setting('app.user_id', true), '');
  if v is null then
    raise exception using
      errcode = '42501',
      message = 'app.user_id non défini',
      hint    = 'Cette requête tourne hors du wrapper withUser(). Voir db/client.ts.';
  end if;
  return v;
end;
$$;

-- ------------------------------------------------------------
-- Privilèges
-- ------------------------------------------------------------

grant usage on schema public to tablefinder_app;

-- Tables Better Auth : pas de RLS (l'auth doit lire un utilisateur
-- par email avant qu'une session existe).
grant select, insert, update, delete
  on public.users, public.sessions, public.accounts, public.verifications
  to tablefinder_app;

-- Tables applicatives : privilèges accordés, la RLS tranche ensuite
-- ligne par ligne.
grant select, insert, update, delete
  on public.events, public.event_tables, public.guests
  to tablefinder_app;
grant select on public.event_tables_with_counts to tablefinder_app;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------

alter table public.events       enable row level security;
alter table public.event_tables enable row level security;
alter table public.guests       enable row level security;

-- events
create policy events_owner_all
  on public.events for all
  to tablefinder_app
  using      (owner_id = public.current_app_user())
  with check (owner_id = public.current_app_user());

-- event_tables — héritent du propriétaire de l'événement
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

-- guests
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

