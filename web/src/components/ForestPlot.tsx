import { useId, useMemo, useState } from "react";
import { scaleLinear } from "d3-scale";
import type { Estimate, Reliability, Role } from "~/generated/types";
import { ROLE_LABELS, formatInteger, formatNumber } from "~/lib/format";

/**
 * Le graphique canonique des méta-analyses cliniques, appliqué au classement de joueurs.
 *
 * Il rend visible ce qu'aucun tableau ne montre : qui est vraiment devant, et qui n'est
 * devant que par manque de données. La largeur d'un intervalle EST la donnée — elle n'est
 * jamais normalisée pour l'esthétique, quitte à ce qu'une ligne déborde des autres.
 */

export interface ForestRow {
  slug: string;
  name: string;
  role: Role;
  team: string;
  games: number;
  estimate: Estimate;
  reliability: Reliability;
}

export type SortMode = "point" | "lower";

interface Props {
  rows: ForestRow[];
  /** Médiane de la ligue, tracée en pointillé comme repère de lecture. */
  reference?: number;
  referenceLabel?: string;
  confidenceLevel: number;
  sortable?: boolean;
  initialSort?: SortMode;
  /** Lien vers la fiche joueur. Absent, les lignes ne sont pas cliquables. */
  linkPrefix?: string;
  emptyMessage?: string;
  /** Au-delà, seules les premières lignes sont tracées et la troncature est annoncée. */
  maxRows?: number;
}

const ROW_HEIGHT = 30;
const MARGIN = { top: 26, right: 24, bottom: 34, left: 330 };
const WIDTH = 1000;

/**
 * En deçà, les libellés deviennent illisibles : le conteneur défile plutôt que d'écraser
 * le graphique. Mieux vaut faire glisser que ne rien pouvoir lire.
 */
const MIN_READABLE_WIDTH = 660;

