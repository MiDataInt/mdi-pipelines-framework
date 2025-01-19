//! The mdi_streamer crate supports MDI pipelines by providing
//! a framework to manipulate tabular records in data streams.
//! Data are read from STDIN and written to STDOUT to function within a Unix stream.
//! This makes it easier to create executable crates that can be chained together,
//! with each crate performing a specific task in a data processing pipeline.
//!
//! Create a new RecordStreamer instance with default settings using
//! `mdi_streamer::RecordStreamer::new()`.
//!
//! Input records can be handled either:
//! - one record at a time using the `stream()` function, or
//! - over multiple records in an keyed batch using the `group_by()` function
//! Either method allows zero, one, or many output records to be generated from each (set of) input records.
//!
//! Record/group parsing can be done either:
//! - serially (the default), or
//! - in parallel using a record buffer by calling `parallelize(buffer_size: usize, n_cpu: usize)` on the RecordStreamer
//! Only benchmarking can determine which is faster for a given task,
//! which will depend on the complexity of the parsing function.
//!
//! Input and output records are assumed to be:
//! - without headers, unless `has_headers()` is called on the RecordStreamer
//! - tab-delimited, unless `delimiter(b'<delimiter>')` is called on the RecordStreamer
//!
//! Fields in input records will be trimmed of leading and trailing whitespace 
//! unless `trim(csv::Trim::None)` is called on the RecordStreamer.
//!
//! Streaming is executed by calling `stream(|record: &InputRecord|{})` 
//! or `group_by(grouping_field: &str, |records: &[InputRecord]|{})` on the RecordStreamer, 
//! where the caller defines and provides:
//! - InputRecord  = a Struct that defines the data type of each input record
//! - OutputRecord = a Struct that defines the data type of each output record
//! - a parsing function that processes the data, returning:
//!   - None if no record(s) should be written to the output stream for a (set of) input record(s), or
//!   - Some(Vec<OutputRecord>) specifying the output record(s) resulting from the input record(s)
//!
//! The work to be done on input records is arbitrary and defined by the caller.
//! Some examples of work that can be done include:
//! - filtering records based on a condition
//! - transforming records into one or more output records
//! - aggregating records into a single output record
//! - updating or adding a field in a record
//!
//! Importantly, the InputRecord and OutputRecord structures can be the same or entirely different.

// dependencies
use std::error::Error;
use std::io::{self};
// use rayon::prelude::*;
use serde::{de::DeserializeOwned, Serialize};
// use serde_json::Value;

/// Initialize a record streamer.
pub struct RecordStreamer {
    buffer_size: Option<usize>, // optional parameters for parallel processing
    n_cpu:       Option<usize>,
    has_headers: bool,
    delimiter:   u8,
    trim:        csv::Trim,
}
impl Default for RecordStreamer {
    fn default() -> RecordStreamer {
        RecordStreamer {
            buffer_size: None,
            n_cpu:       None,
            has_headers: false,
            delimiter:   b'\t',
            trim:        csv::Trim::Fields,
        }
    }
}
impl RecordStreamer {

    /// Create a new RecordStreamer instance with default settings.
    /// 
    /// ## Example
    /// ```
    /// use mdi_streamer::RecordStreamer;
    /// 
    /// struct InputRecord {} // as needed to define record fields
    /// struct OutputRecord {}
    /// 
    /// let rs = RecordStreamer::new()
    ///     .parallelize(1000, 8) // process 1000 records at a time across 8 CPU cores
    ///     .has_headers()
    ///     .stream(|record: &InputRecord| {
    ///         // process record into None or Some(Vec<OutputRecord>)
    ///     })
    ///     .expect("my RecordStreamer failed");
    /// // ... or ...
    /// let rs = RecordStreamer::new()
    ///     .group_by("UUID", |records: &[InputRecord]| { // group records by UUID field
    ///         // process records into None or Some(Vec<OutputRecord>)
    ///     })
    ///     .expect("my RecordStreamer failed");
    /// ```
    pub fn new() -> RecordStreamer {
        RecordStreamer::default()
    }

    /// Set the options to process records in parallel.
    ///
    /// Parameter `buffer_size` specifies the number of records to process in parallel.
    /// Parameter `n_cpu` specifies the number of CPU cores to use for parallel processing.
    pub fn parallelize(&mut self, buffer_size: usize, n_cpu: usize) -> &mut Self {
        self.buffer_size = Some(buffer_size);
        self.n_cpu = Some(n_cpu);
        self
    }

    /// Set the csv has_headers option to true for the input and output streams.
    pub fn has_headers(&mut self) -> &mut Self {
        self.has_headers = true;
        self
    }

    /// Set the csv delimiter for the input and output streams if not tab-delimited.
    pub fn delimiter(&mut self, delimiter: u8) -> &mut Self {
        self.delimiter = delimiter;
        self
    }

