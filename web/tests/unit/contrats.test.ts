import { describe, expect, it } from "vitest";
import { createValidator } from "../../../tools/lib/validator.mjs";

/**
 * Les schémas ne sont utiles que si l'on sait ce qu'ils refusent. Ces tests attaquent
 * chaque garde-fou du §1.2 et du §3.4 par un contre-exemple : une donnée qui doit échouer.
 */

const ajv = createValidator();

function validatePlayer(player: unknown): { valid: boolean; messages: string[] } {
  const validate = ajv.getSchema("player.schema.json")!;
  const valid = validate({ players: [player] }) as boolean;
  return { valid, messages: (validate.errors ?? []).map((error) => error.message ?? "") };
}

const referencePlayer = {
  slug: "vladi",
  name: "Vladi",
  role: "mid",
  team: "Fnatic",
  league: "LEC",
  age: 20,
  contractEnd: "2026-11-16",
  games: 84,
  valueIndex: { point: 71.2, lower: 63.8, upper: 78.1 },
  playerShare: { point: 0.64, lower: 0.51, upper: 0.76 },
  lecEquivalent: null,
  salaryQuintile: 4,
  salaryBand: { lower: 120000, upper: 210000 },
  reliability: "medium",
  history: [
    {
      season: 2024,
      league: "LFL",
      team: "Karmine Corp",
      games: 45,
      valueIndex: { point: 66.0, lower: 58.2, upper: 73.4 },
    },
  ],
};

describe("le joueur de référence du brief", () => {
  it("est accepté", () => {
    expect(validatePlayer(referencePlayer).valid).toBe(true);
  });
});

describe("ordre des bornes", () => {
  it("refuse une borne basse au-dessus du point estimé", () => {
    const result = validatePlayer({
      ...referencePlayer,
      valueIndex: { point: 71.2, lower: 80.0, upper: 78.1 },
    });
    expect(result.valid).toBe(false);
    expect(result.messages.join(" ")).toContain("lower");
  });

  it("refuse un point estimé au-dessus de la borne haute", () => {
    const result = validatePlayer({
      ...referencePlayer,
      valueIndex: { point: 90.0, lower: 63.8, upper: 78.1 },
    });
    expect(result.valid).toBe(false);
  });

  it("accepte un intervalle dégénéré, où les trois valeurs coïncident", () => {
    const result = validatePlayer({
      ...referencePlayer,
      valueIndex: { point: 70, lower: 70, upper: 70 },
    });
    expect(result.valid).toBe(true);
  });

  it("refuse une fourchette salariale inversée", () => {
    const result = validatePlayer({
      ...referencePlayer,
      salaryBand: { lower: 210000, upper: 120000 },
    });
    expect(result.valid).toBe(false);
  });
});

describe("aucun chiffre affiché seul", () => {
  it("refuse un indice de valeur sans intervalle", () => {
    const { valueIndex: _drop, ...withoutInterval } = referencePlayer;
    const result = validatePlayer({ ...withoutInterval, valueIndex: 71.2 });
    expect(result.valid).toBe(false);
  });

  it("refuse un indice de valeur amputé de sa borne haute", () => {
    const result = validatePlayer({
      ...referencePlayer,
      valueIndex: { point: 71.2, lower: 63.8 },
    });
    expect(result.valid).toBe(false);
  });

  it("refuse une trajectoire de saison sans intervalle", () => {
    const result = validatePlayer({
      ...referencePlayer,
      history: [{ season: 2024, league: "LFL", team: "Karmine Corp", games: 45, valueIndex: 66.0 }],
    });
    expect(result.valid).toBe(false);
  });
});

