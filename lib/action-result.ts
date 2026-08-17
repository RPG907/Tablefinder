import { unstable_rethrow } from "next/navigation";
import { ZodError } from "zod";

/**
 * Convention commune à toutes les Server Actions : ne jamais laisser
 * une exception traverser jusqu'au client (Next.js la remplacerait
 * par un message générique en production). On l'attrape ici et on
 * renvoie un objet sérialisable.
 */
export type ActionResult<T = undefined> =
  | { ok: true; data: T }
  | { ok: false; error: string };

export function ok<T>(data: T): ActionResult<T> {
  return { ok: true, data };
}

export function fail(error: unknown): ActionResult<never> {
  // requireUser() appelle redirect() si la session a expiré entre le
  // chargement de la page et le clic. redirect()/notFound() lèvent une
  // exception spéciale que Next.js doit intercepter lui-même : sans ce
  // rethrow, le catch(){return fail(error)} de chaque action l'avalerait
  // et transformerait une redirection en simple message d'erreur.
  unstable_rethrow(error);

  // Sans ce cas particulier, une ZodError afficherait son JSON brut
  // (chaque repository valide en entrée, voir "Zod aux frontières"
  // dans CLAUDE.md) : on ne garde que le premier message, lisible.
  if (error instanceof ZodError) {
    return { ok: false, error: error.issues[0]?.message ?? "Donnée invalide" };
  }
  return { ok: false, error: error instanceof Error ? error.message : "Erreur inconnue" };
}