    /// Set the csv trim option for the input stream if whitespace trimming is not needed.
    pub fn trim(&mut self, trim: csv::Trim) -> &mut Self {
        self.trim = trim;
        self
    }

    /// Stream single records from STDIN to STDOUT.
    ///
    /// The `stream()` function processes input records one at a time as they are encountered.
    pub fn stream<I, O, F>(&self, record_parser: F) -> Result<(), Box<dyn Error>>
    where
        I: DeserializeOwned + Serialize,
        O: Serialize,
        F: Fn(&I) -> Option<Vec<O>>,
    {
        // get I/O streams
        let (mut rdr, mut wtr) = get_io_streams(self).expect("RecordStreamer failed to open I/O streams on STDIN and/or STDOUT");
        let mut line_number: u64 = 0;

        // if requested, process records in chunks with parallel processing of each chunk ...
        if let Some(buffer_size) = self.buffer_size {
            init_parallel(self).expect("RecordStreamer failed to initialize parallel processing");
            let mut input_records: Vec<I> = Vec::with_capacity(buffer_size);
            for result in rdr.deserialize() {
                line_number += 1;
                let input_record: I = result.expect(&format!("RecordStreamer failed to parse input line {}", line_number));
                input_records.push(input_record);
                if input_records.len() >= buffer_size {
                    // process_record_buffer(&mut wtr, &input_records, &record_parser)
                    //     .expect(&format!("RecordStreamer failed to process buffer near input line {}", line_number));
                    input_records.clear();
                }
            }
            // process_record_buffer(&mut wtr, &input_records, &record_parser)
            //     .expect("RecordStreamer failed to process the last buffered chunk");

        // .. otherwise process records one at a time
        } else {
            for result in rdr.deserialize() {
                line_number += 1;
                let input_record: I = result.expect(&format!("RecordStreamer failed to parse input line {}", line_number));
                process_record(&mut wtr, &input_record, &record_parser)
                    .expect(&format!("RecordStreamer failed to process input record {}", line_number));
            }
        }

        // finish up and return success
        wtr.flush().expect("RecordStreamer failed while flushing last records in output stream");
        Ok(())
    }

    /// Stream keyed groups of records from STDIN to STDOUT.
    ///
    /// The `group_by()` function processes input records in batches based on the key value in field `grouping_field`.
    pub fn group_by<I, O, F>(&self, grouping_field: &str, record_parser: F) -> Result<(), Box<dyn Error>>
    where
        I: DeserializeOwned + Serialize,
        O: Serialize,
        F: Fn(&[I]) -> Option<Vec<O>>,
    {
        // get I/O streams
        let (mut rdr, mut wtr) = get_io_streams(self).expect("RecordStreamer failed to open I/O streams on STDIN and/or STDOUT");
        let mut line_number: u64 = 0;

        // if requested, process grouped records in chunks of groups with parallel processing of each chunk ...
        if let Some(buffer_size) = self.buffer_size {
            init_parallel(self).expect("RecordStreamer failed to initialize parallel processing");
            let mut buffered_groups: Vec<Vec<I>> = Vec::new();
            let mut working_group: Vec<I> = Vec::new();
            let mut previous_key: Option<String> = None;
            for result in rdr.deserialize() {
                line_number += 1;
                let input_record: I = result.expect(&format!("RecordStreamer failed to parse input line {}", line_number));
                let this_key = get_field_value(&input_record, grouping_field)
                    .expect(&format!("RecordStreamer failed to get group key from line {}", line_number));
                if previous_key.as_ref().map_or(false, |k| k != &this_key) {
                    buffered_groups.push(working_group);
                    // working_group.clear();
                    working_group = Vec::new(); // prevents move error with working_group.clear();
                    if buffered_groups.len() >= buffer_size {
                        // process_group_buffer(&mut wtr, &buffered_groups, &record_parser)
                        //     .expect(&format!("RecordStreamer failed to process group buffer before input line {}", line_number));
                        buffered_groups.clear();
                    }
                }
                previous_key = Some(this_key);
                working_group.push(input_record);
            }
            buffered_groups.push(working_group); // handle last group and buffer
            // process_group_buffer(&mut wtr, &buffered_groups, &record_parser)
            //     .expect("RecordStreamer failed to process last group buffer");

        // .. otherwise process grouped records one group at a time
        } else {
            let mut working_group: Vec<I> = Vec::new();
            let mut previous_key: Option<String> = None;
            for result in rdr.deserialize() {
                line_number += 1;
                let input_record: I = result.expect(&format!("RecordStreamer failed to parse input line {}", line_number));
                let this_key = get_field_value(&input_record, grouping_field)
                    .expect(&format!("RecordStreamer failed to get group key from line {}", line_number));
                if previous_key.as_ref().map_or(false, |k| k != &this_key) {
                    process_group(&mut wtr, &working_group, &record_parser)
                        .expect(&format!("RecordStreamer failed to process group ending at line {}", line_number - 1));
                    working_group.clear();
                }
                previous_key = Some(this_key);
                working_group.push(input_record);
            }
            process_group(&mut wtr, &working_group, &record_parser)
                .expect("RecordStreamer failed to process the last group");
        }

        // finish up and return success
        wtr.flush().expect("RecordStreamer failed while flushing last records in output stream");
        Ok(())
    }
}