describe("salaires", () => {
  it("refuse un montant ponctuel dans la fourchette salariale", () => {
    const result = validatePlayer({
      ...referencePlayer,
      salaryBand: { point: 165000, lower: 120000, upper: 210000 },
    });
    expect(result.valid).toBe(false);
  });

  it("refuse un quintile hors de 1 à 5", () => {
    expect(validatePlayer({ ...referencePlayer, salaryQuintile: 6 }).valid).toBe(false);
    expect(validatePlayer({ ...referencePlayer, salaryQuintile: 0 }).valid).toBe(false);
  });

  it("accepte l'absence d'estimation quand la ligue n'a pas de distribution calibrée", () => {
    // La LFL n'a pas deux moments salariaux relevés sur la même période : ses joueurs
    // sortent du pipeline sans quintile ni fourchette, et c'est un résultat, pas un trou.
    const result = validatePlayer({
      ...referencePlayer,
      league: "LFL",
      salaryQuintile: null,
      salaryBand: null,
    });
    expect(result.valid).toBe(true);
  });
});

describe("contrat des ancres salariales", () => {
  const validateSalary = (payload: unknown) => {
    const validate = ajv.getSchema("salary.schema.json")!;
    return { valid: validate(payload) as boolean, errors: validate.errors };
  };

  const anchor = {
    id: "lec-mediane-2025",
    league: "LEC",
    season: 2025,
    statistic: "median",
    value: 165000,
    valueLower: null,
    valueUpper: null,
    uncertainty: 10000,
    currency: "EUR",
    source: "Sheep Esports — enquête LEC Wooloo",
    method: "Médiane des 50 joueurs actifs, split Winter 2025, à ± 10 000 €.",
    url: "https://www.sheepesports.com/en/all/articles/exclusive-everything-about-lec-salaries-unveiled-or-lec-wooloo/en",
    publishedAt: "2025-01-20",
    retrievedAt: "2026-08-21",
  };

  const file = {
    distributions: [],
    excluded: [
      { league: "LFL", season: 2025, reason: "Aucune médiane relevée sur la même période que le plafond." },
    ],
    anchors: [anchor],
    disclaimer: "Estimation statistique. Aucun salaire réel n'est connu de ce site.",
  };

  it("accepte une ancre complète", () => {
    expect(validateSalary(file).valid).toBe(true);
  });

  it("refuse une ancre sans méthode : on doit pouvoir distinguer une enquête d'un règlement", () => {
    const { method: _drop, ...withoutMethod } = anchor;
    expect(validateSalary({ ...file, anchors: [withoutMethod] }).valid).toBe(false);
  });

  it("refuse une ancre sans date de publication", () => {
    const { publishedAt: _drop, ...withoutDate } = anchor;
    expect(validateSalary({ ...file, anchors: [withoutDate] }).valid).toBe(false);
  });

  it("refuse une URL qui n'est pas en HTTPS", () => {
    expect(
      validateSalary({ ...file, anchors: [{ ...anchor, url: "http://example.invalid/x" }] }).valid,
    ).toBe(false);
  });

  it("refuse une calibration qui ne repose pas sur des moments observés", () => {
    const distribution = {
      league: "LEC",
      season: 2025,
      currency: "EUR",
      basis: "cap",
      mu: 11.78,
      sigma: 0.92,
      floor: 60000,
      pBelowFloor: 0.121,
      truncated: true,
      note: "Calibrée sur un plafond réglementaire.",
      quintiles: [1, 2, 3, 4, 5].map((quintile) => ({
        quintile,
        band: { lower: 60000 + quintile * 1000, upper: 60000 + quintile * 2000 },
      })),
    };
    expect(validateSalary({ ...file, distributions: [distribution] }).valid).toBe(false);
    expect(
      validateSalary({ ...file, distributions: [{ ...distribution, basis: "observed" }] }).valid,
    ).toBe(true);
  });

  it("exige que toute ligue non calibrée soit explicitement écartée", () => {
    const { excluded: _drop, ...withoutExcluded } = file;
    expect(validateSalary(withoutExcluded).valid).toBe(false);
  });
});

describe("seuil de fiabilité", () => {
  it("refuse un joueur sous les dix games, qui ne doit jamais être exporté", () => {
    expect(validatePlayer({ ...referencePlayer, games: 9 }).valid).toBe(false);
  });

  it("accepte un joueur à dix games exactement", () => {
    expect(validatePlayer({ ...referencePlayer, games: 10 }).valid).toBe(true);
  });

  it("refuse une valeur de fiabilité inventée", () => {
    expect(validatePlayer({ ...referencePlayer, reliability: "excellent" }).valid).toBe(false);
  });
});

