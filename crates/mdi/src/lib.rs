// modules
pub mod workflow; // support for MDI-style workflows, environment variables, etc.
pub mod rlike;    // R-like data frames for tabular data manipulation
pub mod record;   // helpers for streaming data in Unix pipes

// re-exports
pub use workflow::file::{InputFile, OutputFile, InputCsv, OutputCsv};
pub use rlike::data_frame;
pub use record::streamer::RecordStreamer;
pub use record::fanner::RecordFanner;
