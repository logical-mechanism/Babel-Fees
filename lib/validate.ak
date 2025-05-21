use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/option
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{InlineDatum, Output}
use search
use types.{BabelFeeDatum, BabelFeeMintRedeemer, EntryMint, LeaveBurn}

pub fn validate_babel_pointer(
  mint_types: BabelFeeMintRedeemer,
  pre_image: ByteArray,
  policy_id: PolicyId,
  mint: Value,
  outputs: List<Output>,
  extra_signatories: List<VerificationKeyHash>,
) -> Bool {
  when mint_types is {
    [mint_type, ..rest] ->
      when mint_type is {
        EntryMint -> {
          let token_name: AssetName = crypto.blake2b_256(pre_image)
          // find the output that holds this nft
          expect Some(Output {
            address: Address { payment_credential: Script(output_hash), .. },
            value,
            datum: InlineDatum(output_datum_data),
            reference_script,
          }): Option<Output> =
            search.for_output_by_token(outputs, policy_id, token_name)
          // we need the keeper and pointer from the babel fee datum
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
            //
            (assets.quantity_of(mint, policy_id, token_name) == 1)?,
            // keeper must sign
            list.has(extra_signatories, keeper)?,
            // token name needs to be in the datum
            (pointer == token_name)?,
            // the output cant have a ref script
            option.is_none(reference_script)?,
            // must be going to this contract
            (policy_id == output_hash)?,
          } && validate_babel_pointer(
            rest,
            token_name,
            policy_id,
            mint,
            outputs,
            extra_signatories,
          )
        }
        // check if the burn is happening
        LeaveBurn { tkn } ->
          assets.quantity_of(mint, policy_id, tkn) == -1 && validate_babel_pointer(
            rest,
            pre_image,
            policy_id,
            mint,
            outputs,
            extra_signatories,
          )
      }
    [] -> True
  }
}

pub fn validate_length_and_uniqueness(
  mint: Value,
  policy_id: PolicyId,
  mint_types: BabelFeeMintRedeemer,
) -> Bool {
  and {
    (
      assets.tokens(mint, policy_id)
        |> dict.size
    ) == list.length(mint_types),
    unique_token_names(mint_types),
  }
}

pub fn unique_token_names(mint_types: BabelFeeMintRedeemer) -> Bool {
  let token_names: List<AssetName> =
    list.filter_map(
      mint_types,
      fn(mint_type) {
        when mint_type is {
          EntryMint -> None
          LeaveBurn { tkn } -> Some(tkn)
        }
      },
    )
  list.unique(token_names) == token_names
}
