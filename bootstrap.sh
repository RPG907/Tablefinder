#!/usr/bin/env bash
# ============================================================
# TableFinder — bootstrap
#
#   mkdir tablefinder && cd tablefinder
#   bash ../bootstrap.sh
#
# Écrit toute l'arborescence, installe les dépendances, et
# s'arrête là. Aucune migration n'est jouée : il faut d'abord
# remplir .env.local et créer le rôle Neon.
# ============================================================
set -euo pipefail

if [ -n "$(ls -A 2>/dev/null)" ]; then
  echo "Le dossier courant n'est pas vide. Lancez le script dans un dossier neuf."
  exit 1
fi

NODE_MAJOR="$(node -v 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/' || echo 0)"
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "Node 20+ requis (détecté: $(node -v 2>/dev/null || echo aucun))."
  exit 1
fi

write() {
  mkdir -p "$(dirname "$1")"
  cat > "$1"
}

echo "→ écriture des fichiers"
write 'package.json' <<'TFEOF'
{
  "name": "tablefinder",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "eslint",
    "typecheck": "tsc --noEmit",
    "db:migrate": "node --env-file=.env.local scripts/migrate.mjs",
    "db:test": "bash db/_test/run.sh",
    "auth:generate": "better-auth generate --config lib/auth.ts --output db/migrations/_betterauth.sql"
  },
  "dependencies": {
    "better-auth": "^1.6.27",
    "next": "^15.5.0",
    "pg": "^8.13.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "zod": "^3.24.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "@types/pg": "^8.11.0",
    "@types/react": "^19.0.0",
    "typescript": "^5.7.0",
    "postcss": "^8.5.26",
    "tailwindcss": "^4.3.0",
    "@tailwindcss/postcss": "^4.3.0"
  },
  "overrides": {
    "sharp": "^0.35.3",
    "postcss": "^8.5.26"
  }
}

TFEOF
write 'tsconfig.json' <<'TFEOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "ES2022"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}

TFEOF
write '.env.example' <<'TFEOF'
# ------------------------------------------------------------
# Neon — DEUX chaînes de connexion, volontairement
# ------------------------------------------------------------

# Runtime. Rôle `tablefinder_app` : soumis à la RLS, sans droit sur
# le schéma. Utiliser l'endpoint POOLED (celui avec `-pooler`).
DATABASE_URL="postgresql://tablefinder_app:MDP@ep-xxx-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require"

# Migrations uniquement. Rôle propriétaire (`neondb_owner`).
# Ne jamais mettre cette chaîne dans les variables Vercel du runtime.
DATABASE_URL_OWNER="postgresql://neondb_owner:MDP@ep-xxx.us-east-2.aws.neon.tech/neondb?sslmode=require"

# ------------------------------------------------------------
# Better Auth (auto-hébergé)
# ------------------------------------------------------------
BETTER_AUTH_SECRET="openssl rand -base64 32"
BETTER_AUTH_URL="http://localhost:3000"
NEXT_PUBLIC_APP_URL="http://localhost:3000"

# ------------------------------------------------------------
# Cloudflare R2 — logo du QR Code (Phase 9)
# Neon Object Storage existe mais reste en préversion privée et
# limité à us-east-2 ; R2 est disponible et déjà dans votre stack.
# ------------------------------------------------------------
R2_ACCOUNT_ID=""
R2_ACCESS_KEY_ID=""
R2_SECRET_ACCESS_KEY=""
R2_BUCKET="tablefinder"

TFEOF
write '.gitignore' <<'TFEOF'
node_modules/
.next/
.env
.env.local
.env*.local
*.tsbuildinfo

TFEOF
write 'README.md' <<'TFEOF'
# TableFinder — Neon

## Ce qui change en quittant Supabase

