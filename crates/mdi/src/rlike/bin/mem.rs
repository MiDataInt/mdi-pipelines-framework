/// Implement a version of the Apache Arrow Row implementation for sorting RLike DataFrames.
/// See: https://arrow.apache.org/blog/2022/11/07/multi-column-sorts-in-arrow-rust-part-2/

// dependencies
use std::mem::{transmute_copy, size_of_val};

// validation of memory encoding of Option<T> for Rust primitive types
// println!("size_of i32:    {}, Option<i32>:    {}", size_of::<i32>(),   size_of::<Option<i32>>());
// println!("size_of f64:    {}, Option<f64>:    {}", size_of::<f64>(),   size_of::<Option<f64>>());
// println!("size_of bool:   {}, Option<bool>:   {}", size_of::<bool>(),  size_of::<Option<bool>>());
// println!("size_of u16:    {}, Option<u16>:    {}", size_of::<u16>(),   size_of::<Option<u16>>());
// println!("size_of usize:  {}, Option<usize>:  {}", size_of::<usize>(), size_of::<Option<usize>>());
// size_of i32:    4, Option<i32>:    8   == Some/None byte, 3 padding bytes, 4 value bytes
// size_of f64:    8, Option<f64>:    16  == Some/None byte, 7 padding bytes, 8 value bytes
// size_of bool:   1, Option<bool>:   1   == one byte with Some/None in second bit (see below)
// size_of u16:    2, Option<u16>:    4   == Some/None byte, 1 padding bytes, 2 value bytes
// size_of usize:  8, Option<usize>:  16  == Some/None byte, 7 padding bytes, 8 value bytes

/// NA_CELL_KEY is a 9-byte array that represents a None, i.e., NA value in a CellKey.
const NA_CELL_KEY: [u8; 9] = [0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8];

/// A CellKey is a 9-byte array that can be compared lexicographically to determine the sort order of a value.
/// The first byte is a flag indicating whether the value is None (0) or Some (1).
/// The remaining 8 bytes are the packed value, with the sign bit flipped for signed integers and floating point numbers.
/// 9 bytes is not aligned, but we will pack four RowKey4 into a 36-byte u8 slice.
type CellKey = [u8; 9];

/// Trait CellKeyValue is implemented for RLike Option<T> types that can be packed into a CellKey using the pack method.
trait CellKeyValue {
    fn pack(&self) -> CellKey;
}
impl CellKeyValue for Option<i32> { // desired sort: None, -2^31, -1, 0, 1, 2^31-1
    fn pack(&self) -> CellKey {
        let bytes = unsafe { transmute_copy::<_, [u8; 8]>(self) };
        if bytes[0] == 0 {
            NA_CELL_KEY
        } else {
            [1_u8, 0_u8, 0_u8, 0_u8, 0_u8, bytes[7] ^ 0x80, bytes[6], bytes[5], bytes[4]] // flip the sign bit
        }
    }
}
impl CellKeyValue for Option<f64> { // desired sort: None, -inf, -1, 0, 1, inf
    fn pack(&self) -> CellKey {
        let bytes = unsafe { transmute_copy::<_, [u8; 16]>(self) };
        if bytes[0] == 0 {
            NA_CELL_KEY
        } else { // see f64::total_cmp also
            let value = f64::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]]);
            let mut as_i64 = value.to_bits() as i64;
            as_i64 ^= (((as_i64 >> 63) as u64) >> 1) as i64;
            let bytes = as_i64.to_le_bytes();
            [1_u8, bytes[7] ^ 0x80, bytes[6], bytes[5], bytes[4], bytes[3], bytes[2], bytes[1], bytes[0]]
        }
    }
}
impl CellKeyValue for Option<bool> { // desired sort: None, false, true
    fn pack(&self) -> CellKey {
        let byte = unsafe { transmute_copy::<_, u8>(self) }; // one byte
        if byte & 0x2 == 0x2 { // None has bit 2 == 1
            NA_CELL_KEY
        } else {
            [1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, byte & 0x1]
        }
    }
}
impl CellKeyValue for Option<u16> { // desired sort: None, 0, 1, 2^16-1
    fn pack(&self) -> CellKey {
        let bytes = unsafe { transmute_copy::<_, [u8; 4]>(self) };
        if bytes[0] == 0 {
            NA_CELL_KEY
        } else {
            [1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, bytes[3], bytes[2]]
        }
    }
}
impl CellKeyValue for Option<usize> { // desired sort: None, 0, 1, 2^64-1
    fn pack(&self) -> CellKey {
        let bytes = unsafe { transmute_copy::<_, [u8; 16]>(self) };
        if bytes[0] == 0 {
            NA_CELL_KEY
        } else {
            [1_u8, bytes[15], bytes[14], bytes[13], bytes[12], bytes[11], bytes[10], bytes[9], bytes[8]]
        }
    }
}

