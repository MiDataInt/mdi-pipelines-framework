//! A simple app to test the mdi_streamer crate.
//! Compatible with output streamed from mdi_streamer/make_tsv.pl.
//! Uses parallel processing of grouped records.

// dependencies
use std::cmp::min;
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
    group:      u32,
    min_random: u32,
    n_records:  usize,
}

// main
fn main() {
    RecordStreamer::new()
        .parallelize(1000, 4) // process 1000 groups at a time across 4 CPU cores
        .group_by("group", aggregate)
        .expect("my RecordStreamer failed");
}

// in this example, we filter and aggregate by group
// therefore, we need both and input and a distinct output structure
fn aggregate(group_input_records: &Vec<InputRecord>) -> Option<Vec<OutputRecord>> {
    
    // example of how to filter with a return result of None
    if group_input_records[0].group < 10 {
        return None
    }

    // unfiltered groups return Some(Vec<OutputRecord>)
    let mut output_record: OutputRecord = OutputRecord {
        group:      group_input_records[0].group,
        min_random: group_input_records[0].random,
        n_records:  group_input_records.len(),
    };
    if output_record.n_records > 1 {
        for input_record in group_input_records[1..].into_iter() {
            output_record.min_random = min(output_record.min_random, input_record.random);
        }
    }
    Some(vec![output_record])
}
