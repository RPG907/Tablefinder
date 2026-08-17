import { z } from "zod";
import { withUser } from "@/db/client";

export const tableInput = z.object({
  tableNumber: z.coerce.number().int().min(1).max(9999),
  name: z.string().trim().max(60).nullable().optional(),
  capacity: z.coerce.number().int().min(1).max(100).default(10),
});
export type TableInput = z.infer<typeof tableInput>;

export type TableRow = {
  id: string;
  event_id: string;
  table_number: number;
  name: string | null;
  capacity: number;
  guest_count: number;
  seats_left: number;
  is_overbooked: boolean;
};

export async function listTables(userId: string, eventId: string): Promise<TableRow[]> {
  return withUser(userId, async (tx) => {
    const { rows } = await tx.query<TableRow>(
      `select id, event_id, table_number, name, capacity,
              guest_count, seats_left, is_overbooked
         from event_tables_with_counts
        where event_id = $1
        order by table_number`,
      [eventId],
    );
    return rows;
  });
}

export async function createTable(userId: string, eventId: string, input: TableInput) {
  const data = tableInput.parse(input);
  return withUser(userId, async (tx) => {
    try {
      const { rows } = await tx.query(
        `insert into event_tables (event_id, table_number, name, capacity)
         values ($1, $2, $3, $4)
         returning id`,
        [eventId, data.tableNumber, data.name || null, data.capacity],
      );
      return rows[0] as { id: string };
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code === "23505") {
        throw new Error(`La table numéro ${data.tableNumber} existe déjà`);
      }
      // FK violation (23503) : l'événement n'appartient pas à l'appelant,
      // ou n'existe pas. La RLS bloque l'INSERT en amont.
      throw error;
    }
  });
}

export async function updateTable(
  userId: string,
  tableId: string,
  input: TableInput,
) {
  const data = tableInput.parse(input);
  return withUser(userId, async (tx) => {
    try {
      const { rowCount } = await tx.query(
        `update event_tables
            set table_number = $2, name = $3, capacity = $4
          where id = $1`,
        [tableId, data.tableNumber, data.name || null, data.capacity],
      );
      if (rowCount === 0) throw new Error("Table introuvable");
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code === "23505") {
        throw new Error(`La table numéro ${data.tableNumber} existe déjà`);
      }
      throw error;
    }
  });
}

export async function deleteTable(userId: string, tableId: string) {
  return withUser(userId, async (tx) => {
    // Les invités assignés sont désassignés (ON DELETE SET NULL), pas supprimés.
    const { rowCount } = await tx.query(`delete from event_tables where id = $1`, [
      tableId,
    ]);
    if (rowCount === 0) throw new Error("Table introuvable");
  });
}
