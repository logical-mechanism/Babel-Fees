use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Input, Output}

/// Find the first occurance of an output with a value that contains a specific
/// token. The token amount does not matter here, it just needs to at least one.
///
/// ```aiken
/// search.for_output_by_token(outputs, pid, tkn)
/// ```
pub fn for_output_by_token(
  outputs: List<Output>,
  pid: PolicyId,
  tkn: AssetName,
) -> Option<Output> {
  list.find(
    outputs,
    fn(Output { value, .. }) { assets.quantity_of(value, pid, tkn) >= 1 },
  )
}

/// Find the first occurance of an input that has a specific script hash.
///
/// ```aiken
/// search.for_input_by_script_hash(inputs, script_hash)
/// ```
///
pub fn for_input_by_script_hash(
  inputs: List<Input>,
  the_script: ScriptHash,
) -> Option<Input> {
  list.find(
    inputs,
    fn(
      Input {
        output: Output { address: Address { payment_credential, .. }, .. },
        ..
      },
    ) {
      payment_credential == Script(the_script)
    },
  )
}
