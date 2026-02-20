"use client";

import { useState, useEffect } from "react";
import {
  useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt,
} from "wagmi";
import {
  VAULT_ADDRESS, QUEUE_ADDRESS, erc20Abi, withdrawQueueAbi,
} from "@/lib/contracts";
import { formatNumber, parseAmount } from "@/lib/utils";

export function WithdrawCard() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const [isHovered, setIsHovered] = useState(false);
  const parsedAmount = parseAmount(amount);

  const { data: reads, refetch } = useReadContracts({
    contracts: [
      { address: VAULT_ADDRESS, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
      { address: VAULT_ADDRESS, abi: erc20Abi, functionName: "allowance", args: [address!, QUEUE_ADDRESS] },
    ],
    query: { enabled: !!address, refetchInterval: 15_000 },
  });

  const shareBalance = reads?.[0]?.result as bigint | undefined;
  const allowance = reads?.[1]?.result as bigint | undefined;
  const needsApproval = allowance !== undefined && parsedAmount > 0n && allowance < parsedAmount;

  const { writeContract: approve, data: approveTxHash, isPending: isApproving, isError: isApproveError, reset: resetApprove } = useWriteContract();
  const { writeContract: requestWithdraw, data: withdrawTxHash, isPending: isRequesting, isError: isWithdrawError, reset: resetWithdraw } = useWriteContract();
  const { isLoading: isApproveConfirming, isSuccess: isApproveConfirmed } = useWaitForTransactionReceipt({ hash: approveTxHash });
  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawConfirmed } = useWaitForTransactionReceipt({ hash: withdrawTxHash });

  useEffect(() => { if (isApproveConfirmed) { refetch(); resetApprove(); } }, [isApproveConfirmed, refetch, resetApprove]);
  useEffect(() => { if (isWithdrawConfirmed) { setAmount(""); refetch(); resetWithdraw(); } }, [isWithdrawConfirmed, refetch, resetWithdraw]);
  useEffect(() => { if (isApproveError) resetApprove(); }, [isApproveError, resetApprove]);
  useEffect(() => { if (isWithdrawError) resetWithdraw(); }, [isWithdrawError, resetWithdraw]);

  const handleApprove = () => { approve({ address: VAULT_ADDRESS, abi: erc20Abi, functionName: "approve", args: [QUEUE_ADDRESS, parsedAmount] }); };
  const handleRequest = () => { requestWithdraw({ address: QUEUE_ADDRESS, abi: withdrawQueueAbi, functionName: "requestWithdraw", args: [parsedAmount as unknown as bigint & { __uint96: true }] }); };
  const handleMax = () => { if (shareBalance) setAmount(formatNumber(shareBalance, 18, 18).replace(/,/g, "").replace(/0+$/, "").replace(/\.$/, "")); };

  const busy = isApproving || isApproveConfirming || isRequesting || isWithdrawConfirming;

  return (
    <div
      className="relative flex flex-col rounded-2xl overflow-hidden transition-all duration-500"
      style={{
        background: "linear-gradient(170deg, #0a0d17 0%, #060810 100%)",
        border: `1px solid rgba(99,102,241,${isHovered ? "0.35" : "0.12"})`,
        boxShadow: isHovered
          ? "0 0 50px -10px rgba(99,102,241,0.15), 0 8px 32px -4px rgba(0,0,0,0.5)"
          : "0 4px 24px -4px rgba(0,0,0,0.4)",
        transform: isHovered ? "translateY(-2px)" : "translateY(0)",
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      {/* Animated top glow bar */}
      <div className="h-[2px] overflow-hidden relative">
        <div style={{
          position: "absolute", top: 0, left: "-50%", width: "200%", height: "100%",
          background: "linear-gradient(90deg, transparent, #818cf8, #6366f1, #818cf8, transparent)",
          animation: "sweep 4s ease-in-out infinite",
        }} />
      </div>

      {/* Corner glow */}
      <div className="absolute top-0 right-0 w-32 h-32 pointer-events-none"
        style={{
          background: "radial-gradient(circle at top right, rgba(99,102,241,0.08), transparent 70%)",
          opacity: isHovered ? 1 : 0.4,
          transition: "opacity 0.5s",
        }}
      />

      <div className="flex flex-col flex-1 p-6 relative z-10">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="relative flex h-10 w-10 items-center justify-center rounded-xl"
              style={{
                background: "rgba(99,102,241,0.1)",
                border: "1px solid rgba(99,102,241,0.25)",
                boxShadow: "0 0 20px -3px rgba(99,102,241,0.2)",
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#818cf8" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 19V5" /><path d="m5 12 7-7 7 7" />
              </svg>
              {/* Pulsing ring */}
              <div className="absolute inset-0 rounded-xl"
                style={{
                  border: "1px solid rgba(99,102,241,0.3)",
                  animation: "pulse-glow 3s ease-in-out infinite 1s",
                }}
              />
            </div>
            <div>
              <h2 className="text-[16px] font-extrabold" style={{ color: "#f0f0f5" }}>Withdraw</h2>
              <p className="text-[11px] font-semibold" style={{ color: "#818cf8" }}>
                cUSDe &rarr; USDe
              </p>
            </div>
          </div>
          {/* Token badge */}
          <div className="flex items-center gap-2 rounded-full px-3 py-1.5"
            style={{ background: "rgba(99,102,241,0.06)", border: "1px solid rgba(99,102,241,0.2)", backdropFilter: "blur(8px)" }}
          >
            <div className="h-4 w-4 rounded-full"
              style={{
                background: "linear-gradient(135deg, #818cf8, #6366f1)",
                boxShadow: "0 0 10px rgba(99,102,241,0.5)",
              }}
            />
            <span className="text-[11px] font-bold" style={{ color: "#818cf8" }}>cUSDe</span>
          </div>
        </div>

        {/* Input area */}
        <div className="rounded-xl p-4 mb-4 transition-all duration-300"
          style={{
            background: "#050710",
            border: "1px solid rgba(99,102,241,0.08)",
            boxShadow: "inset 0 2px 10px rgba(0,0,0,0.4)",
          }}
        >
          <div className="flex items-center justify-between mb-3">
            <span className="text-[10px] font-bold uppercase tracking-[0.12em]" style={{ color: "#6b7280" }}>
              You withdraw
            </span>
            <button onClick={handleMax} disabled={!address || !shareBalance}
              className="transition-all duration-200 disabled:opacity-30"
              style={{
                fontSize: "10px", fontWeight: 800, letterSpacing: "0.06em",
                color: "#818cf8", background: "rgba(99,102,241,0.1)",
                border: "1px solid rgba(99,102,241,0.25)",
                padding: "4px 12px", borderRadius: "6px", cursor: "pointer",
              }}
              onMouseEnter={e => { e.currentTarget.style.background = "rgba(99,102,241,0.2)"; e.currentTarget.style.boxShadow = "0 0 12px rgba(99,102,241,0.2)"; }}
              onMouseLeave={e => { e.currentTarget.style.background = "rgba(99,102,241,0.1)"; e.currentTarget.style.boxShadow = "none"; }}
            >MAX</button>
          </div>
          <div className="flex items-center gap-3">
            <input
              type="text" inputMode="decimal" placeholder="0.00" value={amount}
              onChange={(e) => { if (/^[0-9]*\.?[0-9]*$/.test(e.target.value)) setAmount(e.target.value); }}
              disabled={!address}
              className="bg-transparent outline-none disabled:opacity-40"
              style={{
                fontSize: "30px", fontWeight: 800, fontFamily: "var(--font-mono)",
                color: "#f0f0f5", letterSpacing: "-0.02em",
                minWidth: 0, width: "100%", flex: "1 1 0",
              }}
            />
            <div className="text-right" style={{ flexShrink: 0 }}>
              <p className="text-[10px] font-semibold" style={{ color: "#6b7280" }}>Balance</p>
              <p className="text-[14px] font-bold font-[family-name:var(--font-mono)]" style={{ color: "#818cf8" }}>
                {shareBalance !== undefined ? formatNumber(shareBalance) : "—"}
              </p>
            </div>
          </div>
        </div>

        {/* Maturity info */}
        <div className="flex items-center gap-2.5 rounded-xl p-3 mb-4"
          style={{
            background: "rgba(99,102,241,0.04)",
            border: "1px solid rgba(99,102,241,0.12)",
          }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#818cf8" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
          </svg>
          <span className="text-[12px] font-medium" style={{ color: "#9ca3af" }}>
            3-day maturity period before withdrawal
          </span>
        </div>

        {/* Button */}
        <div className="mt-auto">
          {!address ? (
            <div className="text-center py-3.5 rounded-xl"
              style={{ background: "#0a0c12", border: "1px solid #1a1d2e" }}
            >
              <span className="text-[12px] font-semibold" style={{ color: "#6b7280" }}>
                Connect wallet to withdraw
              </span>
            </div>
          ) : needsApproval ? (
            <button onClick={handleApprove} disabled={busy || parsedAmount === 0n}
              className="relative w-full overflow-hidden rounded-xl py-4 font-bold text-[14px] transition-all duration-300 disabled:opacity-30 disabled:cursor-not-allowed"
              style={{
                background: "linear-gradient(135deg, #fbbf24, #f59e0b)",
                color: "#000", cursor: "pointer",
                boxShadow: busy ? "none" : "0 0 35px -4px rgba(251,191,36,0.4), 0 4px 16px -2px rgba(251,191,36,0.25)",
              }}
              onMouseEnter={e => { if (!busy) e.currentTarget.style.boxShadow = "0 0 50px -4px rgba(251,191,36,0.5), 0 6px 20px -2px rgba(251,191,36,0.3)"; }}
              onMouseLeave={e => { if (!busy) e.currentTarget.style.boxShadow = "0 0 35px -4px rgba(251,191,36,0.4), 0 4px 16px -2px rgba(251,191,36,0.25)"; }}
            >
              <div className="absolute inset-0 pointer-events-none" style={{
                background: "linear-gradient(90deg, transparent 0%, rgba(255,255,255,0.3) 50%, transparent 100%)",
                animation: busy ? "none" : "sweep 2.5s ease-in-out infinite",
              }} />
              <span className="relative z-10">
                {isApproving || isApproveConfirming ? "Approving..." : "Approve Shares"}
              </span>
            </button>
          ) : (
            <button onClick={handleRequest}
              disabled={busy || parsedAmount === 0n || (shareBalance !== undefined && parsedAmount > shareBalance)}
              className="relative w-full overflow-hidden rounded-xl py-4 font-bold text-[14px] transition-all duration-300 disabled:opacity-30 disabled:cursor-not-allowed"
              style={{
                background: "linear-gradient(135deg, #818cf8, #6366f1)",
                color: "#fff", cursor: "pointer",
                boxShadow: (busy || parsedAmount === 0n) ? "none" : "0 0 35px -4px rgba(99,102,241,0.4), 0 4px 16px -2px rgba(99,102,241,0.25)",
              }}
              onMouseEnter={e => { if (!busy && parsedAmount > 0n) e.currentTarget.style.boxShadow = "0 0 50px -4px rgba(99,102,241,0.5), 0 6px 20px -2px rgba(99,102,241,0.3)"; }}
              onMouseLeave={e => { if (!busy && parsedAmount > 0n) e.currentTarget.style.boxShadow = "0 0 35px -4px rgba(99,102,241,0.4), 0 4px 16px -2px rgba(99,102,241,0.25)"; }}
            >
              <div className="absolute inset-0 pointer-events-none" style={{
                background: "linear-gradient(90deg, transparent 0%, rgba(255,255,255,0.18) 50%, transparent 100%)",
                animation: (busy || parsedAmount === 0n) ? "none" : "sweep 2.5s ease-in-out infinite",
              }} />
              <span className="relative z-10">
                {isRequesting || isWithdrawConfirming ? "Requesting..." : "Request Withdrawal"}
              </span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
