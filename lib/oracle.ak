use aiken/builtin
use aiken/interval.{
  Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity,
}
use cardano/transaction.{ValidityRange}

/// A finite moment of time represented as simple start and end integers.
pub type Moment {
  start: Int,
  end: Int,
}

/// Check if a moment data structure is logical. 
pub fn is_logical(m: Moment) -> Bool {
  and {
    m.end >= m.start,
    m.start >= 0,
    m.end >= 0,
  }
}

/// Check if a validity range is contained within some moment.
/// This assumes inclusivity.
///
/// |start--|lower----upper|--end|
///
pub fn is_contained(m: Moment, vr: ValidityRange) -> Bool {
  when vr.lower_bound.bound_type is {
    // must be finite
    NegativeInfinity -> False
    // get the lower bound int
    Finite(lower_bound) ->
      when vr.upper_bound.bound_type is {
        // must be finite
        NegativeInfinity -> False
        // get the upper bound int
        Finite(upper_bound) -> and {
            // the lower bound is greater than or equal the start of the moment
            m.start <= lower_bound,
            // the upper bound is less or equal to the end of the moment
            upper_bound <= m.end,
          }
        // must be finite
        PositiveInfinity -> False
      }
    // must be finite
    PositiveInfinity -> False
  }
}

pub type PriceMap =
  Pairs<Int, Data>

pub type PriceData {
  SharedData
  ExtendedData
  GenericData { price_map: PriceMap }
}

pub type OracleDatum {
  price_data: PriceData,
}

pub fn get_moment(datum: OracleDatum) -> Moment {
  when datum.price_data is {
    GenericData { price_map } -> {
      expect start: Int = find_value(price_map, 1)
      expect end: Int = find_value(price_map, 2)
      let m: Moment = Moment { start, end }
      if is_logical(m) {
        m
      } else {
        fail @"Illogical Moment Data"
      }
    }
    _ -> fail @"Price Data Not Generic Data"
  }
}

pub fn get_price(datum: OracleDatum) -> Int {
  when datum.price_data is {
    GenericData { price_map } -> {
      expect price: Int = find_value(price_map, 0)
      price
    }
    _ -> fail @"Price Data Not Generic Data"
  }
}

pub fn find_value(data: PriceMap, key: Int) -> Data {
  when data is {
    [] -> fail @"Value Not Found"
    [d, ..ds] ->
      if builtin.fst_pair(d) == key {
        builtin.snd_pair(d)
      } else {
        find_value(ds, key)
      }
  }
}
