"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/session";
import { ok, fail, type ActionResult } from "@/lib/action-result";
import { importGuests, type ImportRow, type ImportResult } from "@/repositories/import";

export async function importGuestsAction(
  eventId: string,
  rows: ImportRow[],
  createMissingTables: boolean,
  defaultCapacity: number,
): Promise<ActionResult<ImportResult>> {
  try {
    const user = await requireUser();
    const result = await importGuests(
      user.id,
      eventId,
      rows,
      createMissingTables,
      defaultCapacity,
    );
    if (result.status === "ok") {
      revalidatePath(`/dashboard/events/${eventId}/guests`);
      revalidatePath(`/dashboard/events/${eventId}/tables`);
    }
    return ok(result);
  } catch (error) {
    return fail(error);
  }
}
