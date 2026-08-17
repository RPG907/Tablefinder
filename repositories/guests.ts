import { z } from "zod";
import { withUser } from "@/db/client";

export const guestInput = z.object({
  firstName: z.string().trim().max(80).default(""),
  lastName: z.string().trim().max(80).default(""),
  tableId: z.string().uuid().nullable().optional(),
});
export type GuestInput = z.infer<typeof guestInput>;

export type GuestRow = {
  id: string;
  event_id: string;
  first_name: string;
  last_name: string;
  table_id: string | null;
  table_number: number | null;
  table_name: string | null;
};

/** Neutralise les jokers LIKE : sinon "%" dans la recherche renverrait tout. */
function escapeLike(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

export async function listGuests(
  userId: string,
  eventId: string,
  search?: string,
): Promise<GuestRow[]> {
  const trimmed = search?.trim();
  return withUser(userId, async (tx) => {
    const { rows } = await tx.query<GuestRow>(
      `select g.id, g.event_id, g.first_name, g.last_name, g.table_id,
              t.table_number, t.name as table_name
         from guests g
         left join event_tables t on t.id = g.table_id
        where g.event_id = $1
          and ($2::text is null or g.search_name like '%' || normalize_name($2) || '%' escape '\\')
        order by g.last_name, g.first_name`,
      [eventId, trimmed ? escapeLike(trimmed) : null],
    );
    return rows;
  });
}

function assertNameNotEmpty(data: GuestInput) {
  if (!data.firstName.trim() && !data.lastName.trim()) {
    throw new Error("Le prénom ou le nom est requis");
  }
}

export async function createGuest(userId: string, eventId: string, input: GuestInput) {
  const data = guestInput.parse(input);
  assertNameNotEmpty(data);
  return withUser(userId, async (tx) => {
    const { rows } = await tx.query(
      `insert into guests (event_id, first_name, last_name, table_id)
       values ($1, $2, $3, $4)
       returning id`,
      [eventId, data.firstName, data.lastName, data.tableId ?? null],
    );
    return rows[0] as { id: string };
  });
}

export async function updateGuest(userId: string, guestId: string, input: GuestInput) {
  const data = guestInput.parse(input);
  assertNameNotEmpty(data);
  return withUser(userId, async (tx) => {
    // La FK composite (table_id, event_id) empêche d'assigner ce
    // guest à la table d'un autre événement, même si tableId est
    // manipulé côté client.
    const { rowCount } = await tx.query(
      `update guests
          set first_name = $2, last_name = $3, table_id = $4
        where id = $1`,
      [guestId, data.firstName, data.lastName, data.tableId ?? null],
    );
    if (rowCount === 0) throw new Error("Invité introuvable");
  });
}

export async function deleteGuest(userId: string, guestId: string) {
  return withUser(userId, async (tx) => {
    const { rowCount } = await tx.query(`delete from guests where id = $1`, [guestId]);
    if (rowCount === 0) throw new Error("Invité introuvable");
  });
}
