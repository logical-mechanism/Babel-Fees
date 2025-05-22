#!/usr/bin/env bash
set -e

# SET UP VARS HERE
source ../.env
source ../evaluateTx.sh

# get params
${cli} conway query protocol-parameters ${network} --out-file ../tmp/protocol.json

#
### Wallets
#

# user 1
user_wallet_path="../wallets/user-1-wallet"
user_address=$(cat ${user_wallet_path}/payment.addr)
user_pkh=$(${cli} conway address key-hash --payment-verification-key-file ${user_wallet_path}/payment.vkey)

# who gets some ada
# receiver_address="addr_test1qqa9e0qfjgge2r39lxrh4dat6c7s2m23t0tysga9m6pacfjnm243cyjk69v32rkjvwlvpplx5cgfk3jmq9gwncamgf5sg8turc"
receiver_address="addr_test1qrwejm9pza929cedhwkcsprtgs8l2carehs8z6jkse2qp344c43tmm0md55r4ufmxknr24kq6jkvt6spq60edeuhtf4sn2scds"

# collat wallet
collat_wallet_path="../wallets/collat-wallet"
collat_address=$(cat ${collat_wallet_path}/payment.addr)
collat_pkh=$(${cli} conway address key-hash --payment-verification-key-file ${collat_wallet_path}/payment.vkey)

# babel fees
babel_fee_script_path="../../contracts/babel_fees_contract.plutus"
babel_fee_script_address=$(${cli} conway address build --payment-script-file ${babel_fee_script_path} ${network})
babel_fee_policy_id=$(cat ../../hashes/babel_fees.hash)

# payment info
payment_policy_id=$(jq -r '.fields[3].fields[0].bytes' ../data/fixed-babel-fee-datum.json)
payment_token_name=$(jq -r '.fields[3].fields[1].bytes' ../data/fixed-babel-fee-datum.json)

receiver_amt=7654321
receiver_output="${receiver_address} + ${receiver_amt}"
echo Receiver Output: ${receiver_output}

echo -e "\033[0;36m Gathering User UTxO Information  \033[0m"
${cli} conway query utxo \
    ${network} \
    --address ${user_address} \
    --out-file ../tmp/user_utxo.json