| | Supabase | Neon |
|---|---|---|
| Auth | Supabase Auth | Better Auth auto-hébergé |
| Accès aux données | PostgREST, navigateur → Postgres | Server Actions, navigateur → serveur → Postgres |
| Barrière d'autorisation | **RLS** | **`repositories/`**, RLS en filet |
| Stockage (logo QR) | Supabase Storage | Cloudflare R2 |
| Migrations | Supabase CLI | `scripts/migrate.mjs` |
| Rôles | `anon` / `authenticated` | `neondb_owner` / `tablefinder_app` |

### Le point qui compte

Avec Supabase, le navigateur parlait **directement** à Postgres. La RLS
était la seule chose entre un invité curieux et vos données ; sans elle,
tout fuyait.

Avec Neon, le navigateur ne voit jamais la base. Tout passe par les
Server Actions. La conséquence n'est pas « on a moins besoin de
sécurité » — c'est que **la barrière a changé d'endroit** : un `WHERE
owner_id = ...` oublié dans un repository est désormais une fuite, alors
que la RLS l'aurait attrapé avant.

D'où le dispositif retenu :

1. **`repositories/`** — chaque fonction prend `userId` en premier
   argument et passe par `withUser()`. C'est la barrière principale.
2. **RLS** — l'application se connecte avec `tablefinder_app`, un rôle
   non propriétaire soumis aux policies. Filet de sécurité.
3. **`current_app_user()` lève une erreur** si `app.user_id` n'est pas
   posé, au lieu de renvoyer NULL. Oublier `withUser()` fait planter
   bruyamment plutôt que retourner zéro ligne en silence — la
   différence entre un bug trouvé en 30 secondes et un bug trouvé en
   production.
4. **FK composite** — assigner un invité à la table d'un autre
   événement reste impossible au niveau base.

Si la friction du double rôle devient pénible, la sortie propre est de
supprimer la migration `0003` et de tout faire reposer sur les
repositories. À faire consciemment, pas par accident.

## Décisions à connaître

**Better Auth auto-hébergé plutôt que Neon Auth.** Neon Auth (« Managed
Better Auth ») est encore en Beta, limité aux régions AWS, et
incompatible avec IP Allow / Private Networking. Comme la même bibliothèque
tourne en auto-hébergé avec ses tables dans votre base, l'auto-hébergement
donne le même produit sans dépendance managée. Le schéma d'auth
(`0001_auth.sql`) est généré par leur CLI, pas écrit à la main.

**Pas d'ORM.** Le schéma utilise une colonne générée par fonction
personnalisée, une FK composite avec `ON DELETE SET NULL (colonne)`, des
policies RLS et trois fonctions PL/pgSQL. Drizzle n'en exprime qu'une
partie, et `drizzle-kit generate` proposerait de « corriger » le reste.
Un schéma TypeScript parallèle serait un piège à dérive. On reste sur
`pg` + requêtes paramétrées + Zod aux frontières.

**Deux chaînes de connexion.** `DATABASE_URL` (rôle applicatif, endpoint
pooled) pour le runtime, `DATABASE_URL_OWNER` (propriétaire) pour les
migrations seulement. Ne mettez jamais la seconde dans les variables
d'environnement Vercel du runtime.

**Endpoint pooled.** Le pooler Neon tourne en mode transaction, donc
`SET LOCAL` fonctionne et un `SET` de session ne survivrait pas. C'est
pourquoi `withUser()` utilise `set_config(..., true)`.

## Mise en route

```bash
npm install
cp .env.example .env.local     # puis remplir
```

Dans la console Neon, **Roles → New Role**, nom `tablefinder_app`.
Récupérez son mot de passe et construisez `DATABASE_URL` avec
l'endpoint **pooled**. La migration `0003` échoue avec un message
explicite si le rôle n'existe pas.

```bash
npm run db:migrate
npm run dev
```

## Tests base de données

```bash
PGURL="postgres://user:pass@host:5432/postgres" npm run db:test
```

19 assertions, dont :

