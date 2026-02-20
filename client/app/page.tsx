"use client";

import { ConnectButton } from "@/components/connect-button";
import { VaultStats } from "@/components/vault-stats";
import { DepositCard } from "@/components/deposit-card";
import { WithdrawCard } from "@/components/withdraw-card";
import { RequestsTable } from "@/components/requests-table";

export default function Home() {
  return (
    <div className="relative min-h-screen overflow-hidden"
      style={{ background: "#050507" }}
    >
      {/* ── Animated background ── */}
      <div className="pointer-events-none fixed inset-0 z-0">
        {/* Large animated gradient blobs */}
        <div className="absolute rounded-full"
          style={{
            top: "-20%", left: "-10%",
            width: "700px", height: "700px",
            background: "radial-gradient(circle, rgba(52,211,153,0.18) 0%, rgba(52,211,153,0.03) 50%, transparent 70%)",
            filter: "blur(40px)",
            animation: "float 22s ease-in-out infinite",
          }}
        />
        <div className="absolute rounded-full"
          style={{
            bottom: "-15%", right: "-8%",
            width: "600px", height: "600px",
            background: "radial-gradient(circle, rgba(99,102,241,0.18) 0%, rgba(99,102,241,0.03) 50%, transparent 70%)",
            filter: "blur(40px)",
            animation: "float 26s ease-in-out infinite reverse",
          }}
        />
        <div className="absolute rounded-full"
          style={{
            top: "40%", left: "50%",
            width: "400px", height: "400px",
            background: "radial-gradient(circle, rgba(251,191,36,0.1) 0%, transparent 60%)",
            filter: "blur(50px)",
            animation: "float 18s ease-in-out infinite 4s",
          }}
        />

        {/* Subtle grid */}
        <div className="absolute inset-0"
          style={{
            backgroundImage: "linear-gradient(rgba(255,255,255,0.015) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.015) 1px, transparent 1px)",
            backgroundSize: "80px 80px",
          }}
        />

        {/* Floating particles */}
        {[...Array(6)].map((_, i) => (
          <div key={i} className="absolute rounded-full"
            style={{
              width: `${2 + i}px`,
              height: `${2 + i}px`,
              left: `${15 + i * 15}%`,
              bottom: "-5%",
              background: i % 3 === 0 ? "#34d399" : i % 3 === 1 ? "#818cf8" : "#fbbf24",
              opacity: 0.6,
              animation: `particle-float ${12 + i * 3}s linear infinite ${i * 2}s`,
            }}
          />
        ))}
      </div>

      {/* ── Content ── */}
      <main className="relative z-10 mx-auto max-w-[980px] px-5 sm:px-8 py-8 sm:py-12">

        {/* ── Header ── */}
        <header className="flex items-center justify-between mb-10"
          style={{ animation: "fadeIn 0.6s ease-out both" }}
        >
          <div className="flex items-center gap-4">
            {/* Logo with orbiting dot */}
            <div className="relative flex h-12 w-12 items-center justify-center rounded-2xl"
              style={{
                background: "linear-gradient(135deg, rgba(52,211,153,0.15), rgba(52,211,153,0.05))",
                border: "1px solid rgba(52,211,153,0.3)",
                boxShadow: "0 0 30px -5px rgba(52,211,153,0.25), inset 0 0 15px rgba(52,211,153,0.05)",
              }}
            >
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" stroke="#34d399">
                <path d="M12 2L2 7l10 5 10-5-10-5z" />
                <path d="M2 17l10 5 10-5" />
                <path d="M2 12l10 5 10-5" />
              </svg>
              {/* Orbiting dot */}
              <div className="absolute" style={{ top: "50%", left: "50%", marginTop: "-3px", marginLeft: "-3px" }}>
                <div className="h-1.5 w-1.5 rounded-full"
                  style={{
                    background: "#34d399",
                    boxShadow: "0 0 8px 2px rgba(52,211,153,0.6)",
                    animation: "orbit 4s linear infinite",
                  }}
                />
              </div>
            </div>
            <div>
              <h1 className="text-xl font-extrabold tracking-tight" style={{ color: "#f0f0f5" }}>
                USDe Vault
              </h1>
              <p className="text-[11px] font-semibold tracking-[0.2em] uppercase"
                style={{
                  background: "linear-gradient(90deg, #34d399, #818cf8, #fbbf24)",
                  backgroundSize: "200% auto",
                  WebkitBackgroundClip: "text",
                  WebkitTextFillColor: "transparent",
                  animation: "gradient-shift 4s ease infinite",
                }}
              >
                Deposit &middot; Earn &middot; Withdraw
              </p>
            </div>
          </div>
          <ConnectButton />
        </header>

        {/* ── Stats ── */}
        <div style={{ animation: "fadeIn 0.6s ease-out 0.1s both" }}>
          <VaultStats />
        </div>

        {/* ── Action Cards ── */}
        <div className="mt-6 grid gap-5 lg:grid-cols-2"
          style={{ animation: "fadeIn 0.6s ease-out 0.2s both" }}
        >
          <DepositCard />
          <WithdrawCard />
        </div>

        {/* ── Requests ── */}
        <div className="mt-6" style={{ animation: "fadeIn 0.6s ease-out 0.3s both" }}>
          <RequestsTable />
        </div>

        {/* ── Footer ── */}
        <footer className="mt-16 mb-6 text-center" style={{ animation: "fadeIn 0.6s ease-out 0.4s both" }}>
          <div className="h-px mx-auto max-w-xs mb-5"
            style={{ background: "linear-gradient(90deg, transparent, rgba(52,211,153,0.3), rgba(99,102,241,0.3), transparent)" }}
          />
          <p className="text-[11px] tracking-wide" style={{ color: "#4b5563" }}>
            Built on{" "}
            <span style={{ color: "#34d399" }}>Veda BoringVault</span>
            {" "}&middot;{" "}
            Powered by{" "}
            <span style={{ color: "#818cf8" }}>Ethena USDe</span>
          </p>
        </footer>
      </main>
    </div>
  );
}
