"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Copy, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import type { EventDetail } from "@/repositories/events";
import { updateEventAction, setPublishedAction, deleteEventAction } from "./actions";

function toDateInputValue(value: string | null): string {
  if (!value) return "";
  return value.slice(0, 10);
}

export function SettingsForm({ event }: { event: EventDetail }) {
  const router = useRouter();
  const [name, setName] = useState(event.name);
  const [eventDate, setEventDate] = useState(toDateInputValue(event.event_date));
  const [description, setDescription] = useState(event.description ?? "");
  const [published, setPublished] = useState(event.is_published);
  const [pending, startTransition] = useTransition();
  const [publishPending, startPublishTransition] = useTransition();
  const [deletePending, startDeleteTransition] = useTransition();

  // NEXT_PUBLIC_APP_URL plutôt que window.location.origin : cette
  // dernière ne serait connue qu'après hydratation et provoquerait un
  // avertissement de désaccord serveur/client au premier rendu.
  const publicUrl = `${process.env.NEXT_PUBLIC_APP_URL ?? ""}/e/${event.slug}`;

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    startTransition(async () => {
      const result = await updateEventAction(event.id, {
        name,
        eventDate: eventDate || null,
        description: description || null,
      });
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Enregistré");
      router.refresh();
    });
  }

  function onTogglePublished(checked: boolean) {
    setPublished(checked);
    startPublishTransition(async () => {
      const result = await setPublishedAction(event.id, checked);
      if (!result.ok) {
        toast.error(result.error);
        setPublished(!checked);
        return;
      }
      toast.success(checked ? "Page publique activée" : "Page publique masquée");
      router.refresh();
    });
  }

  function onDelete() {
    if (
      !confirm(
        `Supprimer « ${event.name} » ? Tous les invités et toutes les tables seront perdus.`,
      )
    )
      return;
    startDeleteTransition(async () => {
      const result = await deleteEventAction(event.id);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      router.push("/dashboard");
    });
  }

  return (
    <div className="max-w-xl space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Page publique</CardTitle>
          <CardDescription>
            Ce que vos invités voient en scannant le QR Code.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium">
                {published ? "Publiée" : "Non publiée"}
              </p>
              <p className="text-sm text-neutral-500">
                {published
                  ? "Vos invités peuvent chercher leur nom."
                  : "La page renvoie « introuvable » tant qu'elle est masquée."}
              </p>
            </div>
            <Switch
              checked={published}
              onCheckedChange={onTogglePublished}
              disabled={publishPending}
            />
          </div>
          <div className="flex items-center gap-2">
            <Input readOnly value={publicUrl} className="font-mono text-xs" />
            <Button
              type="button"
              variant="outline"
              size="icon"
              onClick={() => {
                navigator.clipboard.writeText(publicUrl);
                toast.success("Lien copié");
              }}
              aria-label="Copier le lien"
            >
              <Copy className="size-4" />
            </Button>
            <Button type="button" variant="outline" size="icon" asChild>
              <a href={publicUrl} target="_blank" rel="noreferrer" aria-label="Ouvrir">
                <ExternalLink className="size-4" />
              </a>
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Détails</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="name">Nom</Label>
              <Input
                id="name"
                required
                maxLength={120}
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="eventDate">Date</Label>
              <Input
                id="eventDate"
                type="date"
                value={eventDate}
                onChange={(e) => setEventDate(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="description">Description</Label>
              <Textarea
                id="description"
                maxLength={2000}
                value={description}
                onChange={(e) => setDescription(e.target.value)}
              />
            </div>
            <Button type="submit" disabled={pending || !name.trim()}>
              {pending ? "Enregistrement..." : "Enregistrer"}
            </Button>
          </form>
        </CardContent>
      </Card>

      <Separator />

      <Card className="border-red-200">
        <CardHeader>
          <CardTitle className="text-red-700">Zone de danger</CardTitle>
          <CardDescription>
            Supprime l&apos;événement, ses tables et tous ses invités. Irréversible.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button variant="destructive" onClick={onDelete} disabled={deletePending}>
            {deletePending ? "Suppression..." : "Supprimer l'événement"}
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
