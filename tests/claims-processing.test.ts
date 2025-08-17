import { describe, it, expect, beforeEach } from "vitest";

interface Claim {
  claimant: string;
  amount: bigint;
  evidenceHash: Uint8Array; // Simplified buff
  description: Uint8Array;
  submitBlock: bigint;
  state: bigint;
  verifier: string | null;
}

interface HistoryEntry {
  action: string;
  block: bigint;
  actor: string;
}

const mockContract = {
  admin: "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM",
  paused: false,
  poolContract: "SP000000000000000000002Q6VF78",
  oracleContract: "SP000000000000000000002Q6VF78",
  daoContract: "SP000000000000000000002Q6VF78",
  claimCounter: 0n,
  multiAdmins: ["ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"],
  claims: new Map<bigint, Claim>(),
  claimHistory: new Map<bigint, HistoryEntry[]>(),
  CLAIM_STATE_PENDING: 0n,
  CLAIM_STATE_VERIFIED: 1n,
  CLAIM_STATE_PAID: 2n,
  CLAIM_STATE_DISPUTED: 3n,
  CLAIM_STATE_REJECTED: 4n,
  CLAIM_TIMEOUT_BLOCKS: 144n,
  currentBlock: 100n, // Mock block height

  isAuthorized(caller: string): boolean {
    return caller === this.admin || this.multiAdmins.includes(caller);
  },

  setPaused(caller: string, pause: boolean) {
    if (!this.isAuthorized(caller)) return { error: 200 };
    this.paused = pause;
    return { value: pause };
  },

  setPoolContract(caller: string, newPool: string) {
    if (!this.isAuthorized(caller)) return { error: 200 };
    if (newPool === "SP000000000000000000002Q6VF78") return { error: 210 };
    this.poolContract = newPool;
    return { value: true };
  },

  addMultiAdmin(caller: string, newAdmin: string) {
    if (caller !== this.admin) return { error: 200 };
    if (this.multiAdmins.includes(newAdmin)) return { error: 200 };
    if (this.multiAdmins.length >= 10) return { error: 200 };
    this.multiAdmins.push(newAdmin);
    return { value: true };
  },

  removeMultiAdmin(caller: string, target: string) {
    if (caller !== this.admin) return { error: 200 };
    this.multiAdmins = this.multiAdmins.filter((p) => p !== target);
    return { value: true };
  },

  submitClaim(caller: string, amount: bigint, evidenceHash: Uint8Array, description: Uint8Array) {
    if (this.paused) return { error: 205 };
    if (amount <= 0n) return { error: 206 };
    if (evidenceHash.length === 0) return { error: 208 };
    if (description.length < 10 || description.length > 256) return { error: 211 };
    const claimId = ++this.claimCounter;
    this.claims.set(claimId, {
      claimant: caller,
      amount,
      evidenceHash,
      description,
      submitBlock: this.currentBlock,
      state: this.CLAIM_STATE_PENDING,
      verifier: null,
    });
    this.claimHistory.set(claimId, [{ action: "submitted", block: this.currentBlock, actor: caller }]);
    return { value: claimId };
  },

  verifyClaim(caller: string, claimId: bigint, evidenceData: Uint8Array) {
    if (this.paused) return { error: 205 };
    if (claimId <= 0n) return { error: 201 };
    const claim = this.claims.get(claimId);
    if (!claim) return { error: 201 };
    if (claim.state !== this.CLAIM_STATE_PENDING) return { error: 209 };
    // Mock oracle verification success
    claim.state = this.CLAIM_STATE_VERIFIED;
    claim.verifier = caller;
    this.claims.set(claimId, claim);
    const history = this.claimHistory.get(claimId) || [];
    history.push({ action: "verified", block: this.currentBlock, actor: caller });
    this.claimHistory.set(claimId, history);
    return { value: true };
  },

  processPayout(caller: string, claimId: bigint) {
    if (this.paused) return { error: 205 };
    if (claimId <= 0n) return { error: 201 };
    const claim = this.claims.get(claimId);
    if (!claim) return { error: 201 };
    if (claim.state !== this.CLAIM_STATE_VERIFIED) return { error: 209 };
    // Mock pool balance check and payout
    claim.state = this.CLAIM_STATE_PAID;
    this.claims.set(claimId, claim);
    const history = this.claimHistory.get(claimId) || [];
    history.push({ action: "paid", block: this.currentBlock, actor: caller });
    this.claimHistory.set(claimId, history);
    return { value: true };
  },

  disputeClaim(caller: string, claimId: bigint, reason: Uint8Array) {
    if (this.paused) return { error: 205 };
    if (claimId <= 0n) return { error: 201 };
    const claim = this.claims.get(claimId);
    if (!claim) return { error: 201 };
    if (claim.state !== this.CLAIM_STATE_PENDING && claim.state !== this.CLAIM_STATE_VERIFIED) return { error: 202 };
    // Mock DAO escalation
    claim.state = this.CLAIM_STATE_DISPUTED;
    this.claims.set(claimId, claim);
    const history = this.claimHistory.get(claimId) || [];
    history.push({ action: "disputed", block: this.currentBlock, actor: caller });
    this.claimHistory.set(claimId, history);
    return { value: 1n }; // Mock DAO proposal ID
  },

  rejectClaim(caller: string, claimId: bigint) {
    if (!this.isAuthorized(caller)) return { error: 200 };
    if (claimId <= 0n) return { error: 201 };
    const claim = this.claims.get(claimId);
    if (!claim) return { error: 201 };
    if (claim.state !== this.CLAIM_STATE_DISPUTED && this.currentBlock - claim.submitBlock <= this.CLAIM_TIMEOUT_BLOCKS) return { error: 209 };
    claim.state = this.CLAIM_STATE_REJECTED;
    this.claims.set(claimId, claim);
    const history = this.claimHistory.get(claimId) || [];
    history.push({ action: "rejected", block: this.currentBlock, actor: caller });
    this.claimHistory.set(claimId, history);
    return { value: true };
  },
};

