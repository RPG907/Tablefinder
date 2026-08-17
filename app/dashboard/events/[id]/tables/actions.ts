"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/session";
import { ok, fail, type ActionResult } from "@/lib/action-result";
import * as tables from "@/repositories/tables";

export async function createTableAction(
  eventId: string,
  input: tables.TableInput,
): Promise<ActionResult<{ id: string }>> {
  try {
    const user = await requireUser();
    const created = await tables.createTable(user.id, eventId, input);
    revalidatePath(`/dashboard/events/${eventId}/tables`);
    revalidatePath(`/dashboard/events/${eventId}/guests`);
    return ok(created);
  } catch (error) {
    return fail(error);
  }
}

export async function updateTableAction(
  eventId: string,
  tableId: string,
  input: tables.TableInput,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await tables.updateTable(user.id, tableId, input);
    revalidatePath(`/dashboard/events/${eventId}/tables`);
    revalidatePath(`/dashboard/events/${eventId}/guests`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}

export async function deleteTableAction(
  eventId: string,
  tableId: string,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await tables.deleteTable(user.id, tableId);
    revalidatePath(`/dashboard/events/${eventId}/tables`);
    revalidatePath(`/dashboard/events/${eventId}/guests`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}
