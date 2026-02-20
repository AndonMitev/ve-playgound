"use client";

import { useAccount, useReadContracts } from "wagmi";
import {
  VAULT_ADDRESS, USDE_ADDRESS, ACCOUNTANT_ADDRESS,
  erc20Abi, accountantAbi,
} from "@/lib/contracts";
import { formatNumber } from "@/lib/utils";

const statConfig = [
  { label: "TVL", color: "#34d399", bgFrom: "rgba(52,211,153,0.08)", bgTo: "rgba(52,211,153,0.02)" },
  { label: "Rate", color: "#818cf8", bgFrom: "rgba(99,102,241,0.08)", bgTo: "rgba(99,102,241,0.02)" },
  { label: "Shares", color: "#fbbf24", bgFrom: "rgba(251,191,36,0.06)", bgTo: "rgba(251,191,36,0.01)", suffix: "cUSDe" },
  { label: "Balance", color: "#f472b6", bgFrom: "rgba(244,114,182,0.06)", bgTo: "rgba(244,114,182,0.01)", suffix: "USDe" },
];

export function VaultStats() {
  const { address } = useAccount();

  // Public reads — always fetch (no wallet needed)
  const { data: publicData, isLoading: isPublicLoading } = useReadContracts({
    contracts: [
      { address: USDE_ADDRESS, abi: erc20Abi, functionName: "balanceOf", args: [VAULT_ADDRESS] },
      { address: ACCOUNTANT_ADDRESS, abi: accountantAbi, functionName: "getRate" },
    ],
    query: { refetchInterval: 15_000 },
  });

  // User-specific reads — only when connected
  const { data: userData, isLoading: isUserLoading } = useReadContracts({
    contracts: [
      { address: VAULT_ADDRESS, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
      { address: USDE_ADDRESS, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
    ],
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  const tvl = publicData?.[0]?.result as bigint | undefined;
  const rate = publicData?.[1]?.result as bigint | undefined;
  const shares = userData?.[0]?.result as bigint | undefined;
  const usdeBalance = userData?.[1]?.result as bigint | undefined;
  const isLoading = isPublicLoading || isUserLoading;

  const values = [
    tvl !== undefined ? `$${formatNumber(tvl)}` : "—",
    rate !== undefined ? formatNumber(rate, 18, 6) : "—",
    shares !== undefined ? formatNumber(shares) : "—",
    usdeBalance !== undefined ? formatNumber(usdeBalance) : "—",
  ];

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
      {statConfig.map((s, i) => (
        <div key={s.label}
          className="group relative rounded-xl px-5 py-4 overflow-hidden transition-all duration-300"
          style={{
            background: `linear-gradient(135deg, ${s.bgFrom}, ${s.bgTo})`,
            border: `1px solid ${s.color}25`,
            cursor: "default",
          }}
          onMouseEnter={e => {
            e.currentTarget.style.border = `1px solid ${s.color}50`;
            e.currentTarget.style.boxShadow = `0 0 30px -5px ${s.color}30, 0 0 60px -10px ${s.color}15`;
            e.currentTarget.style.transform = "translateY(-2px)";
          }}
          onMouseLeave={e => {
            e.currentTarget.style.border = `1px solid ${s.color}25`;
            e.currentTarget.style.boxShadow = "none";
            e.currentTarget.style.transform = "translateY(0)";
          }}
        >
          {/* Animated top line */}
          <div className="absolute top-0 left-0 right-0 h-[2px] overflow-hidden">
            <div style={{
              position: "absolute", top: 0, left: "-100%", width: "200%", height: "100%",
              background: `linear-gradient(90deg, transparent, ${s.color}, transparent)`,
              animation: "sweep 3s ease-in-out infinite",
            }} />
          </div>

          <p className="text-[10px] font-bold uppercase tracking-[0.15em] mb-2"
            style={{ color: s.color }}
          >
            {s.label}
          </p>
          {isLoading && address ? (
            <div className="h-8 w-20 rounded-md"
              style={{
                background: `linear-gradient(90deg, ${s.bgFrom} 25%, ${s.color}15 50%, ${s.bgFrom} 75%)`,
                backgroundSize: "200% 100%",
                animation: "shimmer 2s infinite",
              }}
            />
          ) : (
            <div className="flex items-baseline gap-1.5">
              <span className="text-[24px] font-extrabold tracking-tight font-[family-name:var(--font-mono)]"
                style={{ color: "#f0f0f5", animation: "count-up 0.4s ease-out both" }}
              >
                {values[i]}
              </span>
              {s.suffix && values[i] !== "—" && (
                <span className="text-[10px] font-bold" style={{ color: `${s.color}90` }}>
                  {s.suffix}
                </span>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
