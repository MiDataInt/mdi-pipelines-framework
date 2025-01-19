//! A simple app to test the mdi_streamer crate.

// dependencies
use mdi_streamer::RecordStreamer;
use serde::{Deserialize, Serialize};

// structures
#[derive(Serialize, Deserialize)]
struct InputRecord {
    group:  u32,
    record: u32,
    random: u32,
}
#[derive(Serialize, Deserialize)]
struct OutputRecord {
    group:  u32,
    record: u32,
    random: u32,
    count:  u16,
}
// impl From<&InputRecord> for OutputRecord {
//     fn from(input_record: &InputRecord) -> Self {
//         let mut output_record: OutputRecord = serde_json::from_value(
//             serde_json::to_value(&input_record).expect("error parsing input record")
//         ).expect("error parsing output_record");
//         output_record.count = 1;
//         output_record
//     }
// }
// impl From<&InputRecord> for OutputRecord {
//     fn from(input_record: &InputRecord) -> Self {
//         OutputRecord {
//             count: 999,
//             ..OutputRecord {
//                 shared_field1: source.shared_field1,
//                 shared_field2: source.shared_field2,
//                 target_only: 0.0, // Placeholder value
//             }
//         }
//     }
// }
impl From<InputRecord> for OutputRecord {
    fn from(input_record: InputRecord) -> Self {
        OutputRecord {
            count: 999,
            ..InputRecord::into(input_record)
        }
    }
}


fn main() {
        // .parallelize(1000, 8) // process 1000 records at a time across 8 CPU cores
        // .has_headers()    
    RecordStreamer::new()
        .stream(|input_record: &InputRecord| {
            let output_record: OutputRecord = OutputRecord::from(*input_record);
            let vec: Vec<OutputRecord> = vec![output_record];
            Some(vec)
        })
        .expect("my RecordStreamer failed");
}
