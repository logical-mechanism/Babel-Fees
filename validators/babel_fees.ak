//// A hyperstructure babel fee contract.
////

use aiken/collection/list
use aiken/math
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
  BabelFeeSpendRedeemer, Remove, UseFee,
}
use validate

validator contract {
  mint(redeemer: BabelFeeMintRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction { inputs, outputs, mint, extra_signatories, .. } = self
    expect [input, ..]: List<Input> = inputs
    let tx_id: TransactionId = input.output_reference.transaction_id
    let tx_idx: Int = input.output_reference.output_index
    let token_name: AssetName =
      tx_id |> bytearray.push(tx_idx) |> bytearray.slice(0, 31)
    and {
      validate.validate_babel_pointer(
        redeemer,
        token_name,
        policy_id,
        mint,
        outputs,
        extra_signatories,
      )?,
      validate.validate_length_and_uniqueness(mint, policy_id, redeemer)?,
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
          // only valid utxos holding the nft
          let is_holding_token: Bool =
            assets.quantity_of(this_value, this_script, this_datum.pointer) == 1
          //
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
              // add the extra lovelace to this value
              let that_value: Value =
                this_value
                  |> assets.add(
                      assets.ada_policy_id,
                      assets.ada_asset_name,
                      extra,
                    )
              //
              // Everything remains constant but the value. Only lovelace can
              // be added to the UTxO.
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
                asset_class: AssetClass { pid, tkn, precision },
                ..
              } = this_datum
              // the rate is fixed or oracle derived
              let rate: Int =
                types.get_babel_rate(
                  babel_fee,
                  reference_inputs,
                  validity_range,
                )
              // precision will scale the babel fee properly
              let babel_fee: Int = math.pow(10, precision) * fee / rate
              // find the output that holds this nft
              expect Some(Output {
                address: Address { payment_credential: Script(that_script), .. },
                value,
                datum: InlineDatum(that_datum_data),
                reference_script,
              }): Option<Output> =
                search.for_output_by_token(outputs, this_script, pointer)
              // subtract the fee from this value and add the babel fee
              let that_value: Value =
                this_value
                  |> assets.add(
                      assets.ada_policy_id,
                      assets.ada_asset_name,
                      -fee,
                    )
                  |> assets.add(pid, tkn, babel_fee)
              //
              // Everything remains constant but the value. The fee is removed
              // and the babel fee is added.
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
                // Burn the token and get a signature from the keeper. This logic
                // will allow updates, extraction, and removal. Update and extract
                // will result in some new pointer token.
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
