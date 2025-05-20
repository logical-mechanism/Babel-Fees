#!/usr/bin/env bash
set -e

# SET UP VARS HERE
source ../.env

# get params
${cli} conway query protocol-parameters ${network} --out-file ../tmp/protocol.json

#
### Wallets
#

# keeper
keeper_wallet_path="../wallets/keeper-wallet"
keeper_address=$(cat ${keeper_wallet_path}/payment.addr)
keeper_pkh=$(${cli} conway address key-hash --payment-verification-key-file ${keeper_wallet_path}/payment.vkey)

# collat wallet
collat_wallet_path="../wallets/collat-wallet"
collat_address=$(cat ${collat_wallet_path}/payment.addr)
collat_pkh=$(${cli} conway address key-hash --payment-verification-key-file ${collat_wallet_path}/payment.vkey)

# babel fee
babel_fee_script_path="../../contracts/babel_fees_contract.plutus"
babel_fee_script_address=$(${cli} conway address build --payment-script-file ${babel_fee_script_path} ${network})
babel_fee_policy_id=$(cat ../../hashes/babel_fees.hash)

#
### Generate Token Information
#

echo -e "\033[0;36m Gathering User UTxO Information  \033[0m"
${cli} conway query utxo \
    ${network} \
    --address ${keeper_address} \
    --out-file ../tmp/keeper_utxo.json
TXNS=$(jq length ../tmp/keeper_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${keeper_address} \033[0m \n";
   exit;
fi
TXIN=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/keeper_utxo.json)
keeper_utxo=${TXIN::-8}
echo "User UTxO:" ${keeper_utxo}

babel_fee_token_name=$(jq -r '.fields[1].bytes' ../data/fixed-babel-fee-datum.json)
babel_fee_asset="-1 ${babel_fee_policy_id}.${babel_fee_token_name}"

jq --arg variable "${babel_fee_token_name}" '.fields[0].bytes=$variable' ../data/burn-redeemer.json | sponge ../data/burn-redeemer.json

echo -e "\033[0;36m Gathering Babel Fee UTxO Information  \033[0m"
${cli} conway query utxo \
    ${network} \
    --address ${babel_fee_script_address} \
    --out-file ../tmp/babel_fee_utxo.json
TXNS=$(jq length ../tmp/babel_fee_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${babel_fee_script_address} \033[0m \n";
   exit;
fi
TXIN=$(jq -r --arg alltxin "" --arg policy_id "$babel_fee_policy_id" --arg token_name "$babel_fee_token_name" 'to_entries[] | select(.value.value[$policy_id][$token_name] == 1) | .key | . + $alltxin + " --tx-in"' ../tmp/babel_fee_utxo.json)
babel_fee_utxo=${TXIN::-8}
echo "Babel Fee UTxO:" ${babel_fee_utxo}

echo -e "\033[0;36m Gathering Collateral UTxO Information  \033[0m"
${cli} conway query utxo \
    ${network} \
    --address ${collat_address} \
    --out-file ../tmp/collat_utxo.json
TXNS=$(jq length ../tmp/collat_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${collat_address} \033[0m \n";
   exit;
fi
collat_utxo=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)
echo "Collateral UTxO:" ${collat_utxo}

babel_fee_ref_utxo=$(${cli} conway transaction txid --tx-file ../tmp/babel_fees_contract-reference-utxo.signed )

echo -e "\033[0;36m Building Tx \033[0m"
FEE=$(${cli} conway transaction build \
    --out-file ../tmp/tx.draft \
    --change-address ${keeper_address} \
    --tx-in-collateral="${collat_utxo}" \
    --tx-in ${keeper_utxo} \
    --tx-in ${babel_fee_utxo} \
    --spending-tx-in-reference="${babel_fee_ref_utxo}#1" \
    --spending-plutus-script-v3 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/remove-redeemer.json \
    --required-signer-hash ${collat_pkh} \
    --required-signer-hash ${keeper_pkh} \
    --mint="${babel_fee_asset}" \
    --mint-tx-in-reference="${babel_fee_ref_utxo}#1" \
    --mint-plutus-script-v3 \
    --policy-id="${babel_fee_policy_id}" \
    --mint-reference-tx-in-redeemer-file ../data/burn-redeemer.json \
    ${network})

echo -e "\033[0;35m${FEE} \033[0m"
#
# exit
#
echo -e "\033[0;36m Signing \033[0m"
${cli} conway transaction sign \
    --signing-key-file ${keeper_wallet_path}/payment.skey \
    --signing-key-file ${collat_wallet_path}/payment.skey \
    --tx-body-file ../tmp/tx.draft \
    --out-file ../tmp/tx.signed \
    ${network}
#
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} conway transaction submit \
    ${network} \
    --tx-file ../tmp/tx.signed