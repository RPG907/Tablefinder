-- ============================================================
-- TableFinder — 0004 : API publique + import CSV
--
-- Ces fonctions appartiennent au rôle propriétaire (celui qui joue
-- les migrations, `neondb_owner` sur Neon). En SECURITY DEFINER
-- elles contournent donc la RLS — c'est voulu : la page publique
-- n'a pas de session, `app.user_id` n'est pas posé, et
-- current_app_user() lèverait une erreur.
-- ============================================================

-- ------------------------------------------------------------
-- get_public_event(slug)
-- Seul point d'entrée de la page /e/[slug] pour l'en-tête.
-- N'expose jamais l'UUID de l'événement ni son propriétaire.
-- ------------------------------------------------------------

create or replace function public.get_public_event(p_slug text)
returns table (
  slug        text,
  name        text,
  event_date  date,
  description text,
  qr_caption  text
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.slug, e.name, e.event_date, e.description, e.qr_caption
  from public.events e
  where e.slug = p_slug
    and e.is_published
  limit 1;
$$;

-- ------------------------------------------------------------
-- search_event_guests(slug, query)
--
-- Garde-fous :
--   * 2 caractères minimum (empêche de vider la liste avec "a")
--   * échappement des jokers LIKE (% et _)
--   * 10 résultats maximum
--   * cloisonnée à l'événement du slug fourni
--
-- NOTE : ceci ne suffit pas contre une énumération alphabétique
-- systématique. Ajouter un rate limit en amont (proxy.ts + Upstash)
-- avant toute mise en production réelle.
-- ------------------------------------------------------------

create or replace function public.search_event_guests(p_slug text, p_query text)
returns table (
  guest_id     uuid,
  first_name   text,
  last_name    text,
  table_number integer,
  table_name   text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_needle   text;
begin
  v_needle := public.normalize_name(coalesce(p_query, ''));

  if v_needle is null or length(v_needle) < 2 then
    return;
  end if;

  if length(v_needle) > 80 then
    v_needle := left(v_needle, 80);
  end if;

  -- neutralise les jokers : sans ça, "%" retournerait toute la liste
  v_needle := replace(replace(replace(v_needle, '\', '\\'), '%', '\%'), '_', '\_');

  select e.id into v_event_id
  from public.events e
  where e.slug = p_slug and e.is_published;

  if v_event_id is null then
    return;
  end if;

  return query
  select
    g.id,
    g.first_name,
    g.last_name,
    t.table_number,
    t.name
  from public.guests g
  left join public.event_tables t on t.id = g.table_id
  where g.event_id = v_event_id
    and g.search_name like '%' || v_needle || '%' escape '\'
  order by
    -- les correspondances en début de nom d'abord
    case when g.search_name like v_needle || '%' escape '\' then 0 else 1 end,
    g.search_name
  limit 10;
end;
$$;

revoke all on function public.get_public_event(text)          from public;
revoke all on function public.search_event_guests(text, text) from public;
grant execute on function public.get_public_event(text)          to tablefinder_app;
grant execute on function public.search_event_guests(text, text) to tablefinder_app;

-- ------------------------------------------------------------
-- import_guests(event_id, rows, create_missing_tables)
--
-- SECURITY INVOKER : la RLS s'applique, donc un organisateur ne
-- peut importer que dans ses propres événements — aucune
-- vérification de propriété à écrire à la main.
--
-- Atomique : soit tout passe, soit rien.
--
-- p_rows attendu :
--   [{"first_name":"Elie","last_name":"Mukuna","table_number":12}, ...]
--   table_number peut être null (invité non assigné).
--
-- Si des numéros de table manquent et que p_create_missing_tables
-- est false, la fonction n'insère RIEN et renvoie la liste
-- manquante — c'est ce que l'aperçu affiche avec le bouton
-- « Créer les tables manquantes ».
-- ------------------------------------------------------------

create or replace function public.import_guests(
  p_event_id              uuid,
  p_rows                  jsonb,
  p_create_missing_tables boolean default false,
  p_default_capacity      integer default 10
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row_count      integer;
  v_missing        integer[];
  v_created_tables integer := 0;
  v_inserted       integer := 0;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Format invalide : un tableau JSON est attendu';
  end if;

  v_row_count := jsonb_array_length(p_rows);

  if v_row_count = 0 then
    return jsonb_build_object('status', 'empty', 'inserted', 0);
  end if;

  if v_row_count > 2000 then
    raise exception 'Trop de lignes : % (maximum 2000)', v_row_count;
  end if;

  -- RLS : ne renvoie rien si l'événement n'appartient pas à l'appelant
  if not exists (select 1 from public.events e where e.id = p_event_id) then
    raise exception 'Événement introuvable ou accès refusé';
  end if;

  -- Numéros de table référencés mais inexistants
  select coalesce(array_agg(distinct r.table_number order by r.table_number), '{}')
  into v_missing
  from jsonb_to_recordset(p_rows)
    as r(first_name text, last_name text, table_number integer)
  where r.table_number is not null
    and not exists (
      select 1 from public.event_tables t
      where t.event_id = p_event_id
        and t.table_number = r.table_number
    );

  if array_length(v_missing, 1) is not null and not p_create_missing_tables then
    return jsonb_build_object(
      'status',         'missing_tables',
      'missing_tables', to_jsonb(v_missing),
      'inserted',       0
    );
  end if;

  if array_length(v_missing, 1) is not null then
    insert into public.event_tables (event_id, table_number, capacity)
    select p_event_id, m, greatest(p_default_capacity, 1)
    from unnest(v_missing) as m
    on conflict (event_id, table_number) do nothing;

    get diagnostics v_created_tables = row_count;
  end if;

  insert into public.guests (event_id, first_name, last_name, table_id)
  select
    p_event_id,
    left(btrim(coalesce(r.first_name, '')), 80),
    left(btrim(coalesce(r.last_name,  '')), 80),
    t.id
  from jsonb_to_recordset(p_rows)
    as r(first_name text, last_name text, table_number integer)
  left join public.event_tables t
    on t.event_id = p_event_id
   and t.table_number = r.table_number
  where btrim(coalesce(r.first_name, '')) <> ''
     or btrim(coalesce(r.last_name,  '')) <> '';

  get diagnostics v_inserted = row_count;

  return jsonb_build_object(
    'status',         'ok',
    'inserted',       v_inserted,
    'created_tables', v_created_tables,
    'skipped',        v_row_count - v_inserted
  );
end;
$$;

revoke all on function public.import_guests(uuid, jsonb, boolean, integer) from public;
grant execute on function public.import_guests(uuid, jsonb, boolean, integer) to tablefinder_app;