describe("échelle unité", () => {
  it("refuse une part joueur supérieure à 1", () => {
    const result = validatePlayer({
      ...referencePlayer,
      playerShare: { point: 1.4, lower: 1.2, upper: 1.6 },
    });
    expect(result.valid).toBe(false);
  });

  it("refuse une part joueur négative", () => {
    const result = validatePlayer({
      ...referencePlayer,
      playerShare: { point: -0.1, lower: -0.3, upper: 0.2 },
    });
    expect(result.valid).toBe(false);
  });
});

describe("champs inconnus", () => {
  it("refuse un champ qui n'est pas au contrat", () => {
    const result = validatePlayer({ ...referencePlayer, salaireReel: 180000 });
    expect(result.valid).toBe(false);
  });

  it("refuse une ligue hors périmètre", () => {
    expect(validatePlayer({ ...referencePlayer, league: "LCK" }).valid).toBe(false);
  });

  it("refuse un slug qui ne tiendrait pas dans une URL", () => {
    expect(validatePlayer({ ...referencePlayer, slug: "Vladi KC" }).valid).toBe(false);
  });
});

describe("traçabilité", () => {
  it("exige un hash git complet dans meta.json", () => {
    const validate = ajv.getSchema("meta.schema.json")!;
    const meta = {
      generatedAt: "2026-08-21T04:00:00Z",
      pipelineCommit: "abc123",
      lastDataDate: "2026-08-17",
      confidenceLevel: 0.8,
      bootstrapReplicates: 2000,
      synthetic: false,
      performanceSource: "leaguepedia",
      metricComponents: ["dmgshare", "rendement", "kp", "survie", "vision"],
      counts: { players: 400, playerGames: 15000, teams: 40, leagues: 2, transitions: 43 },
      unmatchedRate: 0.004,
      sources: [
        {
          name: "Oracle's Elixir",
          url: "https://oracleselixir.com/tools/downloads",
          licence: "Usage libre avec attribution",
          retrievedAt: "2026-08-18",
        },
      ],
    };
    expect(validate(meta)).toBe(false);
    expect(validate({ ...meta, pipelineCommit: "a".repeat(40) })).toBe(true);
  });

  it("refuse un taux de non-résolution au-delà de 2 %", () => {
    const validate = ajv.getSchema("meta.schema.json")!;
    const meta = {
      generatedAt: "2026-08-21T04:00:00Z",
      pipelineCommit: "a".repeat(40),
      lastDataDate: "2026-08-17",
      confidenceLevel: 0.8,
      bootstrapReplicates: 2000,
      synthetic: false,
      performanceSource: "leaguepedia",
      metricComponents: ["dmgshare", "rendement", "kp", "survie", "vision"],
      counts: { players: 400, playerGames: 15000, teams: 40, leagues: 2, transitions: 43 },
      unmatchedRate: 0.05,
      sources: [
        {
          name: "Oracle's Elixir",
          url: "https://oracleselixir.com/tools/downloads",
          licence: "Usage libre avec attribution",
          retrievedAt: "2026-08-18",
        },
      ],
    };
    expect(validate(meta)).toBe(false);
  });
});

describe("coefficients d'équivalence", () => {
  it("refuse un coefficient hors de l'intervalle unité", () => {
    const validate = ajv.getSchema("leagues.schema.json")!;
    const base = {
      strengths: [],
      equivalences: [
        {
          from: "LFL",
          to: "LEC",
          coefficient: { point: 1.3, lower: 1.1, upper: 1.5 },
          nTransitions: 43,
          selectionCorrection: "none",
          retentionOneYear: { point: 0.58, lower: 0.44, upper: 0.71 },
        },
      ],
    };
    expect(validate(base)).toBe(false);
  });
});
