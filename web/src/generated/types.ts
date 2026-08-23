/**
 * FICHIER GÉNÉRÉ — NE PAS ÉDITER À LA MAIN.
 *
 * Source : schemas/*.schema.json
 * Régénérer : pnpm gen:types
 *
 * Toute modification manuelle sera écrasée, et « pnpm verify » échouera tant que
 * ce fichier ne correspondra pas exactement aux schémas.
 */

/**
 * Identifiant d'URL, stable dans le temps. Minuscules, chiffres et tirets.
 */
export type Slug = string;
/**
 * Poste occupé. Les lignes agrégées d'équipe (position == 'team' chez Oracle's Elixir) ne sont jamais exportées comme joueur.
 */
export type Role = "top" | "jng" | "mid" | "adc" | "sup";
/**
 * Ligue régulière couverte. L'extension (LCK, LPL, LCS, autres ERL) se fait en ajoutant une valeur ici : les types TypeScript suivent automatiquement.
 */
export type LeagueId = "LEC" | "LFL";
/**
 * Date au format AAAA-MM-JJ.
 */
export type IsoDate = string;
/**
 * Dérivé du nombre de games : >= 60 high, 25-59 medium, 10-24 low. En dessous de 10 games le joueur n'est pas exporté.
 */
export type Reliability = "high" | "medium" | "low";
/**
 * Année de la saison compétitive.
 */
export type Season = number;
/**
 * D'où vient l'identification de l'effet de ligue. 'transfers' : joueurs ayant changé de ligue. 'international' : rencontres Worlds, MSI, EMEA Masters.
 */
export type IdentificationSource = "transfers" | "international";
/**
 * Regroupement de tous les jeux de données du site. Type de commodité : aucun fichier ne porte cette forme.
 */
export interface WhiskerData {
  players: PlayersFile;
  leagues: LeaguesFile;
  aging: AgingFile;
  salary: SalaryFile;
  meta: MetaFile;
}
/**
 * Contenu de web/src/data/players.json. La provenance (date de génération, hash du pipeline) vit dans meta.json et n'est pas dupliquée ici.
 */
export interface PlayersFile {
  /**
   * @minItems 0
   */
  players: Player[];
}
export interface Player {
  slug: Slug;
  /**
   * Pseudo affiché, dans sa graphie courante.
   */
  name: string;
  role: Role;
  /**
   * Équipe actuelle, en texte. Aucun logo n'est stocké ni affiché (§8).
   */
  team: string;
  league: LeagueId;
  /**
   * Âge en années à la date de dernière donnée.
   */
  age: number;
  /**
   * Fin de contrat connue, ou null si Leaguepedia ne la documente pas.
   */
  contractEnd: IsoDate | null;
  /**
   * Games retenues sur la période. Le minimum de 10 est structurel : en dessous, le joueur n'est pas exporté (§3.4).
   */
  games: number;
  valueIndex: Estimate;
  playerShare: UnitEstimate;
  /**
   * Performance LEC attendue, sur l'échelle unité. null pour un joueur déjà en LEC : la question ne se pose pas.
   */
  lecEquivalent: UnitEstimate | null;
  /**
   * Quintile salarial dans sa ligue, ou null si la ligue n'a pas de distribution calibrée. Le null est un résultat, pas une donnée manquante : il signifie que les sources publiques ne permettent pas d'estimer, et le site l'affiche comme tel.
   */
  salaryQuintile: number | null;
  salaryBand: Band | null;
  reliability: Reliability;
  /**
   * Trajectoire par saison, la plus ancienne d'abord.
   */
  history: SeasonRecord[];
}
/**
 * Estimation ponctuelle accompagnée de son intervalle. Le niveau de confiance est global au jeu de données et porté par meta.json (confidenceLevel).
 */
export interface Estimate {
  /**
   * Estimation ponctuelle.
   */
  point: number;
  /**
   * Borne basse de l'intervalle.
   */
  lower: number;
  /**
   * Borne haute de l'intervalle.
   */
  upper: number;
}
/**
 * Estimation contrainte à l'intervalle unité — proportions, parts de variance, coefficients d'équivalence. Même forme que Estimate ; un test unitaire vérifie que les deux définitions gardent exactement les mêmes champs.
 */
export interface UnitEstimate {
  /**
   * Estimation ponctuelle.
   */
  point: number;
  /**
   * Borne basse de l'intervalle.
   */
  lower: number;
  /**
   * Borne haute de l'intervalle.
   */
  upper: number;
}
/**
 * Fourchette sans estimation ponctuelle. Utilisée pour les salaires : l'absence de champ 'point' est délibérée et structurelle (§6.6 du brief).
 */
