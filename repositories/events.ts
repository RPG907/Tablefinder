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
  // Chaîne "YYYY-MM-DD" plutôt qu'un objet Date : un Date construit à
  // partir d'un <input type="date"> transite par UTC, alors que `pg`
  // sérialise les paramètres Date via les accesseurs locaux — sur un
  // serveur dont le fuseau est en retard sur UTC, la date stockée
  // reculerait d'un jour. La colonne `date` accepte directement ce
  // format en paramètre, sans ambiguïté de fuseau.
  eventDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .nullable()
    .optional(),
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

export type EventDetail = {
  id: string;
  owner_id: string;
  name: string;
  slug: string;
  event_date: string | null;
  description: string | null;
  is_published: boolean;
  qr_foreground: string;
  qr_background: string;
  qr_caption: string | null;
  qr_logo_key: string | null;
  created_at: string;
  updated_at: string;
};

export const qrSettingsInput = z.object({
  qrForeground: z
    .string()
    .regex(/^#[0-9a-fA-F]{6}$/, "Couleur hexadécimale invalide"),
  qrBackground: z
    .string()
    .regex(/^#[0-9a-fA-F]{6}$/, "Couleur hexadécimale invalide"),
  qrCaption: z.string().trim().max(60).nullable().optional(),
});
export type QrSettingsInput = z.infer<typeof qrSettingsInput>;

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

export async function getEvent(
  userId: string,
  eventId: string,
): Promise<EventDetail | null> {
  return withUser(userId, async (tx) => {
    const { rows } = await tx.query<EventDetail>(
      `select * from events where id = $1`,
      [eventId],
    );
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

export async function setEventPublished(
  userId: string,
  eventId: string,
  isPublished: boolean,
) {
  return withUser(userId, async (tx) => {
    const { rowCount } = await tx.query(
      `update events set is_published = $2 where id = $1`,
      [eventId, isPublished],
    );
    if (rowCount === 0) throw new Error("Événement introuvable");
  });
}

export async function updateQrSettings(
  userId: string,
  eventId: string,
  input: QrSettingsInput,
) {
  const data = qrSettingsInput.parse(input);
  return withUser(userId, async (tx) => {
    const { rowCount } = await tx.query(
      `update events
          set qr_foreground = $2, qr_background = $3, qr_caption = $4
        where id = $1`,
      [eventId, data.qrForeground, data.qrBackground, data.qrCaption ?? null],
    );
    if (rowCount === 0) throw new Error("Événement introuvable");
  });
}

/** clé d'objet Cloudflare R2, ou null pour retirer le logo */
export async function setQrLogoKey(
  userId: string,
  eventId: string,
  key: string | null,
) {
  return withUser(userId, async (tx) => {
    const { rowCount } = await tx.query(
      `update events set qr_logo_key = $2 where id = $1`,
      [eventId, key],
    );
    if (rowCount === 0) throw new Error("Événement introuvable");
  });
}

