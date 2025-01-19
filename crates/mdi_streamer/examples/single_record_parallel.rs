//! A simple app to test the mdi_streamer crate.
//! Compatible with output streamed from mdi_streamer/make_tsv.pl.
//! Uses parallel processing of single records.

// dependencies
// use std::{thread, time};
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
    group:     u32,
    record:    u32,
    random:    u32,
    new_field: u32,
}

// main
fn main() {
    RecordStreamer::new()
        .parallelize(1000, 4) // process 1000 records at a time across 4 CPU cores
        .stream(add_new_field)
        .expect("my RecordStreamer failed");
}

// in this example, we add a new field to the input_record
// therefore, we need both and input and a distinct output structure
fn add_new_field(input_record: &InputRecord) -> Option<Vec<OutputRecord>> {
    // thread::sleep(time::Duration::from_millis(1)); // uncomment here and above to stimulate a slow process
    Some(vec![OutputRecord {
        group:  input_record.group,
        record: input_record.record,
        random: input_record.random,
        new_field: 999,
    }])
}
