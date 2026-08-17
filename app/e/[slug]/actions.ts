"use server";

import { searchGuests, type GuestMatch } from "@/repositories/public-search";

/**
 * Seule Server Action publique du projet : aucun requireUser() ici,
 * volontairement. searchGuests() ne passe que par la fonction
 * SECURITY DEFINER search_event_guests, qui porte ses propres
 * garde-fous (voir repositories/public-search.ts).
 */
export async function searchGuestsAction(
  slug: string,
  query: string,
): Promise<GuestMatch[]> {
  if (query.trim().length < 2) return [];
  return searchGuests(slug, query);
}
