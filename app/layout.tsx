import type { Metadata } from "next";
import "./globals.css";
import { Toaster } from "@/components/ui/sonner";

export const metadata: Metadata = {
  title: "TableFinder",
  description: "Trouvez votre table en un scan.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr">
      <body className="min-h-dvh bg-neutral-50 text-neutral-900 antialiased">
        {children}
        <Toaster position="top-center" />
      </body>
    </html>
  );
}