**Recherche** — `elie` trouve `Élie` ; `FRANCOIS` trouve `François` ;
`%` ne retourne rien ; minimum 2 caractères ; slug inconnu muet ;
événement dépublié invisible ; aucune fuite entre événements.

**Intégrité** — FK composite bloquant ; suppression d'une table
désassignant l'invité sans casser `event_id` ; cascade compte →
événements ; comptage de remplissage.

**Isolation** — requête sans `app.user_id` rejetée ; B ne voit ni
n'écrit les données de A ; B ne peut pas importer chez A ; le rôle
applicatif ne peut pas désactiver la RLS.

**Import** — tables manquantes signalées sans insertion ; création sur
confirmation ; lignes vides ignorées ; refus au-delà de 2000 lignes.

## Contrat de `import_guests`

Entrée :

```json
[{ "first_name": "Elie", "last_name": "Mukuna", "table_number": 12 }]
```

Sortie n°1 — l'aperçu affiche « Créer les tables manquantes » :

```json
{ "status": "missing_tables", "missing_tables": [30, 31], "inserted": 0 }
```

Sortie n°2 — après confirmation :

```json
{ "status": "ok", "inserted": 4, "created_tables": 2, "skipped": 1 }
```

## Limites assumées

- **Pas encore de rate limit.** `search_event_guests` reste énumérable
  par force brute alphabétique. À ajouter avant tout usage client réel.
- **Capacité non contrainte.** Dépasser une table est permis ; la vue
  expose `is_overbooked` pour l'afficher en avertissement plutôt que de
  bloquer l'organisateur en plein placement.
- **Doublons non bloqués.** Deux invités homonymes sont légitimes ;
  détection à l'aperçu seulement.
- **Vérification d'email désactivée.** À activer dans `lib/auth.ts` dès
  qu'un fournisseur d'email est branché.

TFEOF
write 'CLAUDE.md' <<'TFEOF'
# TableFinder — contexte projet

MVP : un organisateur crée une liste d'invités et leur assigne une table.
Il génère un QR Code. L'invité le scanne, cherche son nom, voit sa table.
Aucune application à installer.

Langue du produit et des commentaires : **français**.

## Stack

Next.js 15 (App Router) · TypeScript · Tailwind v4 · shadcn/ui ·
Neon Postgres · Better Auth auto-hébergé · Cloudflare R2 · Vercel

Pas d'ORM. `pg` + requêtes paramétrées + Zod aux frontières.

## Règle d'autorisation — la plus importante

Toute lecture ou écriture sur `events`, `event_tables` ou `guests` passe
par une fonction de `repositories/` qui prend `userId` en **premier**
argument et l'exécute dans `withUser()`.

```ts
export async function listEvents(userId: string) {
  return withUser(userId, async (tx) => { /* ... */ });
}
```

Le navigateur ne parle jamais à la base. La barrière principale est donc
le code, pas la RLS. Un `WHERE owner_id` oublié est une fuite.

La RLS reste active en filet : l'app se connecte avec `tablefinder_app`,
un rôle non propriétaire, et `withUser()` pose `app.user_id` par
transaction. `current_app_user()` **lève une erreur** si le GUC manque,
au lieu de renvoyer NULL — c'est volontaire, pour que l'oubli plante
bruyamment.

Ne jamais exporter de fonction qui interroge ces trois tables sans
`userId`. Seule exception : `repositories/public-search.ts`, qui n'accède
aux données qu'à travers les fonctions `SECURITY DEFINER` de la migration
`0004`.

## Base de données

Les migrations sont du SQL écrit à la main, dans `db/migrations/`,
numérotées, jouées par `scripts/migrate.mjs` avec `DATABASE_URL_OWNER`.

**Ne jamais modifier une migration déjà appliquée** : le runner compare
un checksum et refuse de continuer. Créer un nouveau fichier.

`0001_auth.sql` est généré par le CLI Better Auth. Le régénérer via
`npm run auth:generate` si la config auth change, ne pas l'éditer.

Points du schéma à ne pas casser :

