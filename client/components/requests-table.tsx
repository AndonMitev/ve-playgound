"use client";

import { useEffect, useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
  useBlockNumber,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { QUEUE_ADDRESS, withdrawQueueAbi } from "@/lib/contracts";
import { formatNumber, formatCountdown } from "@/lib/utils";

interface WithdrawRequest {
  id: number;
  user: string;
  amountOfShares: bigint;
  creationTime: number;
  completed: boolean;
  isMatured: boolean;
}

export function RequestsTable() {
  const { address } = useAccount();
  const queryClient = useQueryClient();
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  const [isHovered, setIsHovered] = useState(false);

  useEffect(() => {
    const interval = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(interval);
  }, []);

  const { data: blockNumber } = useBlockNumber({ watch: true });
  const { data: nextRequestId } = useReadContract({ address: QUEUE_ADDRESS, abi: withdrawQueueAbi, functionName: "nextRequestId", query: { refetchInterval: 15_000 } });
  const { data: maturityPeriod } = useReadContract({ address: QUEUE_ADDRESS, abi: withdrawQueueAbi, functionName: "MATURITY_PERIOD" });

  const nextId = nextRequestId ? Number(nextRequestId) : 0;
  const requestIds = nextId > 1 && nextId < 10_000 ? Array.from({ length: nextId - 1 }, (_, i) => i + 1) : [];

  const { data: requestsData, refetch: refetchRequests } = useReadContracts({
    contracts: requestIds.flatMap((id) => [
      { address: QUEUE_ADDRESS, abi: withdrawQueueAbi, functionName: "getRequest" as const, args: [BigInt(id)] },
      { address: QUEUE_ADDRESS, abi: withdrawQueueAbi, functionName: "isMatured" as const, args: [BigInt(id)] },
    ]),
    query: { enabled: requestIds.length > 0, refetchInterval: 15_000 },
  });

  useEffect(() => { if (blockNumber) refetchRequests(); }, [blockNumber, refetchRequests]);

  const userRequests: WithdrawRequest[] = [];
  if (requestsData) {
    for (let i = 0; i < requestIds.length; i++) {
      const reqResult = requestsData[i * 2]?.result as { user: string; amountOfShares: bigint; creationTime: number; completed: boolean } | undefined;
      const maturedResult = requestsData[i * 2 + 1]?.result as boolean | undefined;
      if (reqResult && reqResult.user.toLowerCase() === address?.toLowerCase()) {
        userRequests.push({ id: requestIds[i], user: reqResult.user, amountOfShares: reqResult.amountOfShares, creationTime: Number(reqResult.creationTime), completed: reqResult.completed, isMatured: maturedResult ?? false });
      }
    }
  }

  const { writeContract: cancelWithdraw, data: cancelTxHash, isPending: isCancelling, isError: isCancelError, reset: resetCancel } = useWriteContract();
  const { isSuccess: isCancelConfirmed } = useWaitForTransactionReceipt({ hash: cancelTxHash });

  useEffect(() => { if (isCancelConfirmed) { refetchRequests(); queryClient.invalidateQueries(); resetCancel(); } }, [isCancelConfirmed, refetchRequests, queryClient, resetCancel]);
  useEffect(() => { if (isCancelError) resetCancel(); }, [isCancelError, resetCancel]);

  const handleCancel = (requestId: number) => { cancelWithdraw({ address: QUEUE_ADDRESS, abi: withdrawQueueAbi, functionName: "cancelWithdraw", args: [BigInt(requestId)] }); };

  if (!address) return null;
  const mp = maturityPeriod ? Number(maturityPeriod) : 259200;

  return (
    <div
      className="relative flex flex-col rounded-2xl overflow-hidden transition-all duration-500"
      style={{
        background: "linear-gradient(170deg, #0d0e14 0%, #060810 100%)",
        border: `1px solid rgba(251,191,36,${isHovered ? "0.3" : "0.1"})`,
        boxShadow: isHovered
          ? "0 0 50px -10px rgba(251,191,36,0.12), 0 8px 32px -4px rgba(0,0,0,0.5)"
          : "0 4px 24px -4px rgba(0,0,0,0.4)",
        transform: isHovered ? "translateY(-1px)" : "translateY(0)",
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      {/* Animated top glow bar */}
      <div className="h-[2px] overflow-hidden relative">
        <div style={{
          position: "absolute", top: 0, left: "-50%", width: "200%", height: "100%",
          background: "linear-gradient(90deg, transparent, #fbbf24, #f59e0b, #fbbf24, transparent)",
          animation: "sweep 4s ease-in-out infinite",
        }} />
      </div>

      {/* Corner glow */}
      <div className="absolute top-0 right-0 w-40 h-40 pointer-events-none"
        style={{
          background: "radial-gradient(circle at top right, rgba(251,191,36,0.06), transparent 70%)",
          opacity: isHovered ? 1 : 0.3,
          transition: "opacity 0.5s",
        }}
      />

      <div className="p-6 relative z-10">
        {/* Header */}
        <div className="flex items-center gap-3 mb-5">
          <div className="relative flex h-10 w-10 items-center justify-center rounded-xl"
            style={{
              background: "rgba(251,191,36,0.1)",
              border: "1px solid rgba(251,191,36,0.25)",
              boxShadow: "0 0 20px -3px rgba(251,191,36,0.2)",
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fbbf24" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M16 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8Z" />
              <path d="M15 3v4a2 2 0 0 0 2 2h4" />
            </svg>
            <div className="absolute inset-0 rounded-xl"
              style={{
                border: "1px solid rgba(251,191,36,0.3)",
                animation: "pulse-glow 3s ease-in-out infinite 2s",
              }}
            />
          </div>
          <div>
            <h2 className="text-[16px] font-extrabold" style={{ color: "#f0f0f5" }}>Withdrawal Requests</h2>
            <p className="text-[11px] font-semibold" style={{ color: "#fbbf24" }}>
              Track your pending and completed withdrawals
            </p>
          </div>
        </div>

        {userRequests.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-14 text-center rounded-xl"
            style={{
              background: "#050710",
              border: "1px solid rgba(251,191,36,0.06)",
              boxShadow: "inset 0 2px 10px rgba(0,0,0,0.4)",
            }}
          >
            <div className="relative flex h-16 w-16 items-center justify-center rounded-2xl mb-4"
              style={{ background: "rgba(251,191,36,0.06)", border: "1px solid rgba(251,191,36,0.12)" }}
            >
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.4 }}>
                <path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9Z" />
                <path d="M13 2v7h7" />
              </svg>
            </div>
            <p className="text-[14px] font-semibold" style={{ color: "#9ca3af" }}>No withdrawal requests yet</p>
            <p className="text-[12px] mt-1.5" style={{ color: "#4b5563" }}>Request a withdrawal to see it here</p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl"
            style={{
              background: "#050710",
              border: "1px solid rgba(251,191,36,0.06)",
              boxShadow: "inset 0 2px 10px rgba(0,0,0,0.4)",
            }}
          >
            <table className="w-full" style={{ tableLayout: "fixed" }}>
              <colgroup>
                <col style={{ width: "25%" }} />
                <col style={{ width: "25%" }} />
                <col style={{ width: "25%" }} />
                <col style={{ width: "25%" }} />
              </colgroup>
              <thead>
                <tr style={{ borderBottom: "1px solid rgba(251,191,36,0.08)" }}>
                  <th className="text-left px-5 py-3.5">
                    <span className="text-[10px] font-bold uppercase" style={{ color: "#fbbf24", letterSpacing: "0.12em" }}>ID</span>
                  </th>
                  <th className="text-left px-5 py-3.5">
                    <span className="text-[10px] font-bold uppercase" style={{ color: "#fbbf24", letterSpacing: "0.12em" }}>Shares</span>
                  </th>
                  <th className="text-left px-5 py-3.5">
                    <span className="text-[10px] font-bold uppercase" style={{ color: "#fbbf24", letterSpacing: "0.12em" }}>Status</span>
                  </th>
                  <th className="text-right px-5 py-3.5">
                    <span className="text-[10px] font-bold uppercase" style={{ color: "#fbbf24", letterSpacing: "0.12em" }}>Action</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {userRequests.map((req, idx) => {
                  const maturesAt = req.creationTime + mp;
                  const secondsLeft = maturesAt - now;
                  const isPending = !req.completed && req.amountOfShares > 0n;
                  const isCancelled = !req.completed && req.amountOfShares === 0n;

                  return (
                    <tr key={req.id}
                      className="transition-colors duration-200"
                      style={{
                        borderBottom: idx < userRequests.length - 1 ? "1px solid rgba(255,255,255,0.04)" : "none",
                      }}
                      onMouseEnter={e => { e.currentTarget.style.background = "rgba(251,191,36,0.02)"; }}
                      onMouseLeave={e => { e.currentTarget.style.background = "transparent"; }}
                    >
                      <td className="px-5 py-4">
                        <span className="text-[14px] font-bold font-[family-name:var(--font-mono)]" style={{ color: "#f0f0f5" }}>
                          #{req.id}
                        </span>
                      </td>
                      <td className="px-5 py-4">
                        <span className="text-[14px] font-semibold font-[family-name:var(--font-mono)]" style={{ color: "#d1d5db" }}>
                          {formatNumber(req.amountOfShares)}
                        </span>
                      </td>
                      <td className="px-5 py-4">
                        {req.completed ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full px-3 py-1"
                            style={{ background: "rgba(52,211,153,0.1)", border: "1px solid rgba(52,211,153,0.25)" }}
                          >
                            <div className="h-1.5 w-1.5 rounded-full" style={{ background: "#34d399", boxShadow: "0 0 6px rgba(52,211,153,0.6)" }} />
                            <span className="text-[11px] font-bold" style={{ color: "#34d399" }}>Completed</span>
                          </span>
                        ) : isCancelled ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full px-3 py-1"
                            style={{ background: "rgba(107,114,128,0.08)", border: "1px solid rgba(107,114,128,0.2)" }}
                          >
                            <div className="h-1.5 w-1.5 rounded-full" style={{ background: "#6b7280" }} />
                            <span className="text-[11px] font-bold" style={{ color: "#6b7280" }}>Cancelled</span>
                          </span>
                        ) : req.isMatured ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full px-3 py-1"
                            style={{ background: "rgba(99,102,241,0.1)", border: "1px solid rgba(99,102,241,0.25)" }}
                          >
                            <div className="h-1.5 w-1.5 rounded-full" style={{ background: "#818cf8", boxShadow: "0 0 6px rgba(99,102,241,0.6)" }} />
                            <span className="text-[11px] font-bold" style={{ color: "#818cf8" }}>Ready</span>
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-2 rounded-full px-3 py-1"
                            style={{ background: "rgba(251,191,36,0.08)", border: "1px solid rgba(251,191,36,0.2)" }}
                          >
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#fbbf24" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                              <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
                            </svg>
                            <span className="text-[11px] font-bold font-[family-name:var(--font-mono)]" style={{ color: "#fbbf24" }}>
                              {formatCountdown(secondsLeft)}
                            </span>
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-4 text-right">
                        {isPending && !req.completed ? (
                          <button onClick={() => handleCancel(req.id)} disabled={isCancelling}
                            className="transition-all duration-200 disabled:opacity-30 disabled:cursor-not-allowed"
                            style={{
                              fontSize: "11px", fontWeight: 800,
                              color: "#f87171", background: "rgba(248,113,113,0.08)",
                              border: "1px solid rgba(248,113,113,0.2)",
                              padding: "6px 16px", borderRadius: "8px", cursor: "pointer",
                            }}
                            onMouseEnter={e => { e.currentTarget.style.background = "rgba(248,113,113,0.15)"; e.currentTarget.style.boxShadow = "0 0 15px rgba(248,113,113,0.15)"; }}
                            onMouseLeave={e => { e.currentTarget.style.background = "rgba(248,113,113,0.08)"; e.currentTarget.style.boxShadow = "none"; }}
                          >
                            {isCancelling ? "..." : "Cancel"}
                          </button>
                        ) : (
                          <span className="text-[13px]" style={{ color: "#1a1d2e" }}>—</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
