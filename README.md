# Hyperstructure Babel Fees

This contract allows users to pay a fee provider some token in exchange for providing the Lovelace fee for their transaction.

## General Flow

A fee provider will place ADA into the contract and will select some asset to be paid in exchange for providing the fee for a transaction. The rate for the fee may be determined by a C3 oracle or some fixed rate. Payments for their service will auto-accumulate on their fee UTxO.

A fee user will select some fee provider UTxO to use inside of a transaction. The fee user will pay the fee provider in their preferred token for the fee of their transaction.

## Contingency Issues

Many users may attempt to spend the same fee provider UTxO resulting in a contingency issue.