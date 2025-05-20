# Hyperstructure Babel Fees

This contract allows users to pay a fee provider some token in exchange for providing the Lovelace fee for their transaction.

## General Flow

A fee provider will place ADA into the contract and will select some asset to be paid in exchange for providing the fee for a transaction. The payment rate for the fee may be determined by a C3 oracle or some fixed rate that the fee provider selects. Payments for their service will auto-accumulate on their fee UTxO.

A fee user will select some fee provider UTxO to use inside of a transaction. The fee user will pay the fee provider in their preferred token for the fee of their transaction.

## Potential Issues

- Many users may attempt to spend the same fee provider UTxO resulting in a contingency issue.
- Tx fees increase when using this contract as it requires referencing the script CBOR which dominates the contract cost.
- Price fluctuation may cause the C3 oracles to update resulting in the inability to reference a live oracle UTxO for a block.
- Price oracles may not exist for every token.