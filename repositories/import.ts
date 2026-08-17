import { z } from "zod";
import { withUser } from "@/db/client";

export const importRowInput = z.object({
  first_name: z.string().trim().max(80).default(""),
  last_name: z.string().trim().max(80).default(""),
  table_number: z.coerce.number().int().min(1).max(9999).nullable().optional(),
});
export type ImportRow = z.infer<typeof importRowInput>;

export const importRowsInput = z.array(importRowInput).min(1).max(2000);

export type ImportResult =
  | { status: "empty"; inserted: 0 }
  | { status: "missing_tables"; missing_tables: number[]; inserted: 0 }
  | { status: "ok"; inserted: number; created_tables: number; skipped: number };

/**
 * Enveloppe import_guests() : atomique, SECURITY INVOKER, la RLS
 * garantit que p_event_id doit appartenir à userId sinon la fonction
 * lève "Événement introuvable ou accès refusé".
 */
export async function importGuests(
  userId: string,
  eventId: string,
  rows: ImportRow[],
  createMissingTables: boolean,
  defaultCapacity: number,
): Promise<ImportResult> {
  const data = importRowsInput.parse(rows);
  return withUser(userId, async (tx) => {
    const { rows: result } = await tx.query(
      `select import_guests($1, $2::jsonb, $3, $4) as result`,
      [eventId, JSON.stringify(data), createMissingTables, defaultCapacity],
    );
    return result[0].result as ImportResult;
  });
}