export interface Band {
  lower: number;
  upper: number;
}
export interface SeasonRecord {
  season: Season;
  league: LeagueId;
  team: string;
  games: number;
  valueIndex: Estimate;
}
/**
 * Contenu de web/src/data/leagues.json : forces de ligue par saison et coefficients d'équivalence entre ligues.
 */
export interface LeaguesFile {
  /**
   * Une entrée par ligue, saison et source d'identification. Les deux sources sont rapportées séparément et jamais moyennées (§4.1).
   */
  strengths: LeagueStrength[];
  equivalences: Equivalence[];
}
export interface LeagueStrength {
  league: LeagueId;
  season: Season;
  source: IdentificationSource;
  strength: Estimate;
  nPlayers: number;
  nGames: number;
}
/**
 * Traduction d'une performance d'une ligue vers une autre.
 */
export interface Equivalence {
  from: LeagueId;
  to: LeagueId;
  coefficient: UnitEstimate;
  /**
   * Nombre de trajets observés depuis 2019. C'est la taille d'échantillon affichée à côté du taux de base (§6.4).
   */
  nTransitions: number;
  /**
   * Traitement appliqué au biais de sélection. 'none' signifie que le biais est documenté mais non corrigé, et doit être affiché comme tel.
   */
  selectionCorrection: "none" | "heckman";
  retentionOneYear: UnitEstimate;
}
/**
 * Contenu de web/src/data/aging.json : courbes de vieillissement par rôle. Deux variantes sont toujours exportées afin que le biais de survie reste visible plutôt qu'arbitré en silence (§4.4).
 */
export interface AgingFile {
  /**
   * @minItems 1
   */
  variants: [AgingVariant, ...AgingVariant[]];
}
export interface AgingVariant {
  /**
   * 'all' : tous les joueurs, courbe sujette au biais de survie. 'tenured' : restriction aux joueurs ayant au moins N saisons.
   */
  id: "all" | "tenured";
  /**
   * Libellé affiché, en français.
   */
  label: string;
  /**
   * Ce que cette variante corrige et ce qu'elle laisse passer. Affiché sans clic (§6.5).
   */
  survivorshipNote: string;
  /**
   * Seuil de saisons appliqué pour construire la variante.
   */
  minSeasons: number;
  curves: AgingCurve[];
}
export interface AgingCurve {
  role: Role;
  peakAge: Estimate;
  nPlayers: number;
  nGames: number;
  /**
   * Grille d'âges régulière, croissante.
   *
   * @minItems 2
   */
  points: [AgingCurvePoint, AgingCurvePoint, ...AgingCurvePoint[]];
}
export interface AgingCurvePoint {
  age: number;
  value: Estimate;
}
/**
 * Contenu de web/src/data/salary.json : paramètres log-normaux par ligue et ancres sourcées. Aucun montant nominatif n'apparaît ici — l'attribution individuelle se fait par quintile et fourchette dans players.json (§6.6).
 */
export interface SalaryFile {
  /**
   * Uniquement les ligues effectivement calibrées. Une ligue absente d'ici est présente dans « excluded », jamais nulle part.
   */
  distributions: SalaryDistribution[];
  /**
   * Ligues volontairement non calibrées, avec la raison. Rendre l'absence explicite est le seul moyen de la distinguer d'un oubli.
   */
  excluded: SalaryExclusion[];
  /**
   * Recopiées depuis pipeline/config/salary_anchors.yaml, y compris celles qui n'ont servi à aucune calibration. Une ancre sans source, sans méthode ou sans date fait échouer la validation.
   *
   * @minItems 1
   */
  anchors: [SalaryAnchor, ...SalaryAnchor[]];
  /**
   * Texte affiché partout où une estimation salariale apparaît. Stocké dans les données pour qu'il ne puisse pas diverger d'une page à l'autre.
   */
  disclaimer: string;
}
export interface SalaryDistribution {
  league: LeagueId;
  season: Season;
  currency: "EUR";
  /**
   * Seules les distributions adossées à deux moments relevés sur la même période sont publiées. L'énumération n'a qu'une valeur : c'est délibéré, elle interdit structurellement de publier une calibration bâtie sur autre chose.
   */
  basis: "observed";
  /**
   * Paramètre de position de la log-normale, sur l'échelle log.
   */
  mu: number;
  /**
   * Paramètre d'échelle de la log-normale, sur l'échelle log.
   */
  sigma: number;
  /**
   * Plancher salarial réglementaire de la ligue.
   */
  floor: number;
  /**
   * Masse de probabilité que la log-normale NON tronquée plaçait sous le plancher. Au-delà de 5 %, la loi est tronquée à gauche et ré-identifiée numériquement (§4.5). Conservée telle quelle : c'est la justification chiffrée de la troncature.
   */
  pBelowFloor: number;
  /**
   * Vrai si la ré-identification tronquée a été appliquée.
   */
  truncated: boolean;
  /**
   * Ce que cette calibration suppose, en français, affichable.
   */
  note: string;
  /**
   * @minItems 5
   * @maxItems 5
   */
  quintiles: [QuintileBand, QuintileBand, QuintileBand, QuintileBand, QuintileBand];
}
export interface QuintileBand {
  quintile: number;
  band: Band;
}
/**
 * Une ligue pour laquelle aucune estimation salariale n'est produite.
 */
