//// The fee contract pays the fee for the reputation contract.
////

use aiken/collection/list
use aiken/option
use aiken/primitive/bytearray
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, TransactionId,
}
use search
use types.{
  Addition, AssetClass, BabelFeeDatum, BabelFeeMintRedeemer,
  BabelFeeSpendRedeemer, EntryMint, LeaveBurn, Remove, UseFee,
}

validator contract {
  mint(redeemer: BabelFeeMintRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction { inputs, outputs, mint, extra_signatories, .. } = self
    when redeemer is {
      EntryMint -> {
        // The token name is based off the first UTxO being spent
        expect [input, ..]: List<Input> = inputs
        let tx_id: TransactionId = input.output_reference.transaction_id
        let tx_idx: Int = input.output_reference.output_index
        let token_name: AssetName =
          tx_id |> bytearray.push(tx_idx) |> bytearray.slice(0, 31)
        // A single token should be minted in this transaction
        expect [(pid, tkn, amt)]: List<(PolicyId, AssetName, Int)> =
          mint
            |> assets.flatten()
        // find the output that holds this nft
        expect Some(Output {
          address: Address { payment_credential: Script(output_hash), .. },
          value,
          datum: InlineDatum(output_datum_data),
          reference_script,
        }): Option<Output> =
          search.for_output_by_token(outputs, policy_id, token_name)
        // reputation datum needs to be validated so destruct it, do not validate the info_hash
        expect BabelFeeDatum { keeper, pointer, .. } = output_datum_data
        // make sure no dust tokens exist, ada is first then the token being minted
        expect [(_, _, _),
          (_, _, _)]: List<(PolicyId, AssetName, Int)> = assets.flatten(value)
        //
        // The keeper must sign the tx. The pointer token name is
        // stored in the datum for future use. No reference scripts on the output.
        // A single pointer token is being minted using the first input as a token
        // name. The output must be going to this contract.
        //
        and {
          // operator and keeper must sign
          list.has(extra_signatories, keeper)?,
          // token name needs to be in the datum
          (pointer == token_name)?,
          // the reputation output cant have a ref script
          option.is_none(reference_script)?,
          // must be going to the reputation contract
          (policy_id == output_hash)?,
          // must mint nft
          (policy_id == pid)?,
          (token_name == tkn)?,
          (1 == amt)?,
        }
      }
      // single burn here
      LeaveBurn(tkn) -> (( mint |> assets.flatten ) == [(policy_id, tkn, -1)])?
    }
  }

  spend(
    maybe_datum: Option<Data>,
    redeemer: BabelFeeSpendRedeemer,
    utxo: OutputReference,
    self: Transaction,
  ) {
    when maybe_datum is {
      Some(this_datum) ->
        if this_datum is BabelFeeDatum {
          let Transaction {
            inputs,
            outputs,
            fee,
            extra_signatories,
            reference_inputs,
            validity_range,
            ..
          } = self
          expect Some(this_input): Option<Input> =
            transaction.find_input(inputs, utxo)
          // expect the script hash here as we will need it to check for a pointer token later on
          expect Script(this_script) =
            this_input.output.address.payment_credential
          let this_value: Value = this_input.output.value
          when redeemer is {
            Addition(extra) -> {
              // find the output that holds this nft
              expect Some(Output {
                address: Address { payment_credential: Script(that_script), .. },
                value,
                datum: InlineDatum(that_datum_data),
                reference_script,
              }): Option<Output> =
                search.for_output_by_token(
                  outputs,
                  this_script,
                  this_datum.pointer,
                )
              let is_holding_token: Bool =
                assets.quantity_of(this_value, this_script, this_datum.pointer) == 1
              // add the extra lovelace to this value
              let that_value: Value =
                this_value
                  |> assets.add(
                      assets.ada_policy_id,
                      assets.ada_asset_name,
                      extra,
                    )
              //
              //
              //
              and {
                // must hold token
                is_holding_token?,
                // address continuity
                (this_script == that_script)?,
                // value continuity
                (value == that_value)?,
                // datum must be constant
                (as_data(this_datum) == that_datum_data)?,
                // output can not have the reference script
                option.is_none(reference_script)?,
                // must be adding lovelace
                (extra > 0)?,
              }
            }
            UseFee -> {
              let BabelFeeDatum {
                pointer,
                babel_fee,
                asset_class: AssetClass { pid, tkn },
                ..
              } = this_datum
              let rate: Int =
                types.get_babel_rate(
                  babel_fee,
                  reference_inputs,
                  validity_range,
                )
              let babel_fee: Int = 1_000_000 * fee / rate
              // find the output that holds this nft
              expect Some(Output {
                address: Address { payment_credential: Script(that_script), .. },
                value,
                datum: InlineDatum(that_datum_data),
                reference_script,
              }): Option<Output> =
                search.for_output_by_token(outputs, this_script, pointer)
              let is_holding_token: Bool =
                assets.quantity_of(this_value, this_script, pointer) == 1
              // subtract the fee from this value and add the payment
              let that_value: Value =
                this_value
                  |> assets.add(
                      assets.ada_policy_id,
                      assets.ada_asset_name,
                      -fee,
                    )
                  |> assets.add(pid, tkn, babel_fee)
              //
              //
              //
              and {
                // must hold token
                is_holding_token?,
                // address continuity
                (this_script == that_script)?,
                // value continuity
                (value == that_value)?,
                // datum must be constant
                (as_data(this_datum) == that_datum_data)?,
                // output can not have the reference script
                option.is_none(reference_script)?,
              }
            }
            Remove -> {
              let BabelFeeDatum { keeper, pointer, .. } = this_datum
              let is_holding_token: Bool =
                assets.quantity_of(this_value, this_script, pointer) == 1
              if is_holding_token {
                // pointer token must be burnt, so lets check that no output holds that token
                let burn_node_token_name: Bool =
                  list.all(
                    outputs,
                    fn(output) {
                      assets.quantity_of(output.value, this_script, pointer) == 0
                    },
                  )
                //
                // Burn the token and get a signature from the keeper.
                //
                and {
                  list.has(extra_signatories, keeper)?,
                  burn_node_token_name?,
                }
              } else {
                // bad setup default to true
                True
              }
            }
          }
        } else {
          // bad datum default to true
          True
        }
      // missing datum default to true
      None -> True
    }
  }

  else(_) {
    fail
  }
}
