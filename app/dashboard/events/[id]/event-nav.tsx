"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export function EventNav({ eventId }: { eventId: string }) {
  const pathname = usePathname();
  const base = `/dashboard/events/${eventId}`;
  const tabs = [
    { href: base, label: "Réglages", exact: true },
    { href: `${base}/tables`, label: "Tables" },
    { href: `${base}/guests`, label: "Invités" },
    { href: `${base}/import`, label: "Import CSV" },
    { href: `${base}/qr`, label: "QR Code" },
  ];

  return (
    <nav className="flex gap-1 border-b border-neutral-200">
      {tabs.map((tab) => {
        const active = tab.exact ? pathname === tab.href : pathname.startsWith(tab.href);
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={cn(
              "border-b-2 px-3 py-2 text-sm font-medium transition-colors",
              active
                ? "border-neutral-900 text-neutral-900"
                : "border-transparent text-neutral-500 hover:text-neutral-900",
            )}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
