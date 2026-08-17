\set ON_ERROR_STOP on
\pset pager off

-- Toutes les assertions ci-dessous tournent sous le rôle
-- `tablefinder_app` — celui que l'application utilise réellement —
-- et non sous le propriétaire, qui contourne la RLS.

\echo '--- 12. Sans app.user_id, la requete ECHOUE (pas de silence)'
begin;
  set local role tablefinder_app;
  do $$
  begin
    perform 1 from public.events limit 1;
    raise exception 'ECHEC : requete acceptee sans app.user_id';
  exception
    when insufficient_privilege then
      raise notice 'OK : % ', sqlerrm;
  end $$;
rollback;

\echo '--- 13. RLS : l organisateur B ne voit pas les donnees de A'
begin;
  set local role tablefinder_app;
  set local app.user_id = 'usr_intrus';
  select assert_eq(
    (select count(*) from public.guests
       where event_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    0::bigint, 'RLS isole les invites entre organisateurs');
  select assert_eq(
    (select count(*) from public.events), 1::bigint,
    'RLS : B ne voit que son propre evenement');
rollback;

\echo '--- 14. RLS : B ne peut pas s attribuer l evenement de A'
begin;
  set local role tablefinder_app;
  set local app.user_id = 'usr_intrus';
  select assert_eq(
    (select count(*) from public.events
       where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    0::bigint, 'UPDATE cible zero ligne chez B');
rollback;

\echo '--- 15. RLS : B ne peut pas importer dans l evenement de A'
begin;
  set local role tablefinder_app;
  set local app.user_id = 'usr_intrus';
  do $$
  begin
    perform public.import_guests(
      'aaaaaaaa-0000-0000-0000-000000000001',
      '[{"first_name":"Pirate","last_name":"Doe","table_number":12}]'::jsonb,
      true);
    raise exception 'ECHEC : import inter-comptes accepte';
  exception
    when sqlstate 'P0001' then
      if sqlerrm like 'ECHEC%' then raise; end if;
      raise notice 'OK : import bloque (%)', sqlerrm;
  end $$;
rollback;

\echo '--- 16. Import : tables manquantes signalees, AUCUNE insertion'
begin;
  set local role tablefinder_app;
  set local app.user_id = 'usr_gaston';

  select assert_eq(
    public.import_guests(
      'aaaaaaaa-0000-0000-0000-000000000001',
      '[{"first_name":"Marie","last_name":"Kabeya","table_number":30},
        {"first_name":"Paul","last_name":"Ngoy","table_number":31},
        {"first_name":"Ana","last_name":"Lopez","table_number":12}]'::jsonb,
      false),
    '{"status":"missing_tables","missing_tables":[30,31],"inserted":0}'::jsonb,
    'import signale les tables manquantes sans rien inserer');

  select assert_eq(
    (select count(*) from public.guests
       where event_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
    3::bigint, 'aucun invite ajoute lors du refus');
rollback;

\echo '--- 17. Import : confirmation "creer les tables manquantes"'
begin;
  set local role tablefinder_app;
  set local app.user_id = 'usr_gaston';

  select assert_eq(
    public.import_guests(
      'aaaaaaaa-0000-0000-0000-000000000001',
      '[{"first_name":"Marie","last_name":"Kabeya","table_number":30},
        {"first_name":"Paul","last_name":"Ngoy","table_number":31},
        {"first_name":"Ana","last_name":"Lopez","table_number":12},
        {"first_name":"Sans","last_name":"Table","table_number":null},
        {"first_name":"","last_name":"","table_number":12}]'::jsonb,
      true, 8),
    '{"status":"ok","inserted":4,"skipped":1,"created_tables":2}'::jsonb,
    'import cree les tables 30 et 31 et insere 4 invites');

  select assert_eq(
    (select capacity from public.event_tables
       where event_id = 'aaaaaaaa-0000-0000-0000-000000000001'
         and table_number = 30),
    8, 'capacite par defaut appliquee aux tables creees');

  select assert_eq(
    (select count(*) from public.guests
       where event_id = 'aaaaaaaa-0000-0000-0000-000000000001'
         and table_id is null),
    1::bigint, 'invite sans table conserve');

  -- La recherche publique doit voir les nouveaux invités
  select assert_eq(
    (select count(*) from public.search_event_guests(
       'mariage-elie-sarah-k4f9', 'kabeya')),
    1::bigint, 'recherche publique utilisable par le role applicatif');
rollback;

\echo '--- 18. Import : garde-fou sur le volume'
begin;
  set local role tablefinder_app;
  set local app.user_id = 'usr_gaston';
  do $$
  declare v_big jsonb;
  begin
    select jsonb_agg(jsonb_build_object(
             'first_name','A','last_name','B','table_number',12))
      into v_big from generate_series(1, 2001);
    perform public.import_guests(
      'aaaaaaaa-0000-0000-0000-000000000001', v_big, true);
    raise exception 'ECHEC : limite de lignes non appliquee';
  exception
    when sqlstate 'P0001' then
      if sqlerrm like 'ECHEC%' then raise; end if;
      raise notice 'OK : %', sqlerrm;
  end $$;
rollback;

\echo '--- 19. Le role applicatif ne peut pas modifier le schema'
begin;
  set local role tablefinder_app;
  do $$
  begin
    execute 'alter table public.guests disable row level security';
    raise exception 'ECHEC : le role applicatif peut desactiver la RLS';
  exception
    when insufficient_privilege then
      raise notice 'OK : desactivation de la RLS refusee';
  end $$;
rollback;

\echo '--- 20. get_public_qr_settings expose les couleurs pour un evenement publie'
select assert_eq(
  (select qr_foreground from public.get_public_qr_settings('mariage-elie-sarah-k4f9')),
  '#000000'::text, 'couleurs QR exposees publiquement');

\echo '--- 21. get_public_qr_settings muet pour un evenement depublie'
begin;
  update public.events set is_published = false where slug = 'mariage-elie-sarah-k4f9';
  select assert_eq(
    (select count(*) from public.get_public_qr_settings('mariage-elie-sarah-k4f9')),
    0::bigint, 'reglages QR masques si evenement depublie');
rollback;

