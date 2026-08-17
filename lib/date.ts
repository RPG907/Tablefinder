/**
 * event_date est une simple date calendaire "YYYY-MM-DD" (voir le
 * setTypeParser dans db/client.ts). La formater via
 * `new Date(value).toLocaleDateString(...)` sans fuseau explicite
 * parserait la chaîne comme minuit UTC puis l'afficherait dans le
 * fuseau local du serveur — un décalage d'un jour est possible selon
 * ce fuseau. `timeZone: "UTC"` couplé à `Date.UTC(...)` élimine toute
 * dépendance au fuseau d'exécution.
 */
const formatter = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

export function formatEventDate(value: string | null | undefined): string | null {
  if (!value) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return null;
  const [, year, month, day] = match;
  return formatter.format(new Date(Date.UTC(Number(year), Number(month) - 1, Number(day))));
}