/// A RowKey4 is a 36-byte array that can be compared lexicographically to determine the sort order of a row.
/// The size is fixed at four CellKeys, which is the maximum number of columns that can be sorted at once.
/// The four CellKeys are stored such that the first CellKey in the array is the major sort group.
/// Because a CellKey always uses 9 bytes, any data type can be placed into any sorting position.
struct RowKey4s ([CellKey; 4]);

macro_rules! print_bits {
    ($data:expr, $size_of:literal) => {
        for ot in $data {
            println!("{:?} => {} bytes", ot, size_of_val(&ot));
            let bytes = unsafe { 
                transmute_copy::<_, [u8; $size_of]>(&ot) 
            };
            // Print bytes as they are stored in memory (no reversing little-endian)
            for byte in bytes.iter() {
                print!("{:08b} ", byte);
            }
            println!();
            for byte in ot.pack().iter() {
                print!("{:08b} ", byte);
            }
            println!();
        }
    };
}

fn sort_it<RL: CellKeyValue + Clone>(data: Vec<RL>) ->  Vec<RL>{
    let sort_keys: Vec<CellKey> = data.iter().map(|x| x.pack()).collect();
    let mut i_map  = (0..sort_keys.len()).collect::<Vec<_>>();
    i_map.sort_by_key(|&i| &sort_keys[i]);
    i_map.into_iter().map(|i| data[i].clone()).collect()
}

fn main(){

    println!();
    println!("i32");
    let x: Vec<Option<i32>> = vec![Some(255 << 8), Some(-253), Some(255), Some(255 << 16), None, Some(255 << 24), Some(0), Some(1), Some(-1)];
    // print_bits!(x.clone(), 8);
    println!("{:?}", sort_it(x));

    println!();
    println!("f64");
    let x: Vec<Option<f64>> = vec![Some(0.0), Some(-0.0), Some(0.0/0.0), None, Some(f64::INFINITY), Some(f64::NEG_INFINITY), 
                                   Some(-1.0), Some(1.0), Some(12.5), Some(255.0), None, Some(-255.0),
                                   Some(0.002),Some(0.001),Some(0.003),
                                   Some(-0.002),Some(-0.001),Some(-0.003)];
    // print_bits!(x.clone(), 16);
    println!("{:?}", sort_it(x));

    println!();
    println!("bool");
    let x: Vec<Option<bool>> = vec![Some(true), None, Some(false), Some(false), None, Some(true)];
    // print_bits!(x.clone(), 8);
    println!("{:?}", sort_it(x));

    println!();
    println!("u16");
    let x: Vec<Option<u16>> = vec![Some(255), Some(255 << 8), None, Some(1), Some(0), None];
    // print_bits!(x.clone(), 8);
    println!("{:?}", sort_it(x));

    println!();
    println!("usize");
    let x: Vec<Option<usize>> = vec![Some(255), Some(255 << 8), None, Some(1), Some(0), None];
    // print_bits!(x.clone(), 8);
    println!("{:?}", sort_it(x));

}
