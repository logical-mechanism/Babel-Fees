#!/usr/bin/env bash
set -e

# SET UP VARS HERE
source .env

# get current parameters
mkdir -p ./tmp
${cli} conway query protocol-parameters ${network} --out-file ./tmp/protocol.json
${cli} conway query tip ${network} | jq

# Loop the contract in the contract folder
for script_file in ../contracts/*.plutus; do
    contract=$(basename "$script_file")
    script_address=$(${cli} conway address build --payment-script-file ${script_file} ${network})
    echo -e "\033[1;37m--------------------------------------------------------------------------------\033[0m"
    echo -e "\033[1;34m $contract\033[0m\n\n\033[1;32m $script_address\033[0m"

    ${cli} conway query utxo --address ${script_address} ${network}
    ${cli} conway query utxo --address ${script_address} ${network} --out-file ./tmp/current_${contract}_utxo.json
done
echo -e "\033[1;37m--------------------------------------------------------------------------------\033[0m"
echo -e "\033[1;37m--------------------------------------------------------------------------------\033[0m"
# Loop through each -wallet folder
for wallet_folder in wallets/*-wallet; do
    # Check if payment.addr file exists in the folder
    if [ -f "${wallet_folder}/payment.addr" ]; then
        addr=$(cat ${wallet_folder}/payment.addr)

        echo
        echo -e "\033[1;37m--------------------------------------------------------------------------------\033[0m"
        echo -e "\033[1;34m $wallet_folder\033[0m\n\n\033[1;32m $addr\033[0m"

        echo -e "\033[1;33m"
        # Run the cardano-cli command with the reference address and testnet magic
        ${cli} conway query utxo --address ${addr} ${network}
        ${cli} conway query utxo --address ${addr} ${network} --out-file ./tmp/"${addr}.json"

        # Sum up the lovelace at the wallets
        baseLovelace=$(jq '[.. | objects | .lovelace] | add' ./tmp/"${addr}.json")
        
        echo -e "\033[0m"
        echo -e "\033[1;36m"

        ada=$(echo "scale = 6;${baseLovelace} / 1000000" | bc -l)
        echo -e "TOTAL ADA:" ${ada}
        echo -e "\033[0m"
    fi
done
