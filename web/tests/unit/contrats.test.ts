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
