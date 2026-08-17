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

