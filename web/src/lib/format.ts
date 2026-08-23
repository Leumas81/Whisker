import type { Band, Estimate } from "~/generated/types";

/**
 * Mise en forme des nombres.
 *
 * Un seul endroit décide comment un chiffre s'écrit : espace insécable pour les milliers,
 * virgule décimale, et jamais de valeur seule sans son intervalle là où le contrat en impose un.
 */

const NBSP = " ";

export function formatNumber(value: number, decimals = 1): string {
  return value.toLocaleString("fr-FR", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

export function formatInteger(value: number): string {
  return value.toLocaleString("fr-FR", { maximumFractionDigits: 0 });
}

/** Montant en euros, arrondi au millier. Jamais utilisé pour un montant nominatif (§6.6). */
export function formatEuros(value: number): string {
  const rounded = Math.round(value / 1000) * 1000;
  return `${formatInteger(rounded)}${NBSP}€`;
}

export function formatBand(band: Band): string {
  return `${formatEuros(band.lower)} – ${formatEuros(band.upper)}`;
}

/** Estimation ponctuelle et son intervalle, sur une ligne. */
export function formatEstimate(estimate: Estimate, decimals = 1): string {
  return (
    `${formatNumber(estimate.point, decimals)} ` +
    `[${formatNumber(estimate.lower, decimals)}${NBSP}–${NBSP}${formatNumber(estimate.upper, decimals)}]`
  );
}

/** Une proportion en pourcentage, avec son intervalle. */
export function formatShare(estimate: Estimate): string {
  const percent = (value: number) => `${formatNumber(value * 100, 0)}${NBSP}%`;
  return `${percent(estimate.point)} [${percent(estimate.lower)}${NBSP}–${NBSP}${percent(estimate.upper)}]`;
}

/** Largeur de l'intervalle — la donnée qui dit combien on en sait. */
export function intervalWidth(estimate: Estimate): number {
  return estimate.upper - estimate.lower;
}

export function formatConfidence(level: number): string {
  return `IC${NBSP}${formatNumber(level * 100, 0)}${NBSP}%`;
}

/** Surtitre d'un bloc : l'estimand, son niveau de confiance, sa taille d'échantillon (§5.5). */
export function estimandLabel(name: string, level: number, sampleSize?: number): string {
  const parts = [name.toUpperCase(), formatConfidence(level)];
  if (sampleSize !== undefined) parts.push(`n${NBSP}=${NBSP}${formatInteger(sampleSize)}`);
  return parts.join(" · ");
}

export const ROLE_LABELS: Record<string, string> = {
  top: "TOP",
  jng: "JNG",
  mid: "MID",
  adc: "ADC",
  sup: "SUP",
};

export const RELIABILITY_LABELS: Record<string, string> = {
  high: "élevée",
  medium: "moyenne",
  low: "faible",
};

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("fr-FR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}
