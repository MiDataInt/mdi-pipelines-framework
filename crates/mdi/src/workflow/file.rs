//! Wrappers to help open and read/write to input/output files
//! identified by their environment variable keys or as file paths.
//! 
//! Standard methods assume tab-delimited, headerless files, extended
//! methods allow headers and custom delimiters to be used.

// dependencies
use std::fs::{File, read_to_string};
use std::io::{Read, Write};
use csv::{Reader, ReaderBuilder, Writer, WriterBuilder, StringRecord};
use flate2::{Compression, read::GzDecoder, write::GzEncoder};
use crate::workflow::Config;

/// An InputFile supports reading from CSV files.
pub struct InputFile {
    pub filepath: String,
    pub header:   Option<Vec<String>>,
    reader:       Reader<Box<dyn Read>>,
}
impl InputFile {
    /* ------------------------------------------------------------------
    reader opening
    ------------------------------------------------------------------ */
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
    /// Open a reader for an input file with full extended options support.
    pub fn open_file(filepath: &str, delimiter: u8, has_headers: bool) -> Self {
        let file = File::open(filepath).unwrap_or_else(|e| {
            panic!("failed to open file for reading {}: {}", filepath, e);
        });
        let reader: Box<dyn Read> = if filepath.ends_with(".gz") {
            Box::new(GzDecoder::new(file))
        } else {
            Box::new(file)
        };
        let mut reader = ReaderBuilder::new()
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
    /* ------------------------------------------------------------------
    reading from file
    ------------------------------------------------------------------ */
    /// Return an iterator over the records in the input file.
    pub fn records(&mut self) -> csv::StringRecordsIter<'_, Box<dyn Read>> {
        self.reader.records()
    }
    /// Read the entire contents of an input file as a vector of strings,
    /// one per line. Appropriate for smaller files. Header lines are
    /// ignored and not returned if `header` is true.
    pub fn get_lines(file: &str, header: bool) -> Vec<String> {
        let content = if file.ends_with(".gz") {
            let file_handle = File::open(file).expect(
                &format!("could not open {}: ", file)
            );
            let mut decoder = GzDecoder::new(file_handle);
            let mut content = String::new();
            decoder.read_to_string(&mut content).expect(
                &format!("could not read gzipped file {}: ", file)
            );
            content
        } else {
            read_to_string(file).expect(
                &format!("could not open {}: ", file)
            )
        };
        let lines = content.lines().map(|x| x.to_string()).collect::<Vec<String>>();
        if header { lines[1..].to_vec() } else { lines }
    }
}


/// An InputFile supports reading from CSV files.
pub struct OutputFile {
    pub filepath: String,
    writer:       Writer<Box<dyn Write>>,
}
impl OutputFile {
    /* ------------------------------------------------------------------
    writer opening
    ------------------------------------------------------------------ */
    /// Open a writer for a tab-delimited, headerless input file at a 
    /// filepath provided as a reference to an environment variable key.
    pub fn open_env(cfg: &mut Config, key: &str) -> Self {
        cfg.set_string_env(&[key]);
        Self::open_file(cfg.get_string(key), b'\t', None)
    }
    /// Open a writer for a tab-delimited, headerless input file at a 
    /// filepath provided as &str.
    pub fn open(filepath: &str) -> Self {
        Self::open_file(filepath, b'\t', None)
    }
    /// Open a writer for an input file with full options definition.
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
    /// Flush the writer to ensure all data is written to the file and close it.
    pub fn close(&mut self) {
        self.writer
            .flush()
            .unwrap_or_else(|e| {
                panic!("failed to flush output file {}: {}", self.filepath, e);
            });
    }
}
