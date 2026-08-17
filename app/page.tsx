import Link from "next/link";
import { redirect } from "next/navigation";
import { getUser } from "@/lib/session";
import { Button } from "@/components/ui/button";
import { QrCode, Search, Users } from "lucide-react";

export default async function Home() {
  const user = await getUser();
  if (user) redirect("/dashboard");

  return (
    <main className="mx-auto flex min-h-dvh max-w-3xl flex-col items-center justify-center gap-10 px-6 py-16 text-center">
      <div className="space-y-4">
        <h1 className="text-4xl font-semibold tracking-tight sm:text-5xl">
          TableFinder
        </h1>
        <p className="mx-auto max-w-xl text-balance text-neutral-500">
          Créez votre liste d&apos;invités, assignez une table à chacun, générez
          un QR Code. Vos invités le scannent, cherchent leur nom, voient leur
          table. Aucune application à installer.
        </p>
      </div>

      <div className="flex gap-3">
        <Button asChild size="lg">
          <Link href="/inscription">Créer un compte</Link>
        </Button>
        <Button asChild size="lg" variant="outline">
          <Link href="/connexion">Se connecter</Link>
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-6 pt-8 text-left sm:grid-cols-3">
        <Feature
          icon={<Users className="size-5" />}
          title="Invités & tables"
          description="Créez vos tables et assignez chaque invité en quelques clics, ou importez un CSV."
        />
        <Feature
          icon={<QrCode className="size-5" />}
          title="Un QR Code"
          description="Personnalisable aux couleurs de votre événement, avec votre logo."
        />
        <Feature
          icon={<Search className="size-5" />}
          title="Recherche instantanée"
          description="Vos invités scannent, tapent leur nom, trouvent leur table. C'est tout."
        />
      </div>
    </main>
  );
}

function Feature({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  return (
    <div className="space-y-2 rounded-xl border border-neutral-200 bg-white p-5">
      <div className="flex size-9 items-center justify-center rounded-lg bg-neutral-900 text-neutral-50">
        {icon}
      </div>
      <h3 className="font-medium">{title}</h3>
      <p className="text-sm text-neutral-500">{description}</p>
    </div>
  );
}