- `guests.search_name` est une colonne générée (accents + casse
  neutralisés). C'est ce qui fait que « elie » trouve « Élie ». La
  recherche doit toujours passer par elle, jamais par `first_name`.
- FK composite `(table_id, event_id)` : empêche d'assigner un invité à la
  table d'un autre événement. `ON DELETE SET NULL (table_id)` avec liste
  de colonnes, sinon `event_id` serait mis à NULL.
- Les slugs portent un suffixe aléatoire. Sans lui ils se devinent à
  partir des prénoms des mariés.

## Tests

```bash
PGURL="postgres://..." npm run db:test
```

19 assertions dans `db/_test/`. Toute modification du schéma, des
policies ou des fonctions doit laisser la suite verte, et ajouter une
assertion si elle introduit une garantie nouvelle.

Ne pas déplacer `db/_test/` dans `db/migrations/` : le runner y jouerait
les fixtures en production.

## Import CSV

`import_guests(event_id, rows, create_missing_tables, default_capacity)`
est atomique et `SECURITY INVOKER` (la RLS vérifie la propriété).

Si des numéros de table manquent et que la confirmation n'est pas donnée,
elle n'insère **rien** et renvoie :

```json
{ "status": "missing_tables", "missing_tables": [30, 31], "inserted": 0 }
```

L'aperçu affiche alors un bouton « Créer les tables manquantes », qui
rappelle la fonction avec `create_missing_tables = true`.

## Reste à faire

Étapes 5 à 15 du cahier des charges : dashboard, événements, tables,
invités, import CSV, page publique, recherche, QR Code, personnalisation,
tests, déploiement.

Deux dettes connues et assumées :

1. **Pas de rate limit** sur `search_event_guests`. La page publique reste
   énumérable par force brute alphabétique. À traiter avant qu'un vrai
   client l'utilise.
2. **Capacité non contrainte** en base. La vue `event_tables_with_counts`
   expose `is_overbooked` pour l'afficher en avertissement plutôt que de
   bloquer l'organisateur en plein placement.

## À ne pas construire maintenant

Stripe, abonnements, analytics, multi-admin, application mobile, IA,
notifications SMS, domaine personnalisé, réservation.

TFEOF
write 'db/client.ts' <<'TFEOF'
import { Pool, type PoolClient } from "pg";

/**
 * Utiliser la chaîne POOLED de Neon (celle qui contient `-pooler`).
 * Le pooler tourne en mode transaction : `SET LOCAL` fonctionne, un
 * `SET` de session ne survivrait pas. D'où set_config(..., true)
 * ci-dessous, qui est la variante locale à la transaction.
 */
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.PG_POOL_MAX ?? 10),
});

/**
 * Ouvre une transaction et y pose l'identité de l'organisateur.
 * Toute lecture ou écriture sur events / event_tables / guests DOIT
 * passer par ici : hors de ce wrapper, la RLS lève une erreur
 * explicite plutôt que de renvoyer zéro ligne en silence.
 */
