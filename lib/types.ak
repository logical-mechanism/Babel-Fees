use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{AssetName, Lovelace, PolicyId}
use cardano/transaction.{InlineDatum, Input, Output, ValidityRange}
use oracle.{Moment, OracleDatum}
use search

pub type BabelFeeSpendRedeemer {
  Addition(Lovelace)
  UseFee
  Remove
}

pub type BabelFeeMintRedeemer {
  EntryMint
  LeaveBurn(AssetName)
}

pub type AssetClass {
  pid: PolicyId,
  tkn: AssetName,
  // most assets are 6 but some have less and that needs to be accounted for during the price calculation
  precision: Int,
}

pub type BabelFee {
  // use c3 here for the price
  C3OracleRate { feed_vkh: ScriptHash, feed_pid: PolicyId, feed_tkn: AssetName }
  // just set some fix price
  FixedRate { price: Int }
}

pub type BabelFeeDatum {
  // owner of this reputation
  keeper: VerificationKeyHash,
  // unique identifier
  pointer: AssetName,
  // determine the babel fee type
  babel_fee: BabelFee,
  // asset class to be paid in
  asset_class: AssetClass,
}

pub fn get_babel_rate(
  babel_fee: BabelFee,
  reference_inputs: List<Input>,
  validity_range: ValidityRange,
) -> Int {
  when babel_fee is {
    C3OracleRate { feed_vkh, feed_pid, feed_tkn } -> {
      // we need to use the oracle feed so get the input's output
      expect Some(Input {
        output: Output { value, datum: InlineDatum(output_datum_data), .. },
        ..
      }): Option<Input> =
        search.for_input_by_script_hash(reference_inputs, feed_vkh)
      expect feed_datum: OracleDatum = output_datum_data
      let feed_price: Int = oracle.get_price(feed_datum)
      let feed_moment: Moment = oracle.get_moment(feed_datum)
      if and {
        (assets.quantity_of(value, feed_pid, feed_tkn) == 1)?,
        oracle.is_contained(feed_moment, validity_range)?,
      } {
        feed_price
      } else {
        // use zero to force an error here
        0
      }
    }
    FixedRate { price } ->
      if price > 0 {
        price
      } else {
        // use zero to force an error here
        0
      }
  }
}
