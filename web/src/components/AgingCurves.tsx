import { useEffect, useMemo, useRef, useState } from "react";
import * as Plot from "@observablehq/plot";
import type { AgingFile, Role } from "~/generated/types";
import { ROLE_LABELS, formatNumber } from "~/lib/format";

/**
 * Courbes de vieillissement par rôle, rubans d'incertitude natifs.
 *
 * Les deux variantes sont permutables, jamais fusionnées : le §4.4 veut que le biais de
 * survie reste visible plutôt qu'arbitré en coulisses.
 */

interface Props {
  aging: AgingFile;
  confidenceLevel: number;
}

const ROLES: Role[] = ["top", "jng", "mid", "adc", "sup"];

export default function AgingCurves({ aging, confidenceLevel }: Props) {
  const [variantId, setVariantId] = useState(aging.variants[0]?.id ?? "all");
  const [selected, setSelected] = useState<Role[]>(["mid"]);
  const container = useRef<HTMLDivElement>(null);

  const variant = useMemo(
    () => aging.variants.find((candidate) => candidate.id === variantId) ?? aging.variants[0],
    [aging, variantId],
  );

  const series = useMemo(() => {
    if (!variant) return [];
    return variant.curves
      .filter((curve) => selected.includes(curve.role))
      .flatMap((curve) =>
        curve.points.map((point) => ({
          age: point.age,
          role: ROLE_LABELS[curve.role] ?? curve.role,
          point: point.value.point,
          lower: point.value.lower,
          upper: point.value.upper,
        })),
      );
  }, [variant, selected]);

  const peaks = useMemo(
    () => (variant?.curves ?? []).filter((curve) => selected.includes(curve.role)),
    [variant, selected],
  );

  useEffect(() => {
    const node = container.current;
    if (!node) return;
    node.replaceChildren();
    if (series.length === 0) return;

    const chart = Plot.plot({
      width: 900,
      height: 420,
      marginLeft: 52,
      marginBottom: 44,
      style: { background: "transparent", fontFamily: "var(--font-sans)", fontSize: "12px" },
      x: { label: "Âge (années) →", tickFormat: (d: number) => String(d), grid: false },
      y: { label: "↑ Performance (écarts-types)", grid: true },
      color: { legend: true, scheme: "greys" },
      marks: [
        Plot.areaY(series, {
          x: "age",
          y1: "lower",
          y2: "upper",
          fill: "var(--color-panel)",
          fillOpacity: 0.75,
          z: "role",
        }),
        Plot.line(series, { x: "age", y: "point", stroke: "var(--color-ink)", strokeWidth: 1.5, z: "role" }),
        Plot.ruleY([0], { stroke: "var(--color-rule)", strokeDasharray: "3 4" }),
      ],
    });

    node.append(chart);

    // Observable Plot étiquette ses groupes de marques avec un aria-label, sur des <g> qui
    // ne portent aucun rôle : axe le refuse, et ces étiquettes n'apprennent rien — la
    // description utile est celle du conteneur.
    for (const group of chart.querySelectorAll("g[aria-label]")) {
      group.removeAttribute("aria-label");
    }

    return () => chart.remove();
  }, [series]);

  if (!variant) return null;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-end gap-4">
        <fieldset className="flex flex-wrap items-center gap-2 border-0 p-0">
          <legend className="sr-only">Rôles affichés</legend>
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Rôles</span>
          {ROLES.map((role) => {
            const active = selected.includes(role);
            return (
              <button
                key={role}
                type="button"
                aria-pressed={active}
                onClick={() =>
                  setSelected((current) =>
                    current.includes(role)
                      ? current.filter((value) => value !== role)
                      : [...current, role],
                  )
                }
                className={
                  active
                    ? "border border-ink px-2 py-0.5 text-sm font-medium"
                    : "border border-rule px-2 py-0.5 text-sm text-muted hover:border-ink hover:text-ink"
                }
              >
                {ROLE_LABELS[role]}
              </button>
            );
          })}
        </fieldset>

        <label className="ml-auto flex flex-col gap-1">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Échantillon</span>
          <select
            value={variantId}
            onChange={(event) => setVariantId(event.target.value as typeof variantId)}
            className="border border-rule bg-paper px-2 py-1 text-sm"
          >
            {aging.variants.map((candidate) => (
              <option key={candidate.id} value={candidate.id}>
                {candidate.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div ref={container} role="img" aria-label={
        `Courbes de vieillissement pour ${peaks.map((c) => ROLE_LABELS[c.role]).join(", ")}, ` +
        `variante « ${variant.label} », rubans à ${formatNumber(confidenceLevel * 100, 0)} %.`
      } />

      {selected.length === 0 && (
        <p className="border border-rule bg-panel p-6 text-muted" role="status">
          Aucun rôle sélectionné. Choisissez-en au moins un.
        </p>
      )}

      {peaks.length > 0 && (
        <table className="mt-6 w-full border-collapse text-sm">
          <caption className="mb-2 text-left font-mono text-xs uppercase tracking-wide text-muted">
            Âge de pic · IC&nbsp;{formatNumber(confidenceLevel * 100, 0)}&nbsp;% · variante «&nbsp;{variant.label}&nbsp;»
          </caption>
          <thead>
            <tr className="border-b border-rule text-left font-mono text-xs uppercase tracking-wide text-muted">
              <th scope="col" className="py-2 pr-3">Rôle</th>
              <th scope="col" className="py-2 pr-3 text-right">Âge de pic</th>
              <th scope="col" className="py-2 pr-3 text-right">Joueurs</th>
              <th scope="col" className="py-2 text-right">Games</th>
            </tr>
          </thead>
          <tbody>
            {peaks.map((curve) => (
              <tr key={curve.role} className="border-b border-rule/60">
                <td className="py-2 pr-3 font-mono text-xs">{ROLE_LABELS[curve.role]}</td>
                <td className="py-2 pr-3 text-right" data-numeric>
                  <span data-estimate-mark className="font-medium text-mark">
                    {formatNumber(curve.peakAge.point, 1)}
                  </span>
                  <span className="text-muted">
                    {" ["}
                    {formatNumber(curve.peakAge.lower, 1)}&nbsp;–&nbsp;
                    {formatNumber(curve.peakAge.upper, 1)}
                    {"]"}
                  </span>
                </td>
                <td className="py-2 pr-3 text-right text-muted" data-numeric>{curve.nPlayers}</td>
                <td className="py-2 text-right text-muted" data-numeric>{curve.nGames}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <p className="mt-6 border border-flag bg-panel p-4 text-sm">
        <strong>Biais de survie.</strong> {variant.survivorshipNote}
      </p>
    </div>
  );
}
