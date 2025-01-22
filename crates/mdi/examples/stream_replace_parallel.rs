//! A simple app to show the use of mdi::RecordStreamer::stream_replace_parallel().
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

// constants, for parallel processing
const METHOD:      &str  = "stream_replace_parallel";
const N_CPU:       usize = 4;
const BUFFER_SIZE: usize = 1000;

// main
fn main() {

    // demonstrate passing of immutable values to the record parser
    let proof: String = METHOD.to_string();
    let record_parser = |input_record: &InputRecord| -> Option<Vec<OutputRecord>> {
        parse_with_proof(input_record, &proof)
    };
    RecordStreamer::new()
        .stream_replace_parallel(record_parser, N_CPU, BUFFER_SIZE)
        .expect("mdi::RecordStreamer::stream_replace_parallel failed");
}

// record parsing function
fn parse_with_proof(input_record: &InputRecord, proof: &str) -> Option<Vec<OutputRecord>> {

    // simulate a slow process by sleeping for a random number of milliseconds
    // output order will be retained by par_iter.map()
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
            proof:  format!("{}-{}", input_record.name, proof)
        };

        // return the new output record(s)
        Some(vec![output_record])
    }
}
