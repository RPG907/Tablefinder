"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/session";
import { ok, fail, type ActionResult } from "@/lib/action-result";
import * as events from "@/repositories/events";

export async function updateEventAction(
  eventId: string,
  input: events.EventInput,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await events.updateEvent(user.id, eventId, input);
    revalidatePath(`/dashboard/events/${eventId}`);
    revalidatePath("/dashboard");
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}

export async function setPublishedAction(
  eventId: string,
  isPublished: boolean,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await events.setEventPublished(user.id, eventId, isPublished);
    revalidatePath(`/dashboard/events/${eventId}`);
    revalidatePath("/dashboard");
    return ok(undefined);
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