describe("GigShield Claims Processing Contract", () => {
  beforeEach(() => {
    mockContract.admin = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
    mockContract.paused = false;
    mockContract.claimCounter = 0n;
    mockContract.multiAdmins = ["ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM"];
    mockContract.claims = new Map();
    mockContract.claimHistory = new Map();
    mockContract.currentBlock = 100n;
  });

  it("should allow authorized user to set pool contract", () => {
    const result = mockContract.setPoolContract(mockContract.admin, "ST2NEWPOOL");
    expect(result).toEqual({ value: true });
    expect(mockContract.poolContract).toBe("ST2NEWPOOL");
  });

  it("should prevent unauthorized set pool contract", () => {
    const result = mockContract.setPoolContract("STUNAUTHORIZED", "ST2NEWPOOL");
    expect(result).toEqual({ error: 200 });
  });

  it("should submit a claim successfully", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    const result = mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    expect(result).toEqual({ value: 1n });
    const claim = mockContract.claims.get(1n);
    expect(claim?.amount).toBe(100n);
    expect(claim?.state).toBe(0n);
  });

  it("should prevent submit claim with zero amount", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    const result = mockContract.submitClaim("STCLAIMANT", 0n, evidence, desc);
    expect(result).toEqual({ error: 206 });
  });

  it("should prevent submit claim with invalid description length", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(5); // Too short
    const result = mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    expect(result).toEqual({ error: 211 });
  });

  it("should verify a claim", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    const verifyEvidence = new Uint8Array(256);
    const result = mockContract.verifyClaim("STORACLE", 1n, verifyEvidence);
    expect(result).toEqual({ value: true });
    const claim = mockContract.claims.get(1n);
    expect(claim?.state).toBe(1n);
  });

  it("should process payout for verified claim", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    const verifyEvidence = new Uint8Array(256);
    mockContract.verifyClaim("STORACLE", 1n, verifyEvidence);
    const result = mockContract.processPayout("STADMIN", 1n);
    expect(result).toEqual({ value: true });
    const claim = mockContract.claims.get(1n);
    expect(claim?.state).toBe(2n);
  });

  it("should dispute a claim", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    const reason = new Uint8Array(512);
    const result = mockContract.disputeClaim("STDISPUTER", 1n, reason);
    expect(result).toEqual({ value: 1n });
    const claim = mockContract.claims.get(1n);
    expect(claim?.state).toBe(3n);
  });

  it("should reject a disputed claim", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    const reason = new Uint8Array(512);
    mockContract.disputeClaim("STDISPUTER", 1n, reason);
    const result = mockContract.rejectClaim(mockContract.admin, 1n);
    expect(result).toEqual({ value: true });
    const claim = mockContract.claims.get(1n);
    expect(claim?.state).toBe(4n);
  });

  it("should reject a timed-out pending claim", () => {
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    mockContract.currentBlock += 145n; // Past timeout
    const result = mockContract.rejectClaim(mockContract.admin, 1n);
    expect(result).toEqual({ value: true });
    const claim = mockContract.claims.get(1n);
    expect(claim?.state).toBe(4n);
  });

  it("should not allow actions when paused", () => {
    mockContract.setPaused(mockContract.admin, true);
    const evidence = new Uint8Array(32);
    const desc = new Uint8Array(10);
    const result = mockContract.submitClaim("STCLAIMANT", 100n, evidence, desc);
    expect(result).toEqual({ error: 205 });
  });
});