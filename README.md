# GigShield

A blockchain-powered decentralized insurance platform for gig workers, enabling peer-to-peer insurance pools with transparent premiums, automated claims, and community governance—all built on the Stacks blockchain using Clarity smart contracts.

---

## Overview

GigShield addresses the lack of affordable and accessible insurance for gig workers (e.g., rideshare drivers, freelancers, delivery workers) by creating a decentralized, transparent insurance ecosystem. The platform uses tokenized contributions, automated claims processing, and community governance to ensure fairness and efficiency. It consists of four main smart contracts:

1. **Insurance Pool Contract** – Manages contributions to the insurance pool and distributes payouts.
2. **Claims Processing Contract** – Automates claim submissions, validation, and payouts using predefined criteria.
3. **Governance DAO Contract** – Enables gig workers to vote on pool parameters and claim disputes.
4. **Oracle Integration Contract** – Connects to off-chain data for claim verification (e.g., accident reports, work history).

---

## Features

- **Peer-to-Peer Insurance Pool**: Gig workers contribute tokens to a shared pool, which funds payouts for verified claims.
- **Automated Claims Processing**: Smart contracts evaluate claims based on predefined rules, reducing delays and intermediaries.
- **Community Governance**: Token holders vote on pool rules, premium rates, and disputed claims.
- **Transparent Data Integration**: Oracles provide verified off-chain data (e.g., accident reports or gig platform records) for trustless claim validation.
- **Tokenized Incentives**: Contributors earn governance tokens for participation, redeemable for reduced premiums or voting power.

---

## Smart Contracts

### Insurance Pool Contract
- Collects token contributions from gig workers to fund the insurance pool.
- Distributes payouts to approved claims automatically.
- Tracks pool balance and contributor stakes for transparency.

### Claims Processing Contract
- Accepts claim submissions with supporting data (e.g., accident reports).
- Validates claims against predefined criteria (e.g., work-related incidents).
- Automates payouts from the pool or escalates disputes to governance.

### Governance DAO Contract
- Enables token-weighted voting on pool parameters (e.g., premium rates, coverage limits).
- Resolves disputed claims through community consensus.
- Manages quorum and voting periods for fair decision-making.

### Oracle Integration Contract
- Integrates with off-chain data providers (e.g., gig platforms, insurance verifiers).
- Provides secure, verified data for claim validation (e.g., proof of work, incident reports).
- Ensures data integrity with cryptographic signatures.

---

## Installation

1. Install [Clarinet CLI](https://docs.hiro.so/clarinet/getting-started).
2. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/gigshield.git
   ```
3. Run tests:
   ```bash
   clarinet test
   ```
4. Deploy contracts:
   ```bash
   clarinet deploy
   ```

## Usage

Each smart contract is designed to work independently but integrates seamlessly to create a decentralized insurance ecosystem. Below is an example workflow:

1. Gig workers contribute tokens to the **Insurance Pool Contract** to join the pool.
2. A worker submits a claim (e.g., for a work-related injury) via the **Claims Processing Contract**.
3. The **Oracle Integration Contract** verifies claim data (e.g., accident report from a gig platform).
4. If validated, the claim is paid out automatically; if disputed, it’s escalated to the **Governance DAO Contract** for community voting.
5. Token holders vote on pool rules or disputed claims using the **Governance DAO Contract**.

Refer to individual contract documentation for detailed function calls, parameters, and usage examples.

## License

MIT License