export async function withUser<T>(
  userId: string,
  fn: (tx: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    // Paramétré : un identifiant Better Auth ne peut pas s'échapper
    // dans le SQL. `SET LOCAL app.user_id = $1` ne serait pas
    // paramétrable, set_config l'est.
    await client.query("select set_config('app.user_id', $1, true)", [userId]);
    const result = await fn(client);
    await client.query("commit");
    return result;
  } catch (error) {
    await client.query("rollback").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Pour la page publique uniquement : aucune session, donc aucune
 * identité à poser. N'utiliser qu'avec les fonctions SECURITY
 * DEFINER (get_public_event, search_event_guests), jamais avec un
 * SELECT direct sur les tables.
 */
export async function publicQuery<T = unknown>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const { rows } = await pool.query(sql, params);
  return rows as T[];
}

export { pool };

TFEOF
write 'db/migrations/0001_auth.sql' <<'TFEOF'
-- ============================================================
-- TableFinder — 0001 : tables Better Auth
-- Généré par `npx @better-auth/cli generate` (better-auth 1.6.27).
-- Ne pas éditer à la main : régénérer si la config auth change.
-- Ces tables ne sont PAS sous RLS : l'authentification doit
-- pouvoir lire un utilisateur par email avant qu'une session
-- n'existe.
-- ============================================================

create table "users" ("id" text not null primary key, "name" text not null, "email" text not null unique, "emailVerified" boolean not null, "image" text, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz default CURRENT_TIMESTAMP not null);

create table "sessions" ("id" text not null primary key, "expiresAt" timestamptz not null, "token" text not null unique, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz not null, "ipAddress" text, "userAgent" text, "userId" text not null references "users" ("id") on delete cascade);

create table "accounts" ("id" text not null primary key, "accountId" text not null, "providerId" text not null, "userId" text not null references "users" ("id") on delete cascade, "accessToken" text, "refreshToken" text, "idToken" text, "accessTokenExpiresAt" timestamptz, "refreshTokenExpiresAt" timestamptz, "scope" text, "password" text, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz not null);

create table "verifications" ("id" text not null primary key, "identifier" text not null, "value" text not null, "expiresAt" timestamptz not null, "createdAt" timestamptz default CURRENT_TIMESTAMP not null, "updatedAt" timestamptz default CURRENT_TIMESTAMP not null);

create index "sessions_userId_idx" on "sessions" ("userId");

create index "accounts_userId_idx" on "accounts" ("userId");

create index "verifications_identifier_idx" on "verifications" ("identifier");

TFEOF
write 'db/migrations/0002_app_schema.sql' <<'TFEOF'
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

TFEOF
write 'db/migrations/0003_rls.sql' <<'TFEOF'
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

TFEOF
write 'db/migrations/0004_public_api.sql' <<'TFEOF'
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

TFEOF
write 'db/_test/00_roles.sql' <<'TFEOF'
-- Rôle applicatif. Sur Neon, créez-le depuis la console (Roles ->
-- New Role) ; ici on le fabrique pour pouvoir tester en local.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'tablefinder_app') then
    create role tablefinder_app login password 'test-only';
  end if;
end $$;

TFEOF
write 'db/_test/_assert.sql' <<'TFEOF'
create or replace function assert_eq(actual anyelement, expected anyelement, label text)
returns text language plpgsql as $$
begin
  if actual is not distinct from expected then
    return 'OK   -> ' || label;
  end if;
  raise exception 'ECHEC [%] : attendu "%", obtenu "%"', label, expected, actual;
end $$;

TFEOF
write 'db/_test/01_checks.sql' <<'TFEOF'
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

TFEOF
write 'db/_test/02_rls_and_import.sql' <<'TFEOF'
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

TFEOF
write 'db/_test/run.sh' <<'TFEOF'
#!/usr/bin/env bash
# Applique les migrations sur une base jetable et lance les assertions.
#   PGURL="postgres://user:pass@host:5432/postgres" ./db/_test/run.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
PGURL="${PGURL:-postgres://postgres@localhost:5432/postgres}"
DB="${TF_TEST_DB:-tablefinder_test}"

psql "$PGURL" -v ON_ERROR_STOP=1 -q \
  -c "drop database if exists ${DB};" \
  -c "create database ${DB};"

TARGET="${PGURL%/*}/${DB}"
run() { echo "==> $(basename "$1")"; psql "$TARGET" -v ON_ERROR_STOP=1 -q -f "$1"; }

