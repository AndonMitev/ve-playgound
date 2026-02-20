import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatNumber(value: bigint, decimals: number = 18, displayDecimals: number = 2): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = value / divisor;
  const remainder = value % divisor;
  const fractionStr = remainder.toString().padStart(decimals, "0").slice(0, displayDecimals);
  const wholeStr = whole.toLocaleString("en-US");
  return `${wholeStr}.${fractionStr}`;
}

export function parseAmount(value: string, decimals: number = 18): bigint {
  if (!value || value === ".") return 0n;
  const [whole = "0", fraction = ""] = value.split(".");
  const paddedFraction = fraction.padEnd(decimals, "0").slice(0, decimals);
  return BigInt(whole) * 10n ** BigInt(decimals) + BigInt(paddedFraction);
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatCountdown(seconds: number): string {
  if (seconds <= 0) return "Ready";
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}
