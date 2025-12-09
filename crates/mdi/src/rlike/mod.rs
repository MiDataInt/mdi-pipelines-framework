//! DataFrame and other types that combine expressive Rust-like statements 
//! with R-like data objects.
//! 
//! The `rlike` crate supports data analysis pipelines by providing fast, 
//! Rust-native data interfaces. The name `rlike` reflects an initial 
//! goal to provide a naming system reminiscent of R data objects, which 
//! is sometimes true as implemented, sometimes not. It grew to also
//! refer to the Rust-like statement syntax deployed by `rlike`.
//! 
//! The primary structure of interest in `rlike` is its `DataFrame`, a 
//! column-oriented data type for table-based data manipulations.
//! 
//! Other Rust packages, such as `polars` and `nalgebra`, provide 
//! overlapping functionality. You will want to compare them to determine 
//! which is best for your use case. Crates like `polars` have richer 
//! feature sets but `rlike` offers a concise and expressive Rust-like 
//! statement syntax for column definition, data updates, and queries 
//! via a powerful set of macros. This statement syntax allows for  
//! streamlined code with much less quoting and long method chains.
//! 
//! Differences aside, `rlike` adopts many of the same best practices
//! for efficient column-based data manipulation as `polars`, although 
//! without using the Apache Arrow format. Most notably, `rlike` encodes 
//! null/NA values using None elements in Rust Option<T> values. 

pub mod types;
pub mod data_frame; 

/* -----------------------------------------------------------------------------
exported macros
----------------------------------------------------------------------------- */
/// Create a vector of column filter operations for use with DataFrame::filter().
#[macro_export]
macro_rules! throw {
    ($($arg:tt)*) => {
        {
            eprintln!("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            eprintln!($($arg)*);
            eprintln!("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
            std::process::exit(1)
        }
    };
}
