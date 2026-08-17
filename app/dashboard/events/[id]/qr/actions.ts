"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/session";
import { ok, fail, type ActionResult } from "@/lib/action-result";
import * as events from "@/repositories/events";
import { isR2Configured, uploadLogo, deleteLogo } from "@/lib/r2";

const MAX_LOGO_BYTES = 2 * 1024 * 1024;
const ALLOWED_LOGO_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

export async function updateQrSettingsAction(
  eventId: string,
  input: events.QrSettingsInput,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    await events.updateQrSettings(user.id, eventId, input);
    revalidatePath(`/dashboard/events/${eventId}/qr`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}

export async function uploadQrLogoAction(
  eventId: string,
  formData: FormData,
): Promise<ActionResult> {
  try {
    const user = await requireUser();
    if (!isR2Configured()) {
      throw new Error("Cloudflare R2 n'est pas configuré (voir .env.local).");
    }
    const file = formData.get("file");
    if (!(file instanceof File) || file.size === 0) {
      throw new Error("Aucun fichier sélectionné");
    }
    if (file.size > MAX_LOGO_BYTES) {
      throw new Error("Le logo doit faire moins de 2 Mo");
    }
    if (!ALLOWED_LOGO_TYPES.has(file.type)) {
      throw new Error("Formats acceptés : PNG, JPEG, WebP");
    }

    // Vérifie la propriété avant l'upload : withUser() lèverait sinon
    // une erreur après avoir déjà écrit dans R2.
    const event = await events.getEvent(user.id, eventId);
    if (!event) throw new Error("Événement introuvable");

    const buffer = Buffer.from(await file.arrayBuffer());
    const key = await uploadLogo(eventId, buffer, file.type);

    const previousKey = event.qr_logo_key;
    await events.setQrLogoKey(user.id, eventId, key);
    if (previousKey) {
      await deleteLogo(previousKey).catch(() => {});
    }

    revalidatePath(`/dashboard/events/${eventId}/qr`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}

export async function removeQrLogoAction(eventId: string): Promise<ActionResult> {
  try {
    const user = await requireUser();
    const event = await events.getEvent(user.id, eventId);
    if (!event) throw new Error("Événement introuvable");

    await events.setQrLogoKey(user.id, eventId, null);
    if (event.qr_logo_key) {
      await deleteLogo(event.qr_logo_key).catch(() => {});
    }

    revalidatePath(`/dashboard/events/${eventId}/qr`);
    return ok(undefined);
  } catch (error) {
    return fail(error);
  }
}
