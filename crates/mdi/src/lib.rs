//! The mdi::RecordStreamer supports MDI pipelines by providing
//! a structure to manipulate tabular records in data streams.
//! Data are read from STDIN and written to STDOUT to function within a Unix stream.
//! This makes it easier to create executable crates that can be chained together,
//! with each crate performing a specific task in a data processing pipeline.
//!
//! Functions are written to be as fast as possible, without unnecessary copying
//! and with efficient allocation of vectors on the heap. Record parsing can often 
//! be done by reference, i.e., in place, unless records need to change structure.
//! 
//! # Usage Overview
//! Create a new RecordStreamer instance with default settings using
//! `mdi::RecordStreamer::new()`.
//!
//! Input records can be handled either:
//! - one record at a time using one of the `stream_xxx()` functions, or
//! - over multiple records in a keyed batch using one of the `group_by_xxx()` functions
//! 
//! Output records can be either:
//! - in-place modifications of input records using one of the `xxx_in_place()` functions, or
//! - entirely new records generated from input records using one of the `xxx_replace()` functions
//! In-place modification is fast but demands that the input and output record structures be the same 
//! and that there be a one-to-zero or one-to-one correspondence between input and output records.
//! New record generation to replace input records allows the input and output record structures differ 
//! and allows zero, one, or many output records to be generated from each input record.
//!  
//! Record/group parsing can be done either:
//! - serially using one of the xxx_serial() functions, or
//! - in parallel using one of the xxx_parallel() functions
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
//! # Record Parsing
//! Streaming is executed by calling on the RecordStreamer one of:
//! - `stream_in_place_serial(Fn(&mut T) -> Option<()>)`
//! - `stream_in_place_parallel(Fn(&mut T) -> Option<()>, n_cpu: usize, buffer_size: usize)`
//! - `stream_replace_serial(Fn(&I) -> Option<Vec<O>>)`
//! - `stream_replace_parallel(Fn(&I) -> Option<Vec<O>>, n_cpu: usize, buffer_size: usize)`
//! - `group_by_in_place_serial(Fn(&mut Vec<T>) -> Option<()>, grouping_field: &str)`
//! - `group_by_in_place_parallel(Fn(&mut Vec<T>) -> Option<()>, grouping_field: &str, n_cpu: usize, buffer_size: usize)`
//! - `group_by_replace_serial(Fn(&Vec<I>) -> Option<Vec<O>>, grouping_field: &str)`
//! - `group_by_replace_parallel(Fn(&Vec<I>) -> Option<Vec<O>>, grouping_field: &str, n_cpu: usize, buffer_size: usize)`
//! where the caller defines and provides:
//! - `Struct`s that define the input and output record structures
//! - a parsing function that processes the data, returning:
//!   - None if no record(s) should be written to the output stream for a (set of) input record(s), or
//!   - for in_place functions, Some(()) if the (updated) record(s) should be written to the output stream
//!   - for replace functions, Some(Vec<OutputRecord>) carrying the output record(s) resulting from the input record(s)
//!
//! The work to be done on input records is arbitrary and defined by the caller.
//! Some examples of work that can be done include:
//! - when using in_place or replace functions:
//!   - filtering records based on a condition
//!   - updating field(s) in a record
//! - when using replace functions only:
//!   - transforming records into distinct output records, e.g., adding a new field
//!   - aggregating records into a single output record
//!   - splitting records into multiple output records
//!
//! Note that the names of the record structures can be changes by the caller as needed.
//! 
//! # Additional Program Actions (side effects)
//! While the primary purpose of the RecordStreamer is to process records in a stream,
//! programs consuming the input data stream can also perform actions in addition 
//! to writing to the output stream, known as "side effects". Examples include:
//! - writing summary information to a log file
//! - creating a summary image or plot
//! - updating a database
//! If side effects are the only required actions, the caller can simply choose to never
//! write records to the output stream, always returning None from the record_parser.
//! 
//! # Examples
//! See the examples in the mdi/examples directory detailed information on how to use the RecordStreamer.

// dependencies
use std::error::Error;
use std::io::{self};
use rayon::prelude::*;
use serde::{de::DeserializeOwned, Serialize};

