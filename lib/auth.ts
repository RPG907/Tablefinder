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

