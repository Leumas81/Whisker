import { useMemo, useState } from "react";
import type { LeagueId, Player, Role } from "~/generated/types";
import ForestPlot, { type ForestRow } from "./ForestPlot";
import { ROLE_LABELS, formatInteger, formatNumber, formatShare } from "~/lib/format";

/**
 * Filtres, tri et bascule tableau / forest plot sur les mêmes données.
 *
 * Quatre cents joueurs tiennent en mémoire : tout le filtrage se fait dans le navigateur,
 * sans requête. Le défaut de 25 games vient du §6.2 ; les joueurs à faible échantillon sont
 * exclus des classements par défaut, mais restent atteignables en abaissant le seuil.
 */

interface Props {
  players: Player[];
  confidenceLevel: number;
}

const ROLES: Role[] = ["top", "jng", "mid", "adc", "sup"];
type SortKey = "index" | "lower" | "age" | "games" | "contract";

export default function PlayerExplorer({ players, confidenceLevel }: Props) {
  const [view, setView] = useState<"table" | "plot">("plot");
  const [query, setQuery] = useState("");
  const [league, setLeague] = useState<LeagueId | "toutes">("toutes");
  const [role, setRole] = useState<Role | "tous">("tous");
  const [minGames, setMinGames] = useState(25);
  const [sortKey, setSortKey] = useState<SortKey>("index");

  const leagues = useMemo(
    () => Array.from(new Set(players.map((player) => player.league))).sort(),
    [players],
  );

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const kept = players.filter((player) => {
      if (player.games < minGames) return false;
      if (league !== "toutes" && player.league !== league) return false;
      if (role !== "tous" && player.role !== role) return false;
      if (needle && !player.name.toLowerCase().includes(needle)) return false;
      return true;
    });

    const compare: Record<SortKey, (a: Player, b: Player) => number> = {
      index: (a, b) => b.valueIndex.point - a.valueIndex.point,
      lower: (a, b) => b.valueIndex.lower - a.valueIndex.lower,
      age: (a, b) => a.age - b.age,
      games: (a, b) => b.games - a.games,
      contract: (a, b) =>
        (a.contractEnd ?? "9999").localeCompare(b.contractEnd ?? "9999"),
    };
    return [...kept].sort(compare[sortKey]);
  }, [players, query, league, role, minGames, sortKey]);

  const rows: ForestRow[] = filtered.map((player) => ({
    slug: player.slug,
    name: player.name,
    role: player.role,
    team: player.team,
    games: player.games,
    estimate: player.valueIndex,
    reliability: player.reliability,
  }));

  const median = useMemo(() => {
    if (filtered.length === 0) return undefined;
    const values = filtered.map((player) => player.valueIndex.point).sort((a, b) => a - b);
    const middle = Math.floor(values.length / 2);
    return values.length % 2 === 0
      ? ((values[middle - 1] ?? 0) + (values[middle] ?? 0)) / 2
      : values[middle];
  }, [filtered]);

  const field = "border border-rule bg-paper px-2 py-1 text-sm";

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-end gap-4 border border-rule bg-panel p-4">
        <label className="flex flex-col gap-1">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Nom</span>
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Rechercher"
            className={field}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Ligue</span>
          <select
            value={league}
            onChange={(event) => setLeague(event.target.value as LeagueId | "toutes")}
            className={field}
          >
            <option value="toutes">Toutes</option>
            {leagues.map((id) => (
              <option key={id} value={id}>
                {id}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Rôle</span>
          <select
            value={role}
            onChange={(event) => setRole(event.target.value as Role | "tous")}
            className={field}
          >
            <option value="tous">Tous</option>
            {ROLES.map((id) => (
              <option key={id} value={id}>
                {ROLE_LABELS[id]}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">
            Games minimum : <span data-numeric>{minGames}</span>
          </span>
          <input
            type="range"
            min={10}
            max={120}
            step={5}
            value={minGames}
            onChange={(event) => setMinGames(Number(event.target.value))}
            className="w-40"
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className="font-mono text-xs uppercase tracking-wide text-muted">Trier par</span>
          <select
            value={sortKey}
            onChange={(event) => setSortKey(event.target.value as SortKey)}
            className={field}
          >
            <option value="index">Indice</option>
            <option value="lower">Borne basse</option>
            <option value="age">Âge</option>
            <option value="games">Games</option>
            <option value="contract">Fin de contrat</option>
          </select>
        </label>

        <div className="ml-auto flex gap-2">
          {(
            [
              ["plot", "Graphique"],
              ["table", "Tableau"],
            ] as const
          ).map(([mode, label]) => (
            <button
              key={mode}
              type="button"
              onClick={() => setView(mode)}
              aria-pressed={view === mode}
              className={
                view === mode
                  ? "border border-ink px-3 py-1 text-sm font-medium"
                  : "border border-rule px-3 py-1 text-sm text-muted hover:border-ink hover:text-ink"
              }
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <p className="mb-4 font-mono text-xs uppercase tracking-wide text-muted">
        <span data-numeric>{formatInteger(filtered.length)}</span> joueurs · indice de valeur ·
        IC&nbsp;{formatNumber(confidenceLevel * 100, 0)}&nbsp;%
      </p>

      {view === "plot" ? (
        <ForestPlot
          rows={rows}
          reference={median}
          referenceLabel="médiane du filtre"
          confidenceLevel={confidenceLevel}
          linkPrefix="/joueur/"
        />
      ) : (
        <PlayerTable players={filtered} />
      )}
    </div>
  );
}

function PlayerTable({ players }: { players: Player[] }) {
  if (players.length === 0) {
    return (
      <p className="border border-rule bg-panel p-6 text-muted" role="status">
        Aucun joueur ne correspond à ce filtre. Élargissez la plage de games.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto" tabIndex={0} role="region" aria-label="Classement des joueurs">
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-rule text-left font-mono text-xs uppercase tracking-wide text-muted">
            <th scope="col" className="py-2 pr-3">Rôle</th>
            <th scope="col" className="py-2 pr-3">Joueur</th>
            <th scope="col" className="py-2 pr-3">Équipe</th>
            <th scope="col" className="py-2 pr-3 text-right">n</th>
            <th scope="col" className="py-2 pr-3 text-right">Indice · IC 80 %</th>
            <th scope="col" className="py-2 pr-3 text-right">Part joueur</th>
            <th scope="col" className="py-2 text-right">Quintile</th>
          </tr>
        </thead>
        <tbody>
          {players.map((player) => (
            <tr key={player.slug} className="border-b border-rule/60 hover:bg-panel">
              <td className="py-2 pr-3 font-mono text-xs text-muted">{ROLE_LABELS[player.role]}</td>
              <td className="py-2 pr-3">
                <a href={`/joueur/${player.slug}`} className="underline underline-offset-2">
                  {player.name}
                </a>
                {player.reliability === "low" && <span className="ml-1 text-flag">⚑</span>}
              </td>
              <td className="py-2 pr-3 text-muted">{player.team}</td>
              <td className="py-2 pr-3 text-right" data-numeric>{formatInteger(player.games)}</td>
              <td className="py-2 pr-3 text-right" data-numeric>
                <span data-estimate-mark className="font-medium text-mark">
                  {formatNumber(player.valueIndex.point, 1)}
                </span>
                <span className="text-muted">
                  {" ["}
                  {formatNumber(player.valueIndex.lower, 1)}&nbsp;–&nbsp;
                  {formatNumber(player.valueIndex.upper, 1)}
                  {"]"}
                </span>
              </td>
              <td className="py-2 pr-3 text-right text-muted" data-numeric>
                {formatShare(player.playerShare)}
              </td>
              <td className="py-2 text-right" data-numeric>
                {player.salaryQuintile ?? "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
