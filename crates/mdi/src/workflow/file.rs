//! Wrappers to help open and read/write to input/output files
//! identified by their environment variable keys or as file paths.
//! 
//! `Input/OutputFile` methods handle files as Vec<String<> and 
//! assume tab-delimited, headerless files. Extended methods allow 
//! headers and custom delimiters to be used.
//! 
//! `Input/OutputCsv` methods handle files as serialized records and 
//! assume tab-delimited files with headers. Extended methods allow 
//! custom delimiters and headerless files to be used.

// dependencies
use std::fs::{File, read_to_string};
use std::io::{Read, Write, BufReader};
use csv::{Reader, ReaderBuilder, Writer, WriterBuilder, StringRecord};
use flate2::{Compression, read::MultiGzDecoder, write::GzEncoder};
use rust_htslib::bgzf::Writer as BgzWriter;
use serde::{Serialize, de::DeserializeOwned};
use crate::workflow::Config;

/* --------------------------------------------------------------------
Input/OutputFile structs for files handled as Vec<String>
-------------------------------------------------------------------- */
/// An InputFile supports reading from flat files as strings.
pub struct InputFile {
    pub filepath: String,
    pub header:   Option<Vec<String>>,
    reader:       Reader<Box<dyn Read>>,
}
impl InputFile {
    /* ------------------------------------------------------------------
    reader opening
    ------------------------------------------------------------------ */
    /// Open a reader for an input file with full extended options support.
    pub fn open_file(filepath: &str, delimiter: u8, has_headers: bool) -> Self {
        let file = File::open(filepath).unwrap_or_else(|e| {
            panic!("failed to open file for reading {}: {}", filepath, e);
        });
        let buffered_file = BufReader::new(file);
        let reader: Box<dyn Read> = if filepath.ends_with(".gz") || filepath.ends_with(".bgz") {
            Box::new(MultiGzDecoder::new(buffered_file))
        } else {
            Box::new(buffered_file)
        };
        let mut reader: Reader<Box<dyn Read>> = ReaderBuilder::new()
            .has_headers(false) // false since we read the header ourselves below
            .delimiter(delimiter)
            .from_reader(reader);
        let header = if has_headers {
            let mut record = StringRecord::new();
            reader.read_record(&mut record).unwrap(); // grab header line
            Some(record.iter().map(|s| s.to_string()).collect())
        } else {
            None
        };
        Self { 
            filepath: filepath.to_string(),
            header, 
            reader
        }
    }
    /// Open a reader for a tab-delimited, headerless input file at a 
    /// filepath provided as a reference to an environment variable key.
    pub fn open_env(cfg: &mut Config, key: &str) -> Self {
        cfg.set_string_env(&[key]);
        Self::open_file(cfg.get_string(key), b'\t', false)
    }
    /// Open a reader for a tab-delimited, headerless input file at a 
    /// filepath provided as &str.
    pub fn open(filepath: &str) -> Self {
        Self::open_file(filepath, b'\t', false)
    }
    /* ------------------------------------------------------------------
    reading from file
    ------------------------------------------------------------------ */
    /// Return an iterator over the records in the input file.
    pub fn records(&mut self) -> csv::StringRecordsIter<'_, Box<dyn Read>> {
        self.reader.records()
    }
    /// Read the entire contents of an input file as a vector of strings,
    /// one per line. Appropriate for smaller files. The header line is
    /// ignored and not returned if `has_header` is true.
    pub fn get_lines(filepath: &str, has_header: bool) -> Vec<String> {
        let content = if filepath.ends_with(".gz") || filepath.ends_with(".bgz") {
            let file = File::open(filepath).expect(
                &format!("could not open {}: ", filepath)
            );
            let buffered_file = BufReader::new(file);
            let mut decoder = MultiGzDecoder::new(buffered_file);
            let mut content = String::new();
            decoder.read_to_string(&mut content).expect(
                &format!("could not read gzipped file {}: ", filepath)
            );
            content
        } else {
            read_to_string(filepath).expect(
                &format!("could not open {}: ", filepath)
            )
        };
        let lines = content.lines().map(|x| x.to_string()).collect::<Vec<String>>();
        if has_header { lines[1..].to_vec() } else { lines }
    }
}

