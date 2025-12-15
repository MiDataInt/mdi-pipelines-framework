//! This binary script demonstrates the performance of DataFrames
//! on large test data sets. It assumes you are already familiar with
//! the basics of DataFrame usage as described in example `data_frame_basics.rs`.
//! 
//! Additional features demonstrated here include:
//!   - Reading a DataFrame from a CSV file
//!   - Factor (categorical) columns

// dependencies
use std::env::args;
use serde::{Serialize, Deserialize};
use mdi::data_frame::prelude::*; // enable all DataFrame features

// Working record structure
#[derive(Serialize, Deserialize)]
struct MyRecord {
    group:  usize,
    record: u32,
    name:   String,
    random: u32,
}

// main
fn main() {

    // get the number of rows to process from command line argument
    let n_row: usize = match args().nth(1) {
        Some(arg1) => arg1.parse().expect("Please provide a valid integer for number of rows to process."),
        None => 1000000, // default to 1 million rows
    };

    // Generate test data and write to CSV file

    // Load a DataFrame from the CSV file.


    // Clean up temporary files.


}
