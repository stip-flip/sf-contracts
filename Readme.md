# Stip & Flip

Open and decentralized synthetic trading protocol. Trade anything, short and long, on leverage, with no liquidation risk.

This repository contains the smart contracts for the S&F protocol.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Smart contract dependencies

```bash
forge install
```

## Usage

### Config

Replace the appropriate variable in .env.example and rename it to .env

### Deploy

To create a new synthetic, you first need to deploy the `Oracle` contract implementing the IOracle interface.
Once the Oracle contract has a price set, you can deploy the `Synthetic` contract with the address of the newly created Oracle contract.

```bash
forge script ${FILE_URL}:${CONTRACT_NAME}
```

### Test

```bash
forge test
```

### Contract Addresses

The first synthetics available on S&F will come from this Oracle and Synth factory contracts.

| Contract Name | MORDOR                                     | ETHER CLASSIC                              |
| ------------- | ------------------------------------------ | ------------------------------------------ |
| Oracle        | 0x5FbDB2315678afecb367f032d93F642f64180aa3 | 0x5FbDB2315678afecb367f032d93F642f64180aa3 |
| Synth Factory | 0x8f3Cf7ad23Cd3Ca8d1fF675d5f0b4d4aC5b0A1a1 | 0x5FbDB2315678afecb367f032d93F642f64180aa3 |

## License

The primary license for S&F is the Business Source License 1.1 (BUSL-1.1), see LICENSE. However, some files are dual licensed under GPL-2.0-or-later
