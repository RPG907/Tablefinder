"use client";

import { useState, useTransition } from "react";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { toast } from "sonner";
import { Plus, Pencil, Trash2, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "@/components/ui/table";
import type { GuestRow } from "@/repositories/guests";
import type { TableRow as EventTable } from "@/repositories/tables";
import { deleteGuestAction } from "./actions";
import { GuestFormDialog } from "./guest-form-dialog";

export function GuestsManager({
  eventId,
  guests,
  tables,
  initialSearch,
}: {
  eventId: string;
  guests: GuestRow[];
  tables: EventTable[];
  initialSearch: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [search, setSearch] = useState(initialSearch);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<GuestRow | undefined>(undefined);
  const [deletePending, startDeleteTransition] = useTransition();

  function onSearchChange(value: string) {
    setSearch(value);
    const params = new URLSearchParams(searchParams);
    if (value) params.set("q", value);
    else params.delete("q");
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }

  function openCreate() {
    setEditing(undefined);
    setDialogOpen(true);
  }

  function openEdit(guest: GuestRow) {
    setEditing(guest);
    setDialogOpen(true);
  }

  function onDelete(guest: GuestRow) {
    const label = [guest.first_name, guest.last_name].filter(Boolean).join(" ");
    if (!confirm(`Supprimer ${label || "cet invité"} ?`)) return;
    startDeleteTransition(async () => {
      const result = await deleteGuestAction(eventId, guest.id);
      if (!result.ok) {
        toast.error(result.error);
        return;
      }
      toast.success("Invité supprimé");
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <div className="relative max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-neutral-400" />
          <Input
            placeholder="Rechercher un invité..."
            className="pl-8"
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
          />
        </div>
        <Button onClick={openCreate}>
          <Plus /> Ajouter un invité
        </Button>
      </div>

      {guests.length === 0 ? (
        <div className="rounded-xl border border-dashed border-neutral-300 bg-white p-12 text-center">
          <p className="text-neutral-500">
            {search ? "Aucun invité ne correspond." : "Aucun invité pour l'instant."}
          </p>
        </div>
      ) : (
        <div className="rounded-xl border border-neutral-200 bg-white">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nom</TableHead>
                <TableHead>Table</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {guests.map((guest) => (
                <TableRow key={guest.id}>
                  <TableCell className="font-medium">
                    {[guest.first_name, guest.last_name].filter(Boolean).join(" ")}
                  </TableCell>
                  <TableCell className="text-neutral-500">
                    {guest.table_number ? (
                      <>
                        Table {guest.table_number}
                        {guest.table_name ? ` — ${guest.table_name}` : ""}
                      </>
                    ) : (
                      "Non assigné"
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      size="icon"
                      variant="ghost"
                      onClick={() => openEdit(guest)}
                      aria-label="Modifier"
                    >
                      <Pencil className="size-4" />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      disabled={deletePending}
                      onClick={() => onDelete(guest)}
                      aria-label="Supprimer"
                    >
                      <Trash2 className="size-4 text-red-600" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <GuestFormDialog
        eventId={eventId}
        guest={editing}
        tables={tables}
        open={dialogOpen}
        onOpenChange={setDialogOpen}
      />
    </div>
  );
}
