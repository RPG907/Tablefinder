import { publicQuery } from "@/db/client";

/**
 * Page publique /e/[slug] et route /api/qr/[slug] — aucune session.
 *
 * Ces fonctions sont les SEULES autorisées à lire sans identité, et
 * elles n'accèdent aux données qu'à travers les fonctions SECURITY
 * DEFINER des migrations 0004 et 0005, qui portent elles-mêmes les
 * garde-fous (2 caractères minimum, jokers LIKE échappés, 10
 * résultats maximum, cloisonnement par slug, événement publié).
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

export type PublicQrSettings = {
  qr_foreground: string;
  qr_background: string;
  qr_logo_key: string | null;
};

export async function getPublicQrSettings(
  slug: string,
): Promise<PublicQrSettings | null> {
  const rows = await publicQuery<PublicQrSettings>(
    `select * from get_public_qr_settings($1)`,
    [slug],
  );
  return rows[0] ?? null;
}

