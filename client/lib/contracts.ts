export const VAULT_ADDRESS = "0x324dcd943a79Ff3497845479980F6bC936B8116E" as const;
export const TELLER_ADDRESS = "0x9a1f42B252cc0a7fEDD06010c3EA35ce24A4E779" as const;
export const QUEUE_ADDRESS = "0x659c35aF4b862A93D9C1D61B4bAa6595f357dE70" as const;
export const ACCOUNTANT_ADDRESS = "0x04D4E50cDC047b7E36460a813075D075AF59683d" as const;
export const USDE_ADDRESS = "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3" as const;

export const erc20Abi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    type: "function",
    name: "name",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    type: "function",
    name: "totalSupply",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const tellerAbi = [
  {
    type: "function",
    name: "deposit",
    stateMutability: "payable",
    inputs: [
      { name: "depositAsset", type: "address" },
      { name: "depositAmount", type: "uint256" },
      { name: "minimumMint", type: "uint256" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
] as const;

export const withdrawQueueAbi = [
  {
    type: "function",
    name: "requestWithdraw",
    stateMutability: "nonpayable",
    inputs: [{ name: "amountOfShares", type: "uint96" }],
    outputs: [{ name: "requestId", type: "uint96" }],
  },
  {
    type: "function",
    name: "cancelWithdraw",
    stateMutability: "nonpayable",
    inputs: [{ name: "requestId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "getRequest",
    stateMutability: "view",
    inputs: [{ name: "requestId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "user", type: "address" },
          { name: "amountOfShares", type: "uint96" },
          { name: "creationTime", type: "uint40" },
          { name: "completed", type: "bool" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "isMatured",
    stateMutability: "view",
    inputs: [{ name: "requestId", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "nextRequestId",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint96" }],
  },
  {
    type: "function",
    name: "MATURITY_PERIOD",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint24" }],
  },
  {
    type: "event",
    name: "WithdrawRequested",
    inputs: [
      { name: "requestId", type: "uint96", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "amountOfShares", type: "uint96", indexed: false },
    ],
  },
  {
    type: "event",
    name: "WithdrawCancelled",
    inputs: [
      { name: "requestId", type: "uint96", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "amountOfShares", type: "uint96", indexed: false },
    ],
  },
  {
    type: "event",
    name: "WithdrawSolved",
    inputs: [
      { name: "requestId", type: "uint96", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "amountOfShares", type: "uint96", indexed: false },
      { name: "assetsOut", type: "uint256", indexed: false },
    ],
  },
] as const;

export const accountantAbi = [
  {
    type: "function",
    name: "getRate",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "rate", type: "uint256" }],
  },
] as const;