/// Initialize a record streamer.
pub struct RecordStreamer {
    has_headers: bool,
    delimiter:   u8,
    trim:        csv::Trim,
}
impl Default for RecordStreamer {
    fn default() -> RecordStreamer {
        RecordStreamer {
            has_headers: false,
            delimiter:   b'\t',
            trim:        csv::Trim::Fields,
        }
    }
}
impl RecordStreamer {

    /* ------------------------------------------------------------------
    public initialization methods
    ------------------------------------------------------------------ */
    /// Create a new RecordStreamer instance with default settings.
    pub fn new() -> RecordStreamer {
        RecordStreamer::default()
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

    /* ------------------------------------------------------------------
    public streaming methods
    ------------------------------------------------------------------ */
    /// `stream_in_place_serial()` processes input records from STDIN to STDOUT:
    /// - one at a time as they are encountered, without parallel processing
    /// - in place, i.e., only filtering or updating the input record structure
    pub fn stream_in_place_serial <T, F>(
        &self, 
        record_parser: F
    ) -> Result<(), Box<dyn Error>>
    where
        T: DeserializeOwned + Serialize,
        F: Fn(&mut T) -> Option<()>,
    {
        let me: &str = "mdi::RecordStreamer::stream_in_place_serial()";
        let (mut rdr, mut wtr) = init_io_streams(self, None);
        for (line_number, line) in rdr.deserialize().enumerate() {
            let mut input_record: T = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            if let Some(_) = record_parser(&mut input_record) {
                wtr.serialize(input_record)
                    .expect(&format!("{} failed while processing input record {}", me, line_number));
            }
        }
        flush_stream(&mut wtr, me)
    }

    /// `stream_in_place_parallel()` processes input records from STDIN to STDOUT:
    /// - one at a time as they are encountered, with parallel processing
    /// - in place, i.e., only filtering or updating the input record structure
    pub fn stream_in_place_parallel <T, F>(
        &self, 
        record_parser: F, 
        n_cpu: usize, 
        buffer_size: usize
    ) -> Result<(), Box<dyn Error>>
    where
        T: DeserializeOwned + Serialize + Send + Sync,
        F: Fn(&mut T) -> Option<()> + Send + Sync,
    {
        let me: &str = "mdi::RecordStreamer::stream_in_place_parallel()";
        let (mut rdr, mut wtr) = init_io_streams(self, Some(n_cpu));
        let mut input_record_buffer: Vec<T> = Vec::with_capacity(buffer_size);
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: T = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            input_record_buffer.push(input_record);
            if input_record_buffer.len() == buffer_size {
                do_stream_in_place_parallel(&mut wtr, &mut input_record_buffer, &record_parser)
                    .expect(&format!("{} failed while processing buffer near input record {}", me, line_number));
                input_record_buffer.clear();
            }
        }
        do_stream_in_place_parallel(&mut wtr, &mut input_record_buffer, &record_parser)
            .expect(&format!("{} failed while processing the last buffered chunk", me));
        flush_stream(&mut wtr, me)
    }