TXNS=$(jq length ../tmp/user_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${user_address} \033[0m \n";
   exit;
fi
TXIN=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/user_utxo.json)
user_utxo=${TXIN::-8}
echo "User UTxO:" ${user_utxo}

current_user_lovelace=$(jq -r 'to_entries[0].value.value.lovelace' ../tmp/user_utxo.json)
current_user_payment=$(jq -r --arg pid "${payment_policy_id}" --arg tkn "${payment_token_name}" 'to_entries[0].value.value[$pid][$tkn]' ../tmp/user_utxo.json)

echo -e "\033[0;36m Gathering Babel Fee UTxO Information  \033[0m"
${cli} conway query utxo \
    ${network} \
    --address ${babel_fee_script_address} \
    --out-file ../tmp/fee_utxo.json
TXNS=$(jq length ../tmp/fee_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${fee_script_address} \033[0m \n";
   exit;
fi
fee_utxo=$(jq -r 'keys[0]' ../tmp/fee_utxo.json)
echo "Babel Fee UTxO:" ${fee_utxo}
current_fee_lovelace=$(jq -r 'to_entries[0].value.value.lovelace' ../tmp/fee_utxo.json)
current_fee_payment=$(jq -r --arg pid "${payment_policy_id}" --arg tkn "${payment_token_name}" 'to_entries[0].value.value[$pid][$tkn] // 0' ../tmp/fee_utxo.json)

tmp_fee=100000

payment_rate=$(jq -r '.fields[2].fields[0].int' ../data/fixed-babel-fee-datum.json)
payment_amt=$((1000000 * ${tmp_fee} / ${payment_rate}))
fee_payment_asset="$((${current_fee_payment} + ${payment_amt})) ${payment_policy_id}.${payment_token_name}"

babel_fee_token_name=$(jq -r '.fields[1].bytes' ../data/fixed-babel-fee-datum.json)
babel_fee_asset="1 ${babel_fee_policy_id}.${babel_fee_token_name}"

fee_script_output="${babel_fee_script_address} + $((${current_fee_lovelace} - ${tmp_fee})) + ${babel_fee_asset} + ${fee_payment_asset}"
echo Babel Fee Output: ${fee_script_output}

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

if [ $((${current_user_payment} - ${payment_amt})) -eq 0 ]; then
    user_output="${user_address} + $((${current_user_lovelace} - ${receiver_amt}))"
else
    user_payment_asset="$((${current_user_payment} - ${payment_amt})) ${payment_policy_id}.${payment_token_name}"
    user_output="${user_address} + $((${current_user_lovelace} - ${receiver_amt})) + ${user_payment_asset}"
fi
echo User Output: ${user_output}

babel_fee_ref_utxo=$(${cli} conway transaction txid --tx-file ../tmp/babel_fees_contract-reference-utxo.signed )

execution_units="(0, 0)"

echo -e "\033[0;36m Building Tx \033[0m"
${cli} conway transaction build-raw \
    --out-file ../tmp/tx.draft \
    --tx-in-collateral="${collat_utxo}" \
    --tx-in ${user_utxo} \
    --tx-in ${fee_utxo} \
    --spending-tx-in-reference="${babel_fee_ref_utxo}#1" \
    --spending-plutus-script-v3 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/use-redeemer.json \
    --spending-reference-tx-in-execution-units="${execution_units}" \
    --tx-out="${receiver_output}" \
    --tx-out="${user_output}" \
    --tx-out="${fee_script_output}" \
    --tx-out-inline-datum-file ../data/fixed-babel-fee-datum.json \
    --required-signer-hash ${collat_pkh} \
    --required-signer-hash ${user_pkh} \
    --protocol-params-file ../tmp/protocol.json \
    --fee ${tmp_fee}

echo -e "\033[0;36m Evaluating Tx \033[0m"
evaluation_result=$(evaluate_transaction "../tmp/tx.draft" | jq -r '.result')
echo $evaluation_result
#
# exit
#
babel_fee_mem=$(echo "$evaluation_result" | jq -r '.[0].budget.memory')
babel_fee_cpu=$(echo "$evaluation_result" | jq -r '.[0].budget.cpu')

babel_fee_execution_units="(${babel_fee_cpu}, ${babel_fee_mem})"
babel_fee_computation_fee=$(echo "0.0000721*${babel_fee_cpu} + 0.0577*${babel_fee_mem}" | bc)
babel_fee_computation_fee_int=$(printf "%.0f" "$babel_fee_computation_fee")
echo "Babel Fee: " $babel_fee_computation_fee_int

babel_fee_size=$(${cli} conway query ref-script-size \
  --tx-in="${babel_fee_ref_utxo}#1" \
  ${network} \
  --output-json | jq -r '.refInputScriptSize')

fee=$(${cli} conway transaction calculate-min-fee \
    --tx-body-file ../tmp/tx.draft \
    --protocol-params-file ../tmp/protocol.json \
    --reference-script-size ${babel_fee_size} \
    --witness-count 3 \
    --output-json | jq -r '.fee')

total_fee=$((${fee} + ${babel_fee_computation_fee_int}))
echo Total Fee: $total_fee

payment_amt=$((1000000 * ${total_fee} / ${payment_rate}))
fee_payment_asset="$((${current_fee_payment} + ${payment_amt})) ${payment_policy_id}.${payment_token_name}"

fee_script_output="${babel_fee_script_address} + $((${current_fee_lovelace} - ${total_fee})) + ${babel_fee_asset} + ${fee_payment_asset}"
echo Babel Fee Output: ${fee_script_output}

if [ $((${current_user_payment} - ${payment_amt})) -eq 0 ]; then
    user_output="${user_address} + $((${current_user_lovelace} - ${receiver_amt}))"
else
    user_payment_asset="$((${current_user_payment} - ${payment_amt})) ${payment_policy_id}.${payment_token_name}"
    user_output="${user_address} + $((${current_user_lovelace} - ${receiver_amt})) + ${user_payment_asset}"
fi
echo User Output: ${user_output}

# exit

echo -e "\033[0;36m Building Tx \033[0m"
${cli} conway transaction build-raw \
    --out-file ../tmp/tx.draft \
    --tx-in-collateral="${collat_utxo}" \
    --tx-in ${user_utxo} \
    --tx-in ${fee_utxo} \
    --spending-tx-in-reference="${babel_fee_ref_utxo}#1" \
    --spending-plutus-script-v3 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/use-redeemer.json \
    --spending-reference-tx-in-execution-units="${babel_fee_execution_units}" \
    --tx-out="${receiver_output}" \
    --tx-out="${user_output}" \
    --tx-out="${fee_script_output}" \
    --tx-out-inline-datum-file  ../data/fixed-babel-fee-datum.json \
    --required-signer-hash ${collat_pkh} \
    --required-signer-hash ${user_pkh} \
    --protocol-params-file ../tmp/protocol.json \
    --fee ${total_fee}
#
# exit
#
echo -e "\033[0;36m Signing \033[0m"
${cli} conway transaction sign \
    --signing-key-file ${user_wallet_path}/payment.skey \
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
    --tx-file ../tmp/tx.signed | jq