run "$HERE/00_roles.sql"
for f in "$ROOT"/migrations/*.sql; do run "$f"; done
run "$HERE/_assert.sql"
run "$HERE/01_checks.sql"
run "$HERE/02_rls_and_import.sql"

echo; echo "Toutes les assertions sont passées."

TFEOF
write 'lib/auth.ts' <<'TFEOF'
import { betterAuth } from "better-auth";
import { Pool } from "pg";

/**
 * Better Auth auto-hébergé : les tables users / sessions / accounts
 * / verifications vivent dans VOTRE base Neon. Aucun fournisseur
 * externe, un `pg_dump` suffit à tout emporter ailleurs.
 *
 * Il utilise son propre pool parce qu'il doit lire la table users
 * avant qu'une session n'existe — donc hors du wrapper withUser().
 * Ces tables ne sont volontairement pas sous RLS (migration 0003).
 */
export const auth = betterAuth({
  database: new Pool({ connectionString: process.env.DATABASE_URL }),
  baseURL: process.env.BETTER_AUTH_URL,
  secret: process.env.BETTER_AUTH_SECRET,

  emailAndPassword: {
    enabled: true,
    minPasswordLength: 10,
    // Passer à true dès qu'un fournisseur d'email est branché.
    requireEmailVerification: false,
  },

  user: { modelName: "users" },
  session: {
    modelName: "sessions",
    expiresIn: 60 * 60 * 24 * 30,
    cookieCache: { enabled: true, maxAge: 60 * 5 },
  },
  account: { modelName: "accounts" },
  verification: { modelName: "verifications" },
});

export type Session = typeof auth.$Infer.Session;

TFEOF
write 'lib/auth-client.ts' <<'TFEOF'
import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient({
  baseURL: process.env.NEXT_PUBLIC_APP_URL,
});

export const { signIn, signUp, signOut, useSession } = authClient;

TFEOF
write 'lib/session.ts' <<'TFEOF'
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { auth } from "./auth";

/**
 * À appeler en tête de chaque Server Action et de chaque page du
 * dashboard. Renvoie l'identifiant à passer à withUser().
 */
export async function requireUser() {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session?.user) redirect("/connexion");
  return session.user;
}

export async function getUser() {
  const session = await auth.api.getSession({ headers: await headers() });
  return session?.user ?? null;
}

TFEOF
write 'repositories/events.ts' <<'TFEOF'
import { randomBytes } from "node:crypto";
import { z } from "zod";
import { withUser } from "@/db/client";

/**
 * PATTERN À SUIVRE POUR TOUS LES REPOSITORIES
 *
 * Chaque fonction prend `userId` en PREMIER argument et passe par
 * withUser(). C'est la barrière d'autorisation principale depuis le
 * passage à Neon ; la RLS n'est plus que le filet de sécurité.
 *
 * Ne jamais exporter de fonction qui interroge events / event_tables
 * / guests sans userId : ce serait rouvrir la porte à l'IDOR.
 */

export const eventInput = z.object({
  name: z.string().trim().min(1).max(120),
  eventDate: z.coerce.date().nullable().optional(),
  description: z.string().trim().max(2000).nullable().optional(),
});
export type EventInput = z.infer<typeof eventInput>;

export type EventRow = {
  id: string;
  name: string;
  slug: string;
  event_date: string | null;
  description: string | null;
  is_published: boolean;
  guest_count: number;
  table_count: number;
  unassigned_count: number;
};

/** "Mariage Élie & Sarah" -> "mariage-elie-sarah-k4f9" */
export function buildSlug(name: string): string {
  const base = name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
  // Suffixe aléatoire : sans lui, un slug se devine à partir des
  // prénoms des mariés et n'importe qui peut fouiller la liste.
  const suffix = randomBytes(3).toString("hex").slice(0, 5);
  return `${base || "evenement"}-${suffix}`;
}

export async function listEvents(userId: string): Promise<EventRow[]> {
  return withUser(userId, async (tx) => {
    const { rows } = await tx.query<EventRow>(
      `select e.id, e.name, e.slug, e.event_date, e.description, e.is_published,
              (select count(*)::int from guests g where g.event_id = e.id) as guest_count,
              (select count(*)::int from event_tables t where t.event_id = e.id) as table_count,
              (select count(*)::int from guests g
                 where g.event_id = e.id and g.table_id is null) as unassigned_count
         from events e
        order by e.created_at desc`,
    );
    return rows;
  });
}

