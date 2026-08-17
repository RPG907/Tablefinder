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

21 assertions, dont :

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

