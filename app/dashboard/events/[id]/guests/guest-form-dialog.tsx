"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import type { GuestRow } from "@/repositories/guests";
import type { TableRow as EventTable } from "@/repositories/tables";
import { createGuestAction, updateGuestAction } from "./actions";

export function GuestFormDialog({
  eventId,
  guest,
  tables,
  open,
  onOpenChange,
}: {
  eventId: string;
  guest?: GuestRow;
  tables: EventTable[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const router = useRouter();
  const [firstName, setFirstName] = useState(guest?.first_name ?? "");
  const [lastName, setLastName] = useState(guest?.last_name ?? "");
  const [tableId, setTableId] = useState(guest?.table_id ?? "");
  const [pending, startTransition] = useTransition();

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    startTransition(async () => {
      const input = { firstName, lastName, tableId: tableId || null };
      const result = guest
        ? await updateGuestAction(eventId, guest.id, input)
        : await createGuestAction(eventId, input);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success(guest ? "Invité modifié" : "Invité ajouté");
      onOpenChange(false);
      if (!guest) {
        setFirstName("");
        setLastName("");
        setTableId("");
      }
      router.refresh();
    });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{guest ? "Modifier l'invité" : "Nouvel invité"}</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="firstName">Prénom</Label>
              <Input
                id="firstName"
                maxLength={80}
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="lastName">Nom</Label>
              <Input
                id="lastName"
                maxLength={80}
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="tableId">Table</Label>
            <select
              id="tableId"
              value={tableId}
              onChange={(e) => setTableId(e.target.value)}
              className="flex h-9 w-full rounded-md border border-neutral-200 bg-white px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-neutral-400"
            >
              <option value="">Non assigné</option>
              {tables.map((table) => (
                <option key={table.id} value={table.id}>
                  Table {table.table_number}
                  {table.name ? ` — ${table.name}` : ""} ({table.guest_count}/
                  {table.capacity})
                </option>
              ))}
            </select>
          </div>
          <DialogFooter>
            <Button
              type="submit"
              disabled={pending || (!firstName.trim() && !lastName.trim())}
            >
              {pending ? "Enregistrement..." : guest ? "Enregistrer" : "Ajouter"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