export async function getEvent(userId: string, eventId: string) {
  return withUser(userId, async (tx) => {
    const { rows } = await tx.query(`select * from events where id = $1`, [eventId]);
    return rows[0] ?? null;
  });
}

export async function createEvent(userId: string, input: EventInput) {
  const data = eventInput.parse(input);

  return withUser(userId, async (tx) => {
    // Le suffixe aléatoire rend la collision improbable ; on
    // retente quand même plutôt que de renvoyer une erreur brute.
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        const { rows } = await tx.query(
          `insert into events (owner_id, name, event_date, description, slug)
           values ($1, $2, $3, $4, $5)
           returning id, slug`,
          [
            userId,
            data.name,
            data.eventDate ?? null,
            data.description ?? null,
            buildSlug(data.name),
          ],
        );
        return rows[0] as { id: string; slug: string };
      } catch (error) {
        const code = (error as { code?: string }).code;
        if (code === "23505" && attempt < 4) continue; // slug déjà pris
        throw error;
      }
    }
    throw new Error("Impossible de générer un slug unique");
  });
}

export async function updateEvent(userId: string, eventId: string, input: EventInput) {
  const data = eventInput.parse(input);
  return withUser(userId, async (tx) => {
    const { rowCount } = await tx.query(
      `update events set name = $2, event_date = $3, description = $4
        where id = $1`,
      [eventId, data.name, data.eventDate ?? null, data.description ?? null],
    );
    // rowCount 0 = événement inexistant OU appartenant à quelqu'un
    // d'autre. La RLS ne distingue pas les deux, et c'est très bien :
    // répondre différemment révélerait l'existence de l'événement.
    if (rowCount === 0) throw new Error("Événement introuvable");
  });
}

export async function deleteEvent(userId: string, eventId: string) {
  return withUser(userId, async (tx) => {
    const { rowCount } = await tx.query(`delete from events where id = $1`, [eventId]);
    if (rowCount === 0) throw new Error("Événement introuvable");
  });
}

TFEOF
write 'repositories/public-search.ts' <<'TFEOF'
import { publicQuery } from "@/db/client";

/**
 * Page publique /e/[slug] — aucune session.
 *
 * Ces deux fonctions sont les SEULES autorisées à lire sans
 * identité, et elles n'accèdent aux données qu'à travers les
 * fonctions SECURITY DEFINER de la migration 0004, qui portent
 * elles-mêmes les garde-fous (2 caractères minimum, jokers LIKE
 * échappés, 10 résultats maximum, cloisonnement par slug).
 */

export type PublicEvent = {
  slug: string;
  name: string;
  event_date: string | null;
  description: string | null;
  qr_caption: string | null;
};

export type GuestMatch = {
  guest_id: string;
  first_name: string;
  last_name: string;
  table_number: number | null;
  table_name: string | null;
};

export async function getPublicEvent(slug: string): Promise<PublicEvent | null> {
  const rows = await publicQuery<PublicEvent>(
    `select * from get_public_event($1)`,
    [slug],
  );
  return rows[0] ?? null;
}

export async function searchGuests(slug: string, query: string): Promise<GuestMatch[]> {
  return publicQuery<GuestMatch>(
    `select * from search_event_guests($1, $2)`,
    [slug, query],
  );
}

TFEOF
write 'scripts/migrate.mjs' <<'TFEOF'
#!/usr/bin/env node
/**
 * Runner de migrations minimal.
 *
 * Se connecte avec DATABASE_URL_OWNER (le rôle propriétaire Neon,
 * `neondb_owner`), jamais avec la chaîne applicative : le rôle
 * `tablefinder_app` ne doit pas pouvoir toucher au schéma.
 *
 * Chaque fichier tourne dans SA PROPRE transaction et est enregistré
 * dans _migrations. Un fichier qui échoue est intégralement annulé.
 */
import { readdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "db", "migrations");
const url = process.env.DATABASE_URL_OWNER;

if (!url) {
  console.error("DATABASE_URL_OWNER manquant (rôle propriétaire Neon).");
  process.exit(1);
}

const client = new pg.Client({ connectionString: url });
await client.connect();

await client.query(`
  create table if not exists _migrations (
    name       text primary key,
    checksum   text not null,
    applied_at timestamptz not null default now()
  )`);

const files = (await readdir(DIR)).filter((f) => f.endsWith(".sql")).sort();
const { rows: applied } = await client.query("select name, checksum from _migrations");
const seen = new Map(applied.map((r) => [r.name, r.checksum]));

let count = 0;
for (const name of files) {
  const sql = await readFile(path.join(DIR, name), "utf8");
  const checksum = createHash("sha256").update(sql).digest("hex").slice(0, 16);

  if (seen.has(name)) {
    if (seen.get(name) !== checksum) {
      console.error(`\n✗ ${name} a été modifié après application.`);
      console.error("  Créez une nouvelle migration plutôt que d'éditer celle-ci.");
      process.exit(1);
    }
    continue;
  }

  process.stdout.write(`→ ${name} ... `);
  try {
    await client.query("begin");
    await client.query(sql);
    await client.query("insert into _migrations (name, checksum) values ($1, $2)", [name, checksum]);
    await client.query("commit");
    console.log("ok");
    count++;
  } catch (error) {
    await client.query("rollback");
    console.log("ÉCHEC");
    console.error(`\n${error.message}`);
    if (error.hint) console.error(`Indice : ${error.hint}`);
    await client.end();
    process.exit(1);
  }
}

console.log(count === 0 ? "Base déjà à jour." : `${count} migration(s) appliquée(s).`);
await client.end();

TFEOF
write 'app/api/auth/[...all]/route.ts' <<'TFEOF'
import { auth } from "@/lib/auth";
import { toNextJsHandler } from "better-auth/next-js";

export const { GET, POST } = toNextJsHandler(auth.handler);

TFEOF

echo "→ fichiers de base Next.js"

write next.config.ts <<'TFEOF'
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pg est un module Node natif : il ne doit pas être bundlé.
  serverExternalPackages: ["pg"],
};

export default nextConfig;
TFEOF

write postcss.config.mjs <<'TFEOF'
export default { plugins: { "@tailwindcss/postcss": {} } };
TFEOF

write app/globals.css <<'TFEOF'
@import "tailwindcss";
TFEOF

write app/layout.tsx <<'TFEOF'
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "TableFinder",
  description: "Trouvez votre table en un scan.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr">
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
TFEOF

write app/page.tsx <<'TFEOF'
export default function Home() {
  return (
    <main className="mx-auto max-w-md p-8">
      <h1 className="text-2xl font-semibold">TableFinder</h1>
      <p className="mt-2 text-sm text-neutral-500">
        Squelette en place. Prochaine étape : dashboard et connexion.
      </p>
    </main>
  );
}
TFEOF

write next-env.d.ts <<'TFEOF'
/// <reference types="next" />
/// <reference types="next/image-types/global" />
TFEOF

chmod +x db/_test/run.sh

echo "→ npm install (peut prendre une minute)"
npm install
npm install -D tailwindcss @tailwindcss/postcss

cp .env.example .env.local

cat <<'DONE'

────────────────────────────────────────────────
Fait. Trois choses avant de lancer :

1. Console Neon → Roles → New Role → "tablefinder_app"
2. Remplir .env.local
   - DATABASE_URL       : rôle tablefinder_app, endpoint POOLED
   - DATABASE_URL_OWNER : rôle neondb_owner
   - BETTER_AUTH_SECRET : openssl rand -base64 32
3. npm run db:migrate && npm run dev

La migration 0003 échoue avec un message explicite si le rôle
n'existe pas encore. C'est voulu.
────────────────────────────────────────────────
DONE
