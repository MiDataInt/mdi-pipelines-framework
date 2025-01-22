//! A simple app to show the use of mdi::RecordStreamer::stream_replace_serial().
//! Compatible with output streamed from mdi_streamer/make_tsv.pl.

// dependencies
use std::{thread, time};
use rand::Rng;
use mdi::RecordStreamer;
use serde::{Deserialize, Serialize};

// structures, with support for record parsing using serde
#[derive(Serialize, Deserialize)]
struct InputRecord {
    group:  u32,
    record: u32,
    name:   String,
    random: u32,
}
#[derive(Serialize, Deserialize)]
struct OutputRecord {
    group:  u32,
    record: u32,
    name:   String,
    random: u32,
    proof:  String,
}

// main
fn main() {
    RecordStreamer::new()
        .stream_replace_serial(record_parser)
        .expect("mdi::RecordStreamer::stream_replace_serial failed");
}

// record parsing function
fn record_parser(input_record: &InputRecord) -> Option<Vec<OutputRecord>> {

    // simulate a slow process by sleeping for a random number of milliseconds
    // output order will be retained (obligatorily since records are processed serially)
    let milli_seconds: u64 = rand::thread_rng().gen_range(0..5);
    thread::sleep(time::Duration::from_millis(milli_seconds)); 

    // filter against some records by returning None
    if input_record.group > 5 && input_record.group < 10 {
        None
    } else {

        // create a new output record
        let output_record = OutputRecord {
            group:  input_record.group,
            record: input_record.record,
            name:   input_record.name.clone(),
            random: input_record.random * 100,
            proof:  format!("{}-{}", input_record.name, "stream_replace_serial")
        };

        // return the new output record(s)
        Some(vec![output_record])
    }
}
