-- ============================================================
-- TableFinder — 0002 : schéma applicatif
--
-- Portage Supabase -> Neon. Deux différences :
--   * les extensions vivent dans `public` (Neon n'a pas de schéma
--     `extensions` dédié comme Supabase) ;
--   * `owner_id` est un `text` et non un `uuid`, parce que Better
--     Auth génère des identifiants texte.
-- ============================================================

create extension if not exists unaccent;
create extension if not exists pg_trgm;

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

-- unaccent() est STABLE, pas IMMUTABLE : Postgres refuse donc de
-- l'utiliser dans une colonne générée. On l'enveloppe en fixant
-- explicitement le dictionnaire, ce qui la rend déterministe.
create or replace function public.immutable_unaccent(text)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select public.unaccent('public.unaccent'::regdictionary, $1)
$$;

-- Normalisation utilisée partout pour la recherche :
-- "Élie  MUKUNA " -> "elie mukuna"
create or replace function public.normalize_name(text)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select public.immutable_unaccent(lower(btrim(regexp_replace($1, '\s+', ' ', 'g'))))
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- events
-- ------------------------------------------------------------

create table public.events (
  id            uuid primary key default gen_random_uuid(),
  owner_id      text not null references public.users(id) on delete cascade,

  name          text not null check (btrim(name) <> '' and length(name) <= 120),
  event_date    date,
  description   text check (description is null or length(description) <= 2000),

  -- suffixe aléatoire ajouté côté application : "mariage-elie-sarah-k4f9"
  slug          text not null unique
                  check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 6 and 80),

  is_published  boolean not null default true,

  -- Personnalisation QR (Phase 9)
  qr_foreground text not null default '#000000' check (qr_foreground ~* '^#[0-9a-f]{6}$'),
  qr_background text not null default '#FFFFFF' check (qr_background ~* '^#[0-9a-f]{6}$'),
  qr_caption    text check (qr_caption is null or length(qr_caption) <= 60),
  qr_logo_key   text,   -- clé d'objet Cloudflare R2, pas une URL

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index events_owner_id_idx on public.events (owner_id, created_at desc);
create index events_slug_published_idx on public.events (slug) where is_published;

create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- event_tables
-- (nommée ainsi et non "tables" pour éviter la collision de
--  vocabulaire avec information_schema.tables)
-- ------------------------------------------------------------

create table public.event_tables (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,

  table_number integer not null check (table_number between 1 and 9999),
  name         text check (name is null or length(name) <= 60),
  capacity     integer not null default 10 check (capacity between 1 and 100),

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint event_tables_unique_number unique (event_id, table_number),
  -- cible requise par la clé étrangère composite de guests
  constraint event_tables_id_event_key unique (id, event_id)
);

create index event_tables_event_id_idx on public.event_tables (event_id, table_number);

create trigger event_tables_set_updated_at
  before update on public.event_tables
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- guests
-- ------------------------------------------------------------

create table public.guests (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  table_id    uuid,

  first_name  text not null check (length(btrim(first_name)) <= 80),
  last_name   text not null check (length(btrim(last_name))  <= 80),

  -- Colonne générée : accents et casse neutralisés une seule fois,
  -- à l'écriture. "Élie Mukuna" -> "elie mukuna"
  search_name text generated always as
                (public.normalize_name(first_name || ' ' || last_name)) stored,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  check (btrim(first_name) <> '' or btrim(last_name) <> ''),

  -- Empêche au niveau base d'assigner un invité à la table d'un
  -- AUTRE événement, même si une Server Action est boguée ou si un
  -- identifiant est manipulé dans la requête.
  -- ON DELETE SET NULL (table_id) : liste de colonnes requise, sinon
  -- Postgres tenterait aussi de mettre event_id à NULL.
  -- Nécessite PostgreSQL 15+ (Neon : PG 17/18 par défaut).
  constraint guests_table_same_event_fkey
    foreign key (table_id, event_id)
    references public.event_tables (id, event_id)
    on delete set null (table_id)
);

create index guests_event_id_idx on public.guests (event_id, search_name);
create index guests_table_id_idx on public.guests (table_id) where table_id is not null;

-- Recherche "contient" rapide : LIKE '%elie%' passe par cet index.
create index guests_search_name_trgm_idx
  on public.guests using gin (search_name gin_trgm_ops);

create trigger guests_set_updated_at
  before update on public.guests
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- Vue : tables + taux de remplissage (Phase 3 / Phase 10)
-- security_invoker => la RLS de l'appelant s'applique bien.
-- ------------------------------------------------------------

create view public.event_tables_with_counts
with (security_invoker = on) as
select
  t.id,
  t.event_id,
  t.table_number,
  t.name,
  t.capacity,
  count(g.id)::int as guest_count,
  greatest(t.capacity - count(g.id), 0)::int as seats_left,
  (count(g.id) > t.capacity) as is_overbooked
from public.event_tables t
left join public.guests g on g.table_id = t.id
group by t.id;

