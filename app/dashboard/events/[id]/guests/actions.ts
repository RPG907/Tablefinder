"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/session";
import { ok, fail, type ActionResult } from "@/lib/action-result";
import * as guests from "@/repositories/guests";

export async function createGuestAction(
  eventId: string,
  input: guests.GuestInput,
): Promise<ActionResult<{ id: string }>> {
  try {
    const user = await requireUser();
    const created = await guests.createGuest(user.id, eventId, input);
    revalidatePath(`/dashboard/events/${eventId}/guests`);
    revalidatePath(`/dashboard/events/${eventId}/tables`);
    return ok(created);
  } catch (error) {
    return fail(error);
  }
}

export async function updateGuestAction(
  eventId: string,
  guestId: string,
  input: guests.GuestInput,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await guests.updateGuest(user.id, guestId, input);
    revalidatePath(`/dashboard/events/${eventId}/guests`);
    revalidatePath(`/dashboard/events/${eventId}/tables`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}

export async function deleteGuestAction(
  eventId: string,
  guestId: string,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await guests.deleteGuest(user.id, guestId);
    revalidatePath(`/dashboard/events/${eventId}/guests`);
    revalidatePath(`/dashboard/events/${eventId}/tables`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}
