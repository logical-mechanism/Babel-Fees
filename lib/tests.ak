use aiken/crypto

test fixed_rate_payment_amount_1() {
  // 0.243532 ADA
  let fee: Int = 243_532
  // token price in ADA to be paid at
  let rate: Int = 238_880
  let babel_fee: Int = 1_000_000 * fee / rate
  // 1.019474 Tokens
  babel_fee == 1_019_474
}

test fixed_rate_payment_amount_2() {
  // 0.475321 ADA
  let fee: Int = 475_321
  // token price in ADA to be paid at
  let rate: Int = 800
  let babel_fee: Int = 1_000_000 * fee / rate
  // 594.151250 Tokens
  babel_fee == 594_151_250
}

test fixed_rate_payment_amount_3() {
  // 0.353573 ADA
  let fee: Int = 353_573
  // token price in ADA to be paid at
  let rate: Int = 1_411_440
  let babel_fee: Int = 1_000_000 * fee / rate
  // 0.250505 Tokens
  babel_fee == 250_505
}

test fixed_rate_payment_amount_4() {
  // 0.339423 ADA
  let fee: Int = 339_423
  // token price in ADA to be paid at
  let rate: Int = 1_000_000
  let babel_fee: Int = 1_000_000 * fee / rate
  // 0.339423 Tokens
  babel_fee == 339_423
}

test hash_token_name() {
  let pre_image: ByteArray =
    #"00211e7857e5088ea0ebfc6ad4f583d74c9f834a2ac7b4caafb7818a6b00cde6"
  let token_name: ByteArray = crypto.blake2b_256(pre_image)
  token_name == #"a8715bf86cc1b91390b696ffacf3b3aaef258ad6dbe922af7aaf94e6e00479d4"
}
