//! A simple app to show the use of mdi::RecordStreamer::group_by_replace_parallel().
//! Compatible with output streamed from mdi_streamer/make_tsv.pl.

// dependencies
use std::{thread, time};
use std::cmp::min;
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
    group:      u32,
    n_records:  usize,
    min_random: u32,
    proof:      String,
}

// constants, for parallel processing
const METHOD:      &str  = "group_by_replace_parallel";
const N_CPU:       usize = 4;
const BUFFER_SIZE: usize = 1000;

// main
fn main() {

    // demonstrate passing of immutable values to the record parser
    let proof: String = METHOD.to_string();
    let record_parser = |input_record_group: &Vec<InputRecord>| -> Option<Vec<OutputRecord>> {
        parse_with_proof(input_record_group, &proof)
    };
    RecordStreamer::new()
        .group_by_replace_parallel(record_parser, "group", N_CPU, BUFFER_SIZE)
        .expect("mdi::RecordStreamer::group_by_replace_parallel failed");
}

// record parsing function
fn parse_with_proof(input_record_group: &Vec<InputRecord>, proof: &str) -> Option<Vec<OutputRecord>> {

    // simulate a slow process by sleeping for a random number of milliseconds
    // output order will be retained by par_iter.map()
    let milli_seconds: u64 = rand::thread_rng().gen_range(0..5);
    thread::sleep(time::Duration::from_millis(milli_seconds)); 

    // filter against some record groups by returning None
    let group = input_record_group[0].group;
    if group > 5 && group < 10 {
        None
    } else {

        // create a new aggregated output record
        let mut output_record = OutputRecord {
            group:      group,
            n_records:  input_record_group.len(),
            min_random: input_record_group[0].random,
            proof:      format!("{}-{}", input_record_group[0].name, proof),
        };

        // apply aggregation functions using the remaining records
        if input_record_group.len() > 1 {
            for input_record in input_record_group.iter().skip(1) {
                output_record.min_random = min(output_record.min_random, input_record.random);
            }
        }

        // return the new output record(s)
        Some(vec![output_record])
    }
}
