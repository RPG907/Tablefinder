\set ON_ERROR_STOP on
\pset pager off

-- ============================================================
-- Jeu de données (joué par le propriétaire : RLS contournée)
-- ============================================================

insert into "users" (id, name, email, "emailVerified") values
  ('usr_gaston', 'Gaston', 'gaston@example.com', true),
  ('usr_intrus', 'Intrus', 'intrus@example.com', true);

insert into public.events (id, owner_id, name, event_date, slug) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'usr_gaston',
   'Mariage Élie & Sarah', '2026-08-15', 'mariage-elie-sarah-k4f9'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'usr_intrus',
   'Gala privé', '2026-09-01', 'gala-prive-z7x2');

insert into public.event_tables (id, event_id, table_number, capacity) values
  ('cccccccc-0000-0000-0000-000000000012',
   'aaaaaaaa-0000-0000-0000-000000000001', 12, 10),
  ('cccccccc-0000-0000-0000-000000000008',
   'aaaaaaaa-0000-0000-0000-000000000001',  8, 10),
  ('dddddddd-0000-0000-0000-000000000099',
   'bbbbbbbb-0000-0000-0000-000000000002', 99, 10);

insert into public.guests (event_id, table_id, first_name, last_name) values
  ('aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000012', 'Élie',     'Mukuna'),
  ('aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000008', 'Sarah',    'Smith'),
  ('aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000012', 'François', 'Tremblay'),
  ('bbbbbbbb-0000-0000-0000-000000000002',
   'dddddddd-0000-0000-0000-000000000099', 'Élie',     'Secret');

-- ============================================================
-- Recherche
-- ============================================================

\echo '--- 1. Recherche sans accent : "elie" doit trouver "Élie"'
select assert_eq(
  (select count(*) from public.search_event_guests('mariage-elie-sarah-k4f9', 'elie')),
  1::bigint, 'recherche insensible aux accents');

\echo '--- 2. "FRANCOIS" doit trouver "François"'
select assert_eq(
  (select count(*) from public.search_event_guests('mariage-elie-sarah-k4f9', 'FRANCOIS')),
  1::bigint, 'recherche insensible accents + casse');

\echo '--- 3. Cloisonnement : pas de fuite depuis l autre evenement'
select assert_eq(
  (select coalesce(string_agg(last_name, ','), '')
     from public.search_event_guests('mariage-elie-sarah-k4f9', 'elie')),
  'Mukuna'::text, 'pas de fuite inter-evenements');

\echo '--- 4. Joker LIKE neutralise : "%" ne doit rien retourner'
select assert_eq(
  (select count(*) from public.search_event_guests('mariage-elie-sarah-k4f9', '%%')),
  0::bigint, 'echappement des jokers LIKE');

\echo '--- 5. Minimum 2 caracteres'
select assert_eq(
  (select count(*) from public.search_event_guests('mariage-elie-sarah-k4f9', 'e')),
  0::bigint, 'minimum 2 caracteres');

\echo '--- 6. Slug inconnu -> aucun resultat'
select assert_eq(
  (select count(*) from public.search_event_guests('slug-inexistant-0000', 'elie')),
  0::bigint, 'slug inconnu');

\echo '--- 7. Evenement depublie -> page publique muette'
update public.events set is_published = false where slug = 'mariage-elie-sarah-k4f9';
select assert_eq(
  (select count(*) from public.get_public_event('mariage-elie-sarah-k4f9')),
  0::bigint, 'evenement depublie masque');
update public.events set is_published = true where slug = 'mariage-elie-sarah-k4f9';

-- ============================================================
-- Intégrité
-- ============================================================

\echo '--- 8. FK composite : assignation a la table d un AUTRE evenement refusee'
do $$
begin
  update public.guests
    set table_id = 'dddddddd-0000-0000-0000-000000000099'
    where last_name = 'Mukuna';
  raise exception 'ECHEC : assignation inter-evenements acceptee';
exception
  when foreign_key_violation then
    raise notice 'OK : FK composite bloque l assignation inter-evenements';
end $$;

\echo '--- 9. ON DELETE SET NULL (table_id) : event_id survit'
insert into public.event_tables (id, event_id, table_number, capacity)
  values ('cccccccc-0000-0000-0000-000000000077',
          'aaaaaaaa-0000-0000-0000-000000000001', 77, 4);
insert into public.guests (event_id, table_id, first_name, last_name)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'cccccccc-0000-0000-0000-000000000077', 'Jean', 'Test');
delete from public.event_tables where table_number = 77;
select assert_eq(
  (select count(*) from public.guests
     where last_name = 'Test' and table_id is null
       and event_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1::bigint, 'suppression table -> invite desassigne, event_id intact');
delete from public.guests where last_name = 'Test';

\echo '--- 10. Vue de remplissage'
select assert_eq(
  (select guest_count from public.event_tables_with_counts
     where id = 'cccccccc-0000-0000-0000-000000000012'),
  2, 'comptage des invites par table');

\echo '--- 11. Suppression du compte -> evenements supprimes en cascade'
begin;
  delete from "users" where id = 'usr_intrus';
  select assert_eq(
    (select count(*) from public.events where slug = 'gala-prive-z7x2'),
    0::bigint, 'cascade users -> events');
rollback;