// private function to return a paired stream reader and writer for STDIN and STDOUT
// by design, headers and delimiters are handled the same for both input and output streams
fn get_io_streams(rs: &RecordStreamer) -> Result<(
    csv::Reader<std::io::Stdin>, 
    csv::Writer<std::io::Stdout>
), Box<dyn Error>> {
    let rdr = csv::ReaderBuilder::new()
        .has_headers(rs.has_headers)
        .delimiter(rs.delimiter)
        .trim(rs.trim)
        .from_reader(io::stdin());
    let wtr = csv::WriterBuilder::new()
        .has_headers(rs.has_headers)
        .delimiter(rs.delimiter)
        .from_writer(io::stdout());
    Ok((rdr, wtr))
}

// private function to initialize the number of parallel processing threads
fn init_parallel(rs: &RecordStreamer) -> Result<(), Box<dyn Error>> {
    if let Some(n_cpu) = rs.n_cpu {
        rayon::ThreadPoolBuilder::new().num_threads(n_cpu).build_global()?;
    }
    Ok(())
}

// private function to get the value of the key field in a record
// returns an error if the named field is not found in the record structure
fn get_field_value<T: Serialize>(record: &T, grouping_field: &str) -> Result<String, Box<dyn Error>> {
    let value = serde_json::to_value(record)?;
    match value.get(grouping_field) {
        Some(v) => Ok(v.to_string().trim_matches('"').to_string()),
        None => Err(format!("Field '{}' not found in record", grouping_field).into())
    }
}

// // private function to process a buffer of single records in parallel
// // called by stream() when parallelize is requested
// fn process_record_buffer<I, O, F>(
//     wtr: &mut csv::Writer<std::io::Stdout>, 
//     input_records: &[I], 
//     record_parser: F
// ) -> Result<(), Box<dyn Error>>
// where
//     I: DeserializeOwned + Serialize,
//     O: Serialize,
//     F: Fn(&I) -> Option<Vec<O>>,
// {
//     // let output_records: Vec<O> = input_records
//     //     .par_iter()
//     //     .filter_map(record_parser) // record_parser must return None or Some(Vec<O>)
//     //     .flatten() // transform Some(Vec<O>) into Vec<O>
//     //     .collect();
//     // for output_record in output_records {
//     //     wtr.serialize(output_record)?;
//     // }
//     Ok(())
// }

// // private function to process a buffer of groups of records in parallel
// // called by group_by() when parallelize is requested
// fn process_group_buffer<I, O, F>(
//     wtr: &mut csv::Writer<std::io::Stdout>, 
//     input_record_groups: &[Vec<I>],
//     record_parser: F
// ) -> Result<(), Box<dyn Error>>
// where
//     I: DeserializeOwned + Serialize,
//     O: Serialize,
//     F: Fn(&[I]) -> Option<Vec<O>>,
// {
//     // let output_records: Vec<O> = input_record_groups
//     //     .par_iter()
//     //     .filter_map(record_parser) // record_parser must return None or Some(Vec<O>)
//     //     .flatten() // transform Some(Vec<O>) into Vec<O>
//     //     .collect();
//     // for output_record in output_records {
//     //     wtr.serialize(output_record)?;
//     // }
//     Ok(())
// }

// private function to process a single record
// called by stream() when parallelize is not requested
fn process_record<I, O, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record: &I, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    I: DeserializeOwned + Serialize,
    O: Serialize,
    F: Fn(&I) -> Option<Vec<O>>,
{
    if let Some(output_records) = record_parser(input_record) {
        for output_record in output_records {
            wtr.serialize(output_record)?;
        }
    }
    Ok(())
}

// private function to process a group of records in a batch
// called by group_by() when parallelize is not requested
fn process_group<I, O, F>(
    wtr: &mut csv::Writer<std::io::Stdout>,
    input_record_group: &[I],
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    I: DeserializeOwned + Serialize,
    O: Serialize,
    F: Fn(&[I]) -> Option<Vec<O>>,
{
    if let Some(output_records) = record_parser(input_record_group) {
        for output_record in output_records {
            wtr.serialize(output_record)?;
        }
    }
    Ok(())
}