export default function ForestPlot({
  rows,
  reference,
  referenceLabel = "médiane de la ligue",
  confidenceLevel,
  sortable = false,
  initialSort = "point",
  linkPrefix,
  emptyMessage = "Aucun joueur ne correspond à ce filtre. Élargissez la plage de games.",
  maxRows = 40,
}: Props) {
  const [sort, setSort] = useState<SortMode>(initialSort);
  const [hovered, setHovered] = useState<string | null>(null);
  const titleId = useId();

  const all = useMemo(() => {
    const copy = [...rows];
    copy.sort((a, b) =>
      sort === "point" ? b.estimate.point - a.estimate.point : b.estimate.lower - a.estimate.lower,
    );
    return copy;
  }, [rows, sort]);

  const sorted = useMemo(() => all.slice(0, maxRows), [all, maxRows]);
  const truncated = all.length - sorted.length;

  const domain = useMemo(() => {
    if (sorted.length === 0) return [0, 100] as const;
    const lows = sorted.map((row) => row.estimate.lower);
    const highs = sorted.map((row) => row.estimate.upper);
    const min = Math.min(...lows, reference ?? Infinity);
    const max = Math.max(...highs, reference ?? -Infinity);
    const padding = Math.max((max - min) * 0.06, 0.5);
    return [min - padding, max + padding] as const;
  }, [sorted, reference]);

  if (sorted.length === 0) {
    return (
      <p className="border border-rule bg-panel p-6 text-muted" role="status">
        {emptyMessage}
      </p>
    );
  }

  const height = MARGIN.top + sorted.length * ROW_HEIGHT + MARGIN.bottom;
  const x = scaleLinear()
    .domain([domain[0], domain[1]])
    .range([MARGIN.left, WIDTH - MARGIN.right]);
  const ticks = x.ticks(5);

  const summary =
    `Classement de ${sorted.length} joueurs par indice de valeur, ` +
    `chaque estimation accompagnée de son intervalle à ${formatNumber(confidenceLevel * 100, 0)} %. ` +
    `En tête : ${sorted[0]?.name} à ${formatNumber(sorted[0]?.estimate.point ?? 0, 1)}. ` +
    `Le tableau équivalent suit ce graphique.`;

  return (
    <figure className="m-0">
      {sortable && (
        <div className="mb-3 flex flex-wrap items-baseline gap-3 text-sm">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Trier par</span>
          {(
            [
              ["point", "estimation"],
              ["lower", "borne basse"],
            ] as const
          ).map(([mode, label]) => (
            <button
              key={mode}
              type="button"
              onClick={() => setSort(mode)}
              aria-pressed={sort === mode}
              className={
                sort === mode
                  ? "border border-ink px-2 py-0.5 font-medium"
                  : "border border-rule px-2 py-0.5 text-muted hover:border-ink hover:text-ink"
              }
            >
              {label}
            </button>
          ))}
          {sort === "lower" && (
            <span className="text-muted">Qui est solidement bon, plutôt que qui est en tête.</span>
          )}
        </div>
      )}

      <div
        className="overflow-x-auto"
        tabIndex={0}
        role="region"
        aria-label="Graphique des estimations, défilement horizontal sur petit écran"
      >
      <svg
        viewBox={`0 0 ${WIDTH} ${height}`}
        width="100%"
        role="img"
        aria-labelledby={titleId}
        style={{ display: "block", width: "100%", minWidth: MIN_READABLE_WIDTH }}
      >
        <title id={titleId}>{summary}</title>

        <g aria-hidden="true">
          <text x={8} y={16} className="fill-muted" fontSize={12} fontFamily="var(--font-mono)">
            RÔLE
          </text>
          <text x={64} y={16} className="fill-muted" fontSize={12} fontFamily="var(--font-mono)">
            JOUEUR
          </text>
          <text x={210} y={16} textAnchor="end" className="fill-muted" fontSize={12} fontFamily="var(--font-mono)">
            n
          </text>
          <text x={296} y={16} textAnchor="end" className="fill-muted" fontSize={12} fontFamily="var(--font-mono)">
            INDICE
          </text>
        </g>

        {reference !== undefined && (
          <g aria-hidden="true">
            <line
              x1={x(reference)}
              x2={x(reference)}
              y1={MARGIN.top - 6}
              y2={MARGIN.top + sorted.length * ROW_HEIGHT}
              stroke="var(--color-rule)"
              strokeDasharray="3 4"
            />
            <text
              x={x(reference)}
              y={MARGIN.top - 12}
              textAnchor="middle"
              fontSize={11}
              fontFamily="var(--font-mono)"
              className="fill-muted"
            >
              {referenceLabel}
            </text>
          </g>
        )}

        {sorted.map((row, index) => {
          const y = MARGIN.top + index * ROW_HEIGHT + ROW_HEIGHT / 2;
          const isHovered = hovered === row.slug;
          const content = (
            <>
              <rect
                className="forest-row-band"
                x={0}
                y={y - ROW_HEIGHT / 2}
                width={WIDTH}
                height={ROW_HEIGHT}
                fill="transparent"
              />
              <text x={8} y={y + 4} fontSize={12} fontFamily="var(--font-mono)" className="fill-muted">
                {ROLE_LABELS[row.role]}
              </text>
              <text x={64} y={y + 4} fontSize={13} className="fill-ink">
                {row.name}
              </text>
              <text
                x={210}
                y={y + 4}
                textAnchor="end"
                fontSize={12}
                fontFamily="var(--font-mono)"
                className="fill-muted"
              >
                {formatInteger(row.games)}
              </text>

              {/* Moustaches : deux moitiés tracées depuis le point vers l'extérieur. */}
              {(["lower", "upper"] as const).map((side) => (
                <line
                  key={side}
                  className="forest-whisker"
                  x1={x(row.estimate.point)}
                  x2={x(row.estimate[side])}
                  y1={y}
                  y2={y}
                  stroke="var(--color-rule)"
                  strokeWidth={1.5}
                  pathLength={1}
                  strokeDasharray={1}
                  style={{ animationDelay: `${index * 20}ms` }}
                />
              ))}
              {(["lower", "upper"] as const).map((side) => (
                <line
                  key={`cap-${side}`}
                  x1={x(row.estimate[side])}
                  x2={x(row.estimate[side])}
                  y1={y - 5}
                  y2={y + 5}
                  stroke="var(--color-rule)"
                  strokeWidth={1.5}
                />
              ))}

              <circle
                data-estimate-mark
                cx={x(row.estimate.point)}
                cy={y}
                r={4}
                fill="var(--color-mark)"
              />

              <text
                x={296}
                y={y + 4}
                textAnchor="end"
                fontSize={13}
                fontFamily="var(--font-mono)"
                className="fill-ink"
              >
                {formatNumber(row.estimate.point, 1)}
              </text>
              {row.reliability === "low" && (
                <text x={306} y={y + 4} fontSize={13} className="fill-flag">
                  ⚑
                </text>
              )}

              {isHovered && (
                <text
                  x={64}
                  y={y + 18}
                  fontSize={11}
                  fontFamily="var(--font-mono)"
                  className="fill-muted"
                >
                  {row.team} · {formatNumber(row.estimate.lower, 1)} – {formatNumber(row.estimate.upper, 1)}
                </text>
              )}
            </>
          );

          // Le §5.3 décrit ce graphique comme une image accompagnée d'une table équivalente.
          // Il ne contient donc aucun lien : un contenu interactif dans un élément annoncé
          // comme atomique est inaccessible, et un tabindex négatif n'y change rien. Le clic
          // reste un raccourci pour la souris ; le clavier passe par la vue tableau.
          const shared = {
            className: "forest-row",
            onMouseEnter: () => setHovered(row.slug),
            onMouseLeave: () => setHovered(null),
          };

          return linkPrefix ? (
            <g
              key={row.slug}
              {...shared}
              style={{ cursor: "pointer" }}
              onClick={() => {
                window.location.href = `${linkPrefix}${row.slug}`;
              }}
            >
              {content}
            </g>
          ) : (
            <g key={row.slug} {...shared}>
              {content}
            </g>
          );
        })}

        <g aria-hidden="true">
          {ticks.map((tick) => (
            <g key={tick}>
              <line
                x1={x(tick)}
                x2={x(tick)}
                y1={MARGIN.top + sorted.length * ROW_HEIGHT}
                y2={MARGIN.top + sorted.length * ROW_HEIGHT + 5}
                stroke="var(--color-rule)"
              />
              <text
                x={x(tick)}
                y={MARGIN.top + sorted.length * ROW_HEIGHT + 20}
                textAnchor="middle"
                fontSize={11}
                fontFamily="var(--font-mono)"
                className="fill-muted"
              >
                {formatNumber(tick, 0)}
              </text>
            </g>
          ))}
        </g>
      </svg>
      </div>

      {/* Table équivalente : le graphique n'est pas la seule façon de lire ces chiffres.
          Le masquage porte sur le conteneur — une table ne se laisse pas réduire à 1px. */}
      <div className="sr-only">
      <table>
        <caption>{summary}</caption>
        <thead>
          <tr>
            <th scope="col">Rôle</th>
            <th scope="col">Joueur</th>
            <th scope="col">Équipe</th>
            <th scope="col">Games</th>
            <th scope="col">Indice</th>
            <th scope="col">Borne basse</th>
            <th scope="col">Borne haute</th>
            <th scope="col">Fiabilité</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((row) => (
            <tr key={row.slug}>
              <td>{ROLE_LABELS[row.role]}</td>
              <td>{row.name}</td>
              <td>{row.team}</td>
              <td>{formatInteger(row.games)}</td>
              <td>{formatNumber(row.estimate.point, 1)}</td>
              <td>{formatNumber(row.estimate.lower, 1)}</td>
              <td>{formatNumber(row.estimate.upper, 1)}</td>
              <td>{row.reliability}</td>
            </tr>
          ))}
        </tbody>
      </table>
      </div>

      {truncated > 0 && (
        <figcaption className="mt-3 text-sm text-muted">
          {sorted.length} premières lignes sur {all.length}. Les {truncated} suivantes existent :
          affinez les filtres, ou passez en tableau pour les voir toutes.
        </figcaption>
      )}
    </figure>
  );
}
