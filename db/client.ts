import { Pool, types, type PoolClient } from "pg";

/**
 * Par défaut, `pg` convertit les colonnes `date` en objets Date JS
 * (minuit UTC). event_date est ensuite manipulée comme une simple
 * chaîne "YYYY-MM-DD" partout dans l'app (formulaires, affichage) :
 * sans ce parseur, un aller-retour Date <-> fuseau local introduirait
 * un décalage d'un jour selon le fuseau du serveur. `setTypeParser`
 * est un registre global au process pg, d'où l'affectation ici plutôt
 * que par requête.
 */
types.setTypeParser(types.builtins.DATE, (value: string) => value);

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