/// An OutputFile supports writing to flat files as strings.
pub struct OutputFile {
    pub filepath: String,
    writer:       Writer<Box<dyn Write>>,
}
impl OutputFile {
    /* ------------------------------------------------------------------
    writer opening
    ------------------------------------------------------------------ */
    /// Open a writer for writing to a flat file as strings with full options definition.
    pub fn open_file(filepath: &str, delimiter: u8, header: Option<&[&str]>) -> Self {
        let file = File::create(filepath).unwrap_or_else(|e| {
            panic!("failed to create file for writing {}: {}", filepath, e);
        });
        let writer: Box<dyn Write> = if filepath.ends_with(".gz") {
            Box::new(GzEncoder::new(file, Compression::default()))
        } else {
            Box::new(file)
        };
        let mut writer = WriterBuilder::new()
            .has_headers(false) // false since we write the header ourselves below
            .delimiter(delimiter)
            .from_writer(writer);
        if let Some(header) = header {
            writer
                .write_record(header)
                .unwrap_or_else(|e| {
                    panic!("failed to write header to file {}: {}", filepath, e);
                });
        }
        Self { 
            filepath: filepath.to_string(),
            writer 
        }
    }
    /// Open a writer for a tab-delimited, headerless output file at a 
    /// filepath provided as a reference to an environment variable key.
    pub fn open_env(cfg: &mut Config, key: &str) -> Self {
        cfg.set_string_env(&[key]);
        Self::open_file(cfg.get_string(key), b'\t', None)
    }
    /// Open a writer for a tab-delimited, headerless output file at a 
    /// filepath provided as &str.
    pub fn open(filepath: &str) -> Self {
        Self::open_file(filepath, b'\t', None)
    }
    /* ------------------------------------------------------------------
    writing to file
    ------------------------------------------------------------------ */
    /// Write a serialized record to the output file.
    pub fn write_record(&mut self, record: Vec<&str>) {
        self.writer
            .write_record(record)
            .unwrap_or_else(|e| {
                panic!("failed to write record to file {}: {}", self.filepath, e);
            });
    }
    /// Flush the writer to ensure all data is written to the file and close it
    /// by taking ownership of and consuming the writer.
    pub fn close(mut self) {
        self.writer
            .flush()
            .unwrap_or_else(|e| {
                panic!("failed to flush output file {}: {}", self.filepath, e);
            });
    }
}

/* --------------------------------------------------------------------
Input/OutputCsv structs for files handled as (de)serialized records.
-------------------------------------------------------------------- */
/// An InputCsv supports reading deserialized records from CSV files.
pub struct InputCsv {
    pub filepath: String,
    reader:       Reader<Box<dyn Read>>,
}
impl InputCsv {
    /* ------------------------------------------------------------------
    reader opening
    ------------------------------------------------------------------ */
    /// Open a reader for an input file with full extended options support.
    pub fn open_file(filepath: &str, delimiter: u8, has_headers: bool) -> Self {
        let file = File::open(filepath).unwrap_or_else(|e| {
            panic!("failed to open file for reading {}: {}", filepath, e);
        });
        let buffered_file = BufReader::new(file);
        let reader: Box<dyn Read> = if filepath.ends_with(".gz") || filepath.ends_with(".bgz") {
            Box::new(MultiGzDecoder::new(buffered_file))
        } else {
            Box::new(buffered_file)
        };
        let reader = ReaderBuilder::new()
            .has_headers(has_headers) 
            .delimiter(delimiter)
            .from_reader(reader);
        Self { 
            filepath: filepath.to_string(),
            reader
        }
    }
    /// Open a reader for an input serialized CSV file at a 
    /// filepath provided as a reference to an environment variable key.
    /// Assumes tab-delimited file with headers.
    pub fn open_env(cfg: &mut Config, key: &str) -> Self {
        cfg.set_string_env(&[key]);
        Self::open_file(cfg.get_string(key), b'\t', true)
    }
    /// Open a reader for an input serialized CSV file at a 
    /// filepath provided as &str.
    /// Assumes tab-delimited file with headers.
    pub fn open(filepath: &str) -> Self {
        Self::open_file(filepath, b'\t', true)
    }
    /* ------------------------------------------------------------------
    reading from file
    ------------------------------------------------------------------ */
    /// Return an iterator over the records in the input file.
    pub fn deserialize<T: DeserializeOwned>(&mut self) -> csv::DeserializeRecordsIter<'_, Box<dyn Read>, T> {
        self.reader.deserialize::<T>()
    }
}