    /// `stream_replace_serial()` processes input records from STDIN to STDOUT:
    /// - one at a time as they are encountered, without parallel processing
    /// - where output records of arbitrary number and structure replace input records
    pub fn stream_replace_serial <I, O, F>(
        &self, 
        record_parser: F
    ) -> Result<(), Box<dyn Error>>
    where
        I: DeserializeOwned + Serialize,
        O: Serialize,
        F: Fn(&I) -> Option<Vec<O>>,
    {
        let me: &str = "mdi::RecordStreamer::stream_replace_serial()";
        let (mut rdr, mut wtr) = init_io_streams(self, None);
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: I = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            if let Some(output_records) = record_parser(&input_record) {
                for output_record in output_records {
                    wtr.serialize(output_record)
                        .expect(&format!("{} failed while processing input record {}", me, line_number));
                }
            }
        }
        flush_stream(&mut wtr, me)
    }

    /// `stream_replace_parallel()` processes input records from STDIN to STDOUT:
    /// - one at a time as they are encountered, with parallel processing
    /// - where output records of arbitrary number and structure replace input records
    pub fn stream_replace_parallel <I, O, F>(
        &self, 
        record_parser: F, 
        n_cpu: usize, 
        buffer_size: usize
    ) -> Result<(), Box<dyn Error>>
    where
        I: DeserializeOwned + Serialize + Send + Sync,
        O: Serialize + Send + Sync,
        F: Fn(&I) -> Option<Vec<O>> + Send + Sync,
    {
        let me: &str = "mdi::RecordStreamer::stream_replace_parallel()";
        let (mut rdr, mut wtr) = init_io_streams(self, Some(n_cpu));
        let mut input_record_buffer: Vec<I> = Vec::with_capacity(buffer_size);
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: I = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            input_record_buffer.push(input_record);
            if input_record_buffer.len() == buffer_size {
                do_stream_replace_parallel(&mut wtr, &input_record_buffer, &record_parser)
                    .expect(&format!("{} failed while processing buffer near input record {}", me, line_number));
                input_record_buffer.clear();
            }
        }
        do_stream_replace_parallel(&mut wtr, &input_record_buffer, &record_parser)
            .expect(&format!("{} failed while processing the last buffered chunk", me));
        flush_stream(&mut wtr, me)
    }

    /// `group_by_in_place_serial()` processes input records from STDIN to STDOUT:
    /// - in groups of records with the same sequential key
    /// - in place, i.e., only filtering or updating the input records (where #ouput = #input or 0)
    pub fn group_by_in_place_serial <T, F>(
        &self, 
        record_parser: F, 
        grouping_field: &str
    ) -> Result<(), Box<dyn Error>>
    where
        T: DeserializeOwned + Serialize,
        F: Fn(&mut Vec<T>) -> Option<()>,
    {
        let me: &str = "mdi::RecordStreamer::group_by_in_place_serial()";
        let (mut rdr, mut wtr) = init_io_streams(self, None);
        let mut input_record_group: Vec<T> = Vec::new();
        let mut previous_key: Option<String> = None;
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: T = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            let this_key = get_field_value(&input_record, grouping_field)
                .expect(&format!("{} failed to get group key from line {}", me, line_number));
            if previous_key.as_ref().map_or(false, |k| k != &this_key) {
                do_group_by_in_place_serial(&mut wtr, &mut input_record_group, &record_parser)
                    .expect(&format!("{} failed while processing group ending at line {}", me, line_number - 1));
                input_record_group.clear();
            }
            previous_key = Some(this_key);
            input_record_group.push(input_record);
        }
        do_group_by_in_place_serial(&mut wtr, &mut input_record_group, &record_parser)
            .expect(&format!("{} failed while processing the last group", me));
        flush_stream(&mut wtr, me)
    }

    /// `group_by_in_place_parallel()` processes input records from STDIN to STDOUT:
    /// - in groups of records with the same sequential key, with parallel processing
    /// - in place, i.e., only filtering or updating the input records (where #ouput = #input or 0)
    pub fn group_by_in_place_parallel <T, F>(
        &self, 
        record_parser: F, 
        grouping_field: &str, 
        n_cpu: usize, 
        buffer_size: usize
    ) -> Result<(), Box<dyn Error>>
    where
        T: DeserializeOwned + Serialize + Send + Sync,
        F: Fn(&mut Vec<T>) -> Option<()> + Send + Sync,
    {
        let me: &str = "mdi::RecordStreamer::group_by_in_place_parallel()";
        let (mut rdr, mut wtr) = init_io_streams(self, Some(n_cpu));
        let mut input_record_group_buffer: Vec<Vec<T>> = Vec::new();
        let mut input_record_group: Vec<T> = Vec::new();
        let mut previous_key: Option<String> = None;
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: T = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            let this_key = get_field_value(&input_record, grouping_field)
                .expect(&format!("{} failed to get group key from line {}", me, line_number));
            if previous_key.as_ref().map_or(false, |k| k != &this_key) {
                input_record_group_buffer.push(input_record_group);
                input_record_group = Vec::new(); // prevents move error with input_record_group.clear(); must reallocate
                if input_record_group_buffer.len() == buffer_size {
                    do_group_by_in_place_parallel(&mut wtr, &mut input_record_group_buffer, &record_parser)
                        .expect(&format!("{} failed while processing group buffer before input line {}", me, line_number));
                    input_record_group_buffer.clear();
                }
            }
            previous_key = Some(this_key);
            input_record_group.push(input_record);
        }
        input_record_group_buffer.push(input_record_group);
        do_group_by_in_place_parallel(&mut wtr, &mut input_record_group_buffer, &record_parser)
            .expect(&format!("{} failed while processing the last group", me));
        flush_stream(&mut wtr, me)
    }

    /// `group_by_replace_serial()` processes input records from STDIN to STDOUT:
    /// - in groups of records with the same sequential key, without parallel processing
    /// - where output records of arbitrary number and structure replace input records
    pub fn group_by_replace_serial <I, O, F>(
        &self, 
        record_parser: F, 
        grouping_field: &str
    ) -> Result<(), Box<dyn Error>>
    where
        I: DeserializeOwned + Serialize,
        O: Serialize,
        F: Fn(&Vec<I>) -> Option<Vec<O>>,
    {
        let me: &str = "mdi::RecordStreamer::group_by_replace_serial()";
        let (mut rdr, mut wtr) = init_io_streams(self, None);
        let mut input_record_group: Vec<I> = Vec::new();
        let mut previous_key: Option<String> = None;
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: I = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            let this_key = get_field_value(&input_record, grouping_field)
                .expect(&format!("{} failed to get group key from line {}", me, line_number));
            if previous_key.as_ref().map_or(false, |k| k != &this_key) {
                do_group_by_replace_serial(&mut wtr, &input_record_group, &record_parser)
                    .expect(&format!("{} failed while processing group ending at line {}", me, line_number - 1));
                input_record_group.clear();
            }
            previous_key = Some(this_key);
            input_record_group.push(input_record);
        }
        do_group_by_replace_serial(&mut wtr, &input_record_group, &record_parser)
            .expect(&format!("{} failed while processing the last group", me));
        flush_stream(&mut wtr, me)
    }

    /// `group_by_replace_parallel()` processes input records from STDIN to STDOUT:
    /// - in groups of records with the same sequential key, with parallel processing
    /// - where output records of arbitrary number and structure replace input records
    pub fn group_by_replace_parallel <I, O, F>(
        &self, 
        record_parser: F, 
        grouping_field: &str, 
        n_cpu: usize, 
        buffer_size: usize
    ) -> Result<(), Box<dyn Error>>
    where
        I: DeserializeOwned + Serialize + Send + Sync,
        O: Serialize + Send,
        F: Fn(&Vec<I>) -> Option<Vec<O>> + Send + Sync,
    {
        let me: &str = "mdi::RecordStreamer::group_by_replace_parallel()";
        let (mut rdr, mut wtr) = init_io_streams(self, Some(n_cpu));
        let mut input_record_group_buffer: Vec<Vec<I>> = Vec::new();
        let mut input_record_group: Vec<I> = Vec::new();
        let mut previous_key: Option<String> = None;
        for (line_number, line) in rdr.deserialize().enumerate() {
            let input_record: I = line
                .expect(&format!("{} failed while parsing input record {}", me, line_number));
            let this_key = get_field_value(&input_record, grouping_field)
                .expect(&format!("{} failed to get group key from line {}", me, line_number));
            if previous_key.as_ref().map_or(false, |k| k != &this_key) {
                input_record_group_buffer.push(input_record_group);
                input_record_group = Vec::new(); // prevents move error with input_record_group.clear(); must reallocate
                if input_record_group_buffer.len() == buffer_size {
                    do_group_by_replace_parallel(&mut wtr, &input_record_group_buffer, &record_parser)
                        .expect(&format!("{} failed while processing group buffer before input line {}", me, line_number));
                    input_record_group_buffer.clear();
                }
            }
            previous_key = Some(this_key);
            input_record_group.push(input_record);
        }
        input_record_group_buffer.push(input_record_group);
        do_group_by_replace_parallel(&mut wtr, &input_record_group_buffer, &record_parser)
            .expect(&format!("{} failed while processing the last group", me));
        flush_stream(&mut wtr, me)
    }
}

