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

21 assertions dans `db/_test/`. Toute modification du schéma, des
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

