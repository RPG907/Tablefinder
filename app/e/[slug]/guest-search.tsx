"use client";

import { useEffect, useState, useTransition } from "react";
import { Search, Armchair } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import type { GuestMatch } from "@/repositories/public-search";
import { searchGuestsAction } from "./actions";

export function GuestSearch({ slug }: { slug: string }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<GuestMatch[] | null>(null);
  const [pending, startTransition] = useTransition();

  useEffect(() => {
    if (query.trim().length < 2) return;
    const timeout = setTimeout(() => {
      startTransition(async () => {
        const matches = await searchGuestsAction(slug, query);
        setResults(matches);
      });
    }, 250);
    return () => clearTimeout(timeout);
  }, [query, slug]);

  // Dérivé au rendu plutôt que réinitialisé dans l'effet : évite un
  // setState synchrone dans useEffect, et empêche un résultat obsolète
  // de s'afficher pendant que la requête raccourcie repasse sous 2 caractères.
  const visibleResults = query.trim().length >= 2 ? results : null;

  return (
    <div className="w-full space-y-4">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-neutral-400" />
        <Input
          autoFocus
          placeholder="Votre nom..."
          className="h-12 pl-10 text-base"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>

      {query.trim().length > 0 && query.trim().length < 2 && (
        <p className="text-center text-sm text-neutral-400">
          Continuez à taper (2 caractères minimum)
        </p>
      )}

      {pending && <p className="text-center text-sm text-neutral-400">Recherche...</p>}

      {!pending && visibleResults && visibleResults.length === 0 && (
        <p className="text-center text-sm text-neutral-500">
          Aucun invité trouvé pour « {query} ».
        </p>
      )}

      {!pending && visibleResults && visibleResults.length > 0 && (
        <div className="space-y-2">
          {visibleResults.map((guest) => (
            <Card key={guest.guest_id}>
              <CardContent className="flex items-center justify-between p-4">
                <span className="font-medium">
                  {[guest.first_name, guest.last_name].filter(Boolean).join(" ")}
                </span>
                {guest.table_number ? (
                  <span className="flex items-center gap-1.5 text-sm font-medium text-neutral-900">
                    <Armchair className="size-4" />
                    Table {guest.table_number}
                    {guest.table_name ? ` — ${guest.table_name}` : ""}
                  </span>
                ) : (
                  <span className="text-sm text-neutral-400">Table à venir</span>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