/// An OutputCsv supports writing serialized records to CSV files.
pub struct OutputCsv {
    pub filepath: String,
    writer:       Writer<Box<dyn Write>>,
}
impl OutputCsv {
    /* ------------------------------------------------------------------
    writer opening
    ------------------------------------------------------------------ */
    /// Open a CSV writer for an output file with full options definition.
    /// Supports gzip and bgzip compression based on file extension as well
    /// as uncompressed files.
    pub fn open_csv(filepath: &str, delimiter: u8, has_headers: bool) -> Self {
        let writer: Box<dyn Write> = if filepath.ends_with(".bgz") {
            Box::new(BgzWriter::from_path(filepath).unwrap_or_else(|e| {
                panic!("failed to create BGZ file for writing {}: {}", filepath, e);
            }))
        } else {
            let file = File::create(filepath).unwrap_or_else(|e| {
                panic!("failed to create file for writing {}: {}", filepath, e);
            });            
            if filepath.ends_with(".gz") {
                Box::new(GzEncoder::new(file, Compression::default()))
            } else {
                Box::new(file)
            }
        };
        let writer = WriterBuilder::new()
            .has_headers(has_headers)
            .delimiter(delimiter)
            .from_writer(writer);
        Self { 
            filepath: filepath.to_string(),
            writer 
        }
    }
    /// Open a CSV writer for an output tab-delimited file with headers at a 
    /// filepath provided as a reference to an environment variable key.
    /// Supports gzip and bgzip compression based on file extension as well
    /// as uncompressed files.
    pub fn open_env(cfg: &mut Config, key: &str) -> Self {
        cfg.set_string_env(&[key]);
        Self::open_csv(cfg.get_string(key), b'\t', true)
    }
    /// Open a CSV writer for an output tab-delimited file with headers at a 
    /// filepath provided as &str.
    /// Supports gzip and bgzip compression based on file extension as well
    /// as uncompressed files.
    pub fn open(filepath: &str) -> Self {
        Self::open_csv(filepath, b'\t', true)
    }
    /* ------------------------------------------------------------------
    writing to file
    ------------------------------------------------------------------ */
    /// Write a serialized record to a CSV output file.
    pub fn serialize<T: Serialize>(&mut self, record: &T) {
        self.writer
            .serialize(record)
            .unwrap_or_else(|e| {
                panic!("failed to serialize record to file {}: {}", self.filepath, e);
            });
    }
    /// Flush the writer to ensure all data is written to the file and close it
    /// by taking ownership of and consuming the writer.
    pub fn close(mut self) {
        self.writer
            .flush()
            .unwrap_or_else(|e| {
                panic!("failed to flush output file {}: {}", self.filepath, e);
            });
    }
    /// Write a slice of serialized records to a CSV output file 
    /// and close the file.
    pub fn serialize_all<T: Serialize>(mut self, records: &[T]) {
        for record in records { self.serialize(record); }
        self.close();
    }
}