/*  ------------------------------------------------------------------
 shared stream and record functions
  ------------------------------------------------------------------ */
// return a paired stream reader and writer for STDIN and STDOUT
// by design, headers and delimiters are handled the same for both input and output streams
fn init_io_streams(rs: &RecordStreamer, n_cpu: Option<usize>) -> (
    csv::Reader<std::io::Stdin>, 
    csv::Writer<std::io::Stdout>
) {
    let rdr = csv::ReaderBuilder::new()
        .has_headers(rs.has_headers)
        .delimiter(rs.delimiter)
        .trim(rs.trim)
        .from_reader(io::stdin());
    let wtr = csv::WriterBuilder::new()
        .has_headers(rs.has_headers)
        .delimiter(rs.delimiter)
        .from_writer(io::stdout());
    if let Some(n_cpu) = n_cpu {
        rayon::ThreadPoolBuilder::new().num_threads(n_cpu).build_global()
            .expect("mdi::RecordStreamer failed to initialize parallel processing");
    }
    (rdr, wtr)
}

// get the value of the key field in a record
// returns an error if the named field is not found in the record structure
fn get_field_value<T: Serialize>(record: &T, grouping_field: &str) -> Result<String, Box<dyn Error>> {
    let value = serde_json::to_value(record)?;
    match value.get(grouping_field) {
        Some(v) => Ok(v.to_string().trim_matches('"').to_string()),
        None => Err(format!("Field '{}' not found in record", grouping_field).into())
    }
}

