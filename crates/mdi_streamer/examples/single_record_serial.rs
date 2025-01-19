//! A simple app to test the mdi_streamer crate.
//! Compatible with output streamed from mdi_streamer/make_tsv.pl.
//! Uses serial processing of single records.

// dependencies
// use std::{thread, time};
use mdi_streamer::RecordStreamer;
use serde::{Deserialize, Serialize};

// structures
#[derive(Serialize, Deserialize)]
struct MyRecord {
    group:  u32,
    record: u32,
    random: u32,
}

// main
fn main() {
    RecordStreamer::new()
        .stream(update_random)
        .expect("my RecordStreamer failed");
}

// in this example, we simply update a field in the input_record
// therefore, the input and output record structures are the same
fn update_random(input_record: &MyRecord) -> Option<Vec<MyRecord>> {
    // thread::sleep(time::Duration::from_millis(1)); // uncomment here and above to stimulate a slow process
    Some(vec![MyRecord {
        group:  input_record.group,
        record: input_record.record,
        random: input_record.random * 10,
    }])
}