export interface SalaryExclusion {
  league: LeagueId;
  season: Season;
  /**
   * Pourquoi les sources disponibles ne permettent pas de calibrer. Affiché sur le site.
   */
  reason: string;
}
/**
 * Valeur salariale publique servant à calibrer, ou à documenter pourquoi on ne calibre pas. Jamais codée en dur dans un script (§3.1).
 */
export interface SalaryAnchor {
  id: Slug;
  league: LeagueId;
  season: Season;
  /**
   * « rosterCap » est un plafond réglementaire sur la masse salariale des cinq titulaires : il majore une moyenne sans la situer. « range » est une fourchette déclarative.
   */
  statistic: "mean" | "median" | "floor" | "rosterCap" | "range";
  /**
   * Valeur ponctuelle, ou null pour une ancre de type « range ».
   */
  value: number | null;
  /**
   * Borne basse d'une ancre « range », null sinon.
   */
  valueLower: number | null;
  /**
   * Borne haute d'une ancre « range », null sinon.
   */
  valueUpper: number | null;
  /**
   * Marge annoncée par la source, en euros. null quand la source n'en donne pas. Zéro pour une valeur réglementaire, qui n'est pas une estimation.
   */
  uncertainty: number | null;
  currency: "EUR";
  /**
   * Nom lisible de la source.
   */
  source: string;
  /**
   * Comment la source a obtenu ce chiffre. Distinguer une divulgation réglementaire d'une enquête journalistique change ce qu'on peut en conclure, et le lecteur a le droit de le savoir.
   */
  method: string;
  url: string;
  publishedAt: IsoDate;
  retrievedAt: IsoDate;
}
/**
 * Contenu de web/src/data/meta.json : traçabilité de bout en bout. Chaque estimation affichée sur le site remonte au commit de pipeline nommé ici.
 */
export interface MetaFile {
  /**
   * Instant de génération, UTC.
   */
  generatedAt: string;
  /**
   * Hash git complet du dépôt au moment où le pipeline a tourné. Affiché sur le site (§0.2).
   */
  pipelineCommit: string;
  lastDataDate: IsoDate;
  /**
   * Niveau des intervalles, 0.8 par défaut. Affiché partout dans l'UI, jamais implicite (§4.6).
   */
  confidenceLevel: number;
  bootstrapReplicates: number;
  counts: {
    players: number;
    playerGames: number;
    teams: number;
    leagues: number;
    transitions: number;
  };
  /**
   * Taux d'entités non résolues. Le maximum de 2 % est structurel : au-delà, le pipeline échoue plutôt que d'exporter (§3.2).
   */
  unmatchedRate: number;
  /**
   * @minItems 1
   */
  sources: [DataSource, ...DataSource[]];
  /**
   * Vrai si les données sont un jeu de développement synthétique et non le produit du pipeline. Le site affiche alors un bandeau permanent, et « pnpm verify:release » échoue : des données fictives peuvent servir à construire le site, jamais à le publier.
   */
  synthetic: boolean;
  /**
   * Source des performances joueur-game. Oracle's Elixir porte les différentiels de lane à 15 minutes ; les tableaux de score de Leaguepedia ne les portent pas. La source change donc ce que metric_std peut mesurer, et le site doit pouvoir le dire.
   */
  performanceSource: "oracle" | "leaguepedia";
  /**
   * Composants de metric_std réellement calculés. Une estimation bâtie sur cinq composants au lieu de huit ne doit pas se présenter comme les autres.
   *
   * @minItems 1
   */
  metricComponents: [string, ...string[]];
}
export interface DataSource {
  name: string;
  url: string;
  licence: string;
  retrievedAt: IsoDate;
}