// finish streaming by flushing the output stream
fn flush_stream(wtr: &mut csv::Writer<std::io::Stdout>, caller: &str) -> Result<(), Box<dyn Error>> {
    wtr.flush().expect(&format!("{} failed while flushing last records in output stream", caller));
    Ok(())
}

/*  ------------------------------------------------------------------
 methods for parallel processing (names match the corresponding calling methods above)
  ------------------------------------------------------------------ */
fn do_stream_in_place_parallel<T, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record_buffer: &mut Vec<T>, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    T: DeserializeOwned + Serialize + Send + Sync,
    F: Fn(&mut T) -> Option<()> + Send + Sync,
{
    let keep: Vec<_> = input_record_buffer
        .into_par_iter()
        .map(record_parser)
        .collect();
    for i in 0..input_record_buffer.len() {
        if let Some(_) = keep[i] {
            wtr.serialize(&input_record_buffer[i])?;
        }
    }
    Ok(())
}

fn do_stream_replace_parallel<I, O, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record_buffer: &Vec<I>, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    I: DeserializeOwned + Serialize + Send + Sync,
    O: Serialize + Send,
    F: Fn(&I) -> Option<Vec<O>> + Send + Sync,
{
    let output_records: Vec<O> = input_record_buffer
        .par_iter()
        .filter_map(record_parser) // record_parser must return None or Some(Vec<O>)
        .flatten() // transform Some(Vec<O>) into Vec<O>
        .collect();
    for output_record in output_records {
        wtr.serialize(output_record)?;
    }
    Ok(())
}

fn do_group_by_in_place_serial<T, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record_group: &mut Vec<T>, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    T: DeserializeOwned + Serialize,
    F: Fn(&mut Vec<T>) -> Option<()>,
{
    if let Some(_) = record_parser(input_record_group) {
        for input_record in input_record_group {
            wtr.serialize(input_record)?;
        }
    }
    Ok(())
}

fn do_group_by_in_place_parallel<T, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record_group_buffer: &mut Vec<Vec<T>>, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    T: DeserializeOwned + Serialize + Send + Sync,
    F: Fn(&mut Vec<T>) -> Option<()> + Send + Sync,
{
    let keep: Vec<_> = input_record_group_buffer
        .into_par_iter()
        .map(record_parser)
        .collect();
    for i in 0..input_record_group_buffer.len() {
        if let Some(_) = keep[i] {
            for input_record in input_record_group_buffer[i].iter() {
                wtr.serialize(&input_record)?;
            }
        }
    }
    Ok(())
}

fn do_group_by_replace_serial<I, O, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record_group: &Vec<I>, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    I: DeserializeOwned + Serialize,
    O: Serialize,
    F: Fn(&Vec<I>) -> Option<Vec<O>>,
{
    if let Some(output_records) = record_parser(input_record_group) {
        for output_record in output_records {
            wtr.serialize(output_record)?;
        }
    }
    Ok(())
}

fn do_group_by_replace_parallel<I, O, F>(
    wtr: &mut csv::Writer<std::io::Stdout>, 
    input_record_group_buffer: &Vec<Vec<I>>, 
    record_parser: F
) -> Result<(), Box<dyn Error>>
where
    I: DeserializeOwned + Serialize + Send + Sync,
    O: Serialize + Send,
    F: Fn(&Vec<I>) -> Option<Vec<O>> + Send + Sync,
{
    let output_records: Vec<O> = input_record_group_buffer
        .par_iter()
        .filter_map(record_parser) // record_parser must return None or Some(Vec<O>)
        .flatten() // transform Some(Vec<O>) into Vec<O>
        .collect();
    for output_record in output_records {
        wtr.serialize(output_record)?;
    }
    Ok(())
}
