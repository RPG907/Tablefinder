"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/session";
import { ok, fail, type ActionResult } from "@/lib/action-result";
import * as events from "@/repositories/events";

export async function createEventAction(
  input: events.EventInput,
): Promise<ActionResult<{ id: string; slug: string }>> {
  try {
    const user = await requireUser();
    const created = await events.createEvent(user.id, input);
    revalidatePath("/dashboard");
    return ok(created);
  } catch (error) {
    return fail(error);
  }
}

export async function deleteEventAction(eventId: string): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await events.deleteEvent(user.id, eventId);
    revalidatePath("/dashboard");
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}

export async function setEventPublishedAction(
  eventId: string,
  isPublished: boolean,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await events.setEventPublished(user.id, eventId, isPublished);
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/events/${eventId}`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}
