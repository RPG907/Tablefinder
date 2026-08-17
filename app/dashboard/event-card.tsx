"use client";

import Link from "next/link";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Trash2, Users, Armchair, UserX } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type { EventRow } from "@/repositories/events";
import { formatEventDate } from "@/lib/date";
import { deleteEventAction } from "./actions";

export function EventCard({ event }: { event: EventRow }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function onDelete() {
    if (!confirm(`Supprimer « ${event.name} » et toutes ses données ?`)) return;
    startTransition(async () => {
      const result = await deleteEventAction(event.id);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Événement supprimé");
      router.refresh();
    });
  }

  return (
    <Card className="flex flex-col">
      <CardHeader>
        <div className="flex items-start justify-between gap-2">
          <CardTitle className="text-base">
            <Link href={`/dashboard/events/${event.id}`} className="hover:underline">
              {event.name}
            </Link>
          </CardTitle>
          <Badge variant={event.is_published ? "success" : "secondary"}>
            {event.is_published ? "Publié" : "Brouillon"}
          </Badge>
        </div>
        {event.event_date && (
          <p className="text-sm text-neutral-500">{formatEventDate(event.event_date)}</p>
        )}
      </CardHeader>
      <CardContent className="flex flex-1 flex-col justify-between gap-4">
        <div className="flex gap-4 text-sm text-neutral-600">
          <span className="flex items-center gap-1">
            <Users className="size-4" /> {event.guest_count}
          </span>
          <span className="flex items-center gap-1">
            <Armchair className="size-4" /> {event.table_count}
          </span>
          {event.unassigned_count > 0 && (
            <span className="flex items-center gap-1 text-amber-600">
              <UserX className="size-4" /> {event.unassigned_count}
            </span>
          )}
        </div>
        <div className="flex items-center justify-between">
          <Button asChild size="sm" variant="outline">
            <Link href={`/dashboard/events/${event.id}`}>Gérer</Link>
          </Button>
          <Button
            size="icon"
            variant="ghost"
            disabled={pending}
            onClick={onDelete}
            aria-label="Supprimer"
          >
            <Trash2 className="size-4 text-red-600" />
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
