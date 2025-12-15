// modules
pub mod workflow;     // support for MDI-style workflows, environment variables, etc.
mod record_streamer;  // helpers for streaming data in Unix pipes
pub mod rlike;            // R-like data frames for tabular data manipulation

// re-exports
pub use record_streamer::RecordStreamer;
pub use rlike::data_frame;
pub use workflow::file::{InputFile, OutputFile};
