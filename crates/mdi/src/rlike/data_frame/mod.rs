//! `rlike::data_frame::DataFrame` offers a columnar data structure stored 
//! as HashMaps of named columns where data are stored as one vector per column. 
//! Different columns can have different enumerated RLike data types. Thus, columns 
//! take the form `HashMap<String, Column>`, where a Column is `Vec<RLike>`, e.g., 
//! `Vec<Option<i32>>`, etc.
//!
//! You are encouraged to use a series of powerful macros to create and manipulate
//! DataFrames, which offer an expressive statement syntax. However, many actions
//! can be accomplished using Rust-like method chaining, albeit with more verbose 
//! code and a greater need to understand the underlying data structures.
//! 
//! The following is an overview of DataFrame macros and methods. See their 
//! individual documentation for syntax and usage details, as well as the complete
//! data_frame*.rs examples in the 
//! [examples directory](https://github.com/wilsontelab/mdi-pipelines-framework/tree/main/crates/mdi/examples).
//! 
//! # Creating DataFrames anew
//! 
//! The `df_new!()` macro is used to create new DataFrame instance without using 
//! other DataFrames as input.
//! 
//! - `let mut df = df_new!();` = create a new empty DataFrame
//! - `let mut df = df_new!(statement, ...);` = create and fill a new DataFrame
//! 
//! The following are related methods used to create empty DataFrames 
//! with no Columns or with empty columns matching an existing DataFrame's schema.
//! 
//! - `let mut df = DataFrame::new();` = create an empty DataFrame with no rows or columns
//! - `let mut df = DataFrame::from_schema(&df);` = create an empty DataFrame matching another DataFrame's columns
//! 
//! # Filling a DataFrame from a file or stream
//! 
//! After establising an empty DataFrame with a column schema, you can fill it with
//! data read from a file or STDIN using the `df_read!()` macro, and write it again
//! with `df_write!()`.
//! 
//! - TODO
//! 
//! Alternatively, RLike offers a binary storage format for DataFrames, which loads
//! faster using the analogous `df_load!()` and `df_save!()` macros.
//! 
//! - TODO
//! 
//! # Extracting data from DataFrames
//! 
//! The following are the main DataFrame getter and setter macros when you know the
//! column name and/or integer row index.
//! 
//! - `let vals: Vec<Option<T>> = df_get!(&df, col [, ...]);` = get [and modify] data from col
//! 
//! These are the related getter and setter public methods.
//! 
//! - `let vals: Vec<Option<T>> = df.get(col)` = copy the data from col
//! - `let vals: &Vec<Option<T>> = df.get_ref(col)` = return a reference to the data in col
//! - `let vals: &mut Vec<Option<T>> = df.get_ref(col)` = return a mutable reference to the data in col
//! - `let val: String = df.cell_string(col, row_i)` = retrieve a single cell value from col as a String
//! - `let val: Option<T> = df.cell(col, row_i)` = retrieve a single cell value from col
//! - `df.set(col, row_i, val)` = update a single cell value in df by mutable reference
//! 
//! In addition, DataFrames support data retrieval keyed by the values of one to eight columns.
//! 
//! - 'let df = df_index!(df, col, ...)' = set an index on df using the named columns as keys
//! - 'let ds = df_get!(df, col = val, ...)' = get a DataFrameSlice of rows matching the key values
//! 
//! # Modifying DataFrames in place
//! 
//! The following macros add or update columns of a DataFrame instance in place, 
//! i.e., the df is permanently modified by mutable reference with only as much copying 
//! as needed to fill new rows or columns.
//! 
//! - `df_retain!(&mut df, col, ...)` = keep only named columns in df, in order; drop all others
//! - `df_drop!(&mut df, col, ...)` = remove one or more named columns from df; retain all other
//! - `df_set!(&mut df, statement; ...)` = add one or more columns or update existing column(s) by column-wise operations
//! 
//! The following are related chainable methods used to modify DataFrames in place.
//! 
//! - `df.add_col(col, data)` = add one new column to df
//! - `df.replace_or_add_col(col, data)` = add or replace one column in df
//! - `df.retain_cols(cols)` = remove all but the named columns from df
//! - `df.drop_col(col)` = remove one column from df
//! - 'df.reserve(additional)' = reserve space for additional rows to minimize reallocation
//! 
//! # Creating simple combinations of existing DataFrames
//! 
//! Two or more DataFrames can be combined in column-wise or row-wise fashion using 
//! functions with the R-like names `cbind` and `rbind`, respectively. Binding functions 
//! (like queries below) always return a new DataFrame.
//! 
//! The simplest named macros consume all input DataFrames. Use the same input and output
//! variable names to replace one of the input DataFrames with the result.
//! 
//! - `let mut df1 = df_cbind!(df1, df2, ...)` = consume and combine two or more DataFrames by column
//! - `let mut df3 = df_rbind!(df1, df2, ...)` = consume and combine two or more DataFrames by row
//! 
//! The following are equivalent methods for consuming and binding just two DataFrames.
//! 
//! - `let mut df1 = df1.cbind(df2)` = consume and combine two DataFrames by column
//! - `let mut df3 = df1.rbind(df2)` = consume and combine two DataFrames by row
//! 
//! Use the equivalent macros and methods with a `_ref` suffix to combine two or more 
//! DataFrames by reference without consuming them. Especially for `cbind_ref()`, this
//! requires more allocation and copying so is slower than the non-ref version (due to the
//! column-wise data model, even `rbind()` requires copying from df2 to df1, whereas
//! `cbind()` allows the output DataFrame to simply take ownership of df2 columns).
//! 
//! - `let mut df1 = df_cbind_ref!(&df1, &df2, ...)` = copy and combine two or more DataFrames by column
//! - `let mut df3 = df_rbind_ref!(&df1, &df2, ...)` = copy and combine two or more DataFrames by row
//! - `let mut df1 = df1.cbind_ref(&df2)` = copy and combine two DataFrames by column
//! - `let mut df3 = df1.rbind_ref(&df2)` = copy and combine two DataFrames by row
//! 
//! The bind macros enforce data integrity by ensuring a compatible number of rows
//! for `cbind()` and a matching column schema for `rbind()`, noting that `cbind()`
//! will recycle empty and single-row DataFrames as needed to match another DataFrame.
//! 
//! # Queries that act on a single DataFrame
//! 
//! The `df_query!()` macro supports queries on a single DataFrame in SQL-like patterns 
//! enumerated below. Queries return a newly allocated DataFrame, copying data from the 
//! input DataFrame by reference as needed, i.e., input DataFrames are neither altered
//! nor consumed. If you want the query to replace the input DataFrame, simply use the 
//! same variable name. Query actions can be chained together within a single call 
//! to `df_query!()` as illustrated in examples below.
//! 
//! ## Query Actions
//! 
//! Queries are constructed by a series of sequential calls to query 'actions'.
//! 
//! The first non-exclusive actions collect and pre-calculate parameters needed for query execution:
//! 
//! - `filter(statement; ...)` = calculate one or more row filters prior to query execution
//! - `sort()` or `sort(col, ...)` = sort the output by one or more columns
//! - `group(statement)` = list the grouping and aggregation column(s), in formula syntax
//! 
//! The last exclusive actions trigger query execution toward different goals and output types.
//! They return a new DataFrame (or Vec<T> in the case of `do::<T>()`).
//! 
//! - `select()` or `select(col, ...)` = list columns to include in the output; execute query
//! - `drop(col, ...)` = list columns to omit from the output; execute query
//! - `aggregate(statement; ...)` = calculate zero to many group aggregates as one value per group
//! - `do(op)` = execute a custom operation on grouped data to return a new DataFrame by `rbind`ing groups
//! - `do::<T>(op)` = execute a custom operation on grouped data to return a new Vec<T> by `flatten`ing groups
//! - `pivot(statement)` = define a formula and fill operation for long-to-wide reshaping via column pivot
//! 
//! One additional action is not a querying action per se, but provides a way to call `df_set!()` inline 
//! between two chained queries, e.g., allowing compound queries that filter data prior to calculating new 
//! columns and returning them.
//! 
//! - `set(statement; ...)` = create or update (filtered) columns prior to next query execution
//! 
//! A few intuitive guides helps to remember the supported order and combinations of query actions:
//! 
//! - when needed, `filter()` comes first to reduce the number of rows that must be sorted, etc.
//! - when needed, `sort()` dictates that the output will be sorted by columns specified in either 
//!   `sort()` itself or other actions; if not sorted, the row order of the input DataFrame is preserved
//! - `group()` and `pivot()` actions specify grouping columns in formula syntax
//! - `select()`, `drop()`, `aggregate()`, `do()`, `do::<T>()`, and `pivot()` actions trigger
//!   query execution so are mutually exclusive and always last in a query sequence
//! - `set()` is not a querying action per se and is only used as a shortcut to `df_set!()` within query chains
//! 
//! See the `df_query!()` macro documentation for details on statement syntax 
//! and closure arguments for various actions.
//! 
//! ## Query macro synonyms
//! 
//! A few query execution actions have synonyms that can simplify code when no other 
//! prepratory actions are needed. Grouping queries always require multiple actions, so do
//! not have synonyms.
//! 
//! - `df_select!(&df, col, ...)` is a synonym for `df_query!(&df, select(col, ...))`
//! - `df_pivot!(&df, statement)` is a synonym for `df_query!(&df, pivot(statement))`
//! 
//! ## Select/Drop Queries
//! 
//! The  `select()` and `drop()` actions trigger SQL-like Select query execution without data grouping.
//! 
//! ```
//! // copy all rows and all columns
//! let df_qry = df_query!(&df, select());
//! let df_qry = df_select!(&df);
//! 
//! // copy all rows of specified columns
//! let df_qry = df_query!(&df, select(col, ...));
//! let df_qry = df_select!(&df, col, ...);
//! 
//! // copy filtered rows of all columns
//! let df_qry = df_query!(&df, filter(...), select());
//! 
//! // copy filtered rows of specified columns
//! let df_qry = df_query!(&df, filter(...), select(col, ...));
//! 
//! // add output sorting to the above patterns to yield a complete Filter/Sort/Select (FSS) pattern
//! let df_qry = df_query!(&df, filter(...), sort(col, ...), select(col, ...));
//! // etc.
//! 
//! // specify the columns to omit from the output, rather than the columns to include
//! let df_qry = df_query!(&df, filter(...), sort(col, ...), drop(col, ...));
//! // etc.
//! 
//! // run multiple sequential queries by chaining them in a single call to df_query!()
//! let df_qry = df_query!(
//!     &df,
//!     filter(...), select(col, ...), // pass a temporary df from first query to subsequent actions
//!     set(...), // perform complex column-wise operations on only the filtered data rows
//!     sort(), group(...), aggregate(...) // do something with the new columns in a second query
//! );
//! ```
//! 
//! ## Group and Aggregate Queries
//! 
//! The `group()` action specifies that query operations are performed on keyed
//! groups of the input data rows. The first and simplest pattern calculates
//! one or more column aggregates for each group.
//! 
//! ```
//! // group and aggregate over all rows; report groups in the order they are encountered in df
//! let df_agg = df_query!(&df, group(...), aggregate(...));
//! 
//! // filter rows before aggregating (only illustrated once, available for all grouping queries)
//! let df_agg = df_query!(&df, filter(...), group(...), aggregate(...));
//! 
//! // report groups sorted by `group()` key columns; sorting is triggered by the empty `sort()`
//! let df_agg = df_query!(&df, sort(), group(...), aggregate(...));
//! 
//! // report groups sorted by `sort(...)` columns; `sort(...)` column list may be longer than `group(...)` keys
//! let df_agg = df_query!(&df, sort(col, ...), group(...), aggregate(...));
//! ```
//! 
//! ## Group and Do Queries
//! 
//! More complex grouped outputs can be generated using Do queries, which apply
//! a user-defined closure operation to each group of rows, resulting in an ouput 
//! DataFrame or Vec<T> constructed by `rbind` and `flatten`, respectively.
//! 
//! ```
//! // group and do over all rows; generate a DataFrame; report groups in the order encountered in df
//! let df_agg = df_query!(&df, group(...), do(op));
//! 
//! // group and do over all rows; generate a Vec<T>; report groups in the order encountered in df
//! let df_agg = df_query!(&df, group(...), do<T>(op));
//! 
//! // add filtering and sorting to the above patterns as needed (the same as for Aggregate queries)
//! let df_agg = df_query!(&df, filter(...), sort(), group(...), do(op));
//! // etc.
//! ```
//! 
//! ## Pivot Queries
//! 
//! Pivot queries are a special case of grouping queries that reshape long data into wide data.
//! The net effect is similar to Group and Aggregate queries, but the aggregated output columns
//! are determined by category values in a pivot column. 
//! 
//! ```
//! // perform a long-to-wide pivot on all rows; report groups in the order encountered in df
//! let df_pvt = df_query!(&df, pivot(...));
//! let df_pvt = df_pivot!(&df, ...);
//! 
//! // perform a long-to-wide pivot on all rows; report groups sorted by the `pivot(...)` key columns
//! let df_pvt = df_query!(&df, sort(), pivot(...));
//! 
//! // filter rows before pivoting
//! let df_pvt = df_query!(&df, filter(...), pivot(...));
//! let df_pvt = df_query!(&df, filter(...), sort(), pivot(...));
//! 
//! // select after pivot by query chaining; will fail if select() columns are missing from pivot categories
//! let df_pvt = df_query!(&df, pivot(...), select(col, ...));
//! ```
//! 
//! # Joining/merging two DataFrames on key columns
//! 
//! Whereas queries take a single DataFrame as input, the `df_join!()` macro 
//! performs SQL-like join (R-like merge) operations on two or more DataFrames using
//! a partially shared statement syntax.
//! 
//! The following preparative actions operate the same as for single DataFrame queries:
//! 
//! - `filter(...)` = calculate one or more row filters prior to executing the join
//! - `sort()` = report results sorted by the join key columns (only empty sort() allowed for joins)
//! 
//! The following actions trigger execution of their respective join types 
//! (note that right joins are rarely needed and not supported):
//! 
//! - `inner(...)` = inner join, i.e., only return rows with matching key values
//! - `left(...)`  = left join,  i.e., return all rows from df1 and matching rows from df2
//! - `outer(...)` = outer join, i.e., return all rows from both DataFrames
//! 
//! As with queries, the following macros are simplifying synonyms for `df_join!()`
//! when no preparative actions are needed prior to inner, left, or outer joins
//! of exactly two DataFrames. Note the difference that `df_inner!()` and `df_left!()`
//! yield unsorted output, whereas `df_outer!()` yields sorted output.
//! 
//! - `df_inner!(&df1, &df2, ...)` is a synonym for `df_join!(&df1, &df2, inner(...))`
//! - `df_left!(&df1, &df2, ...)`  is a synonym for `df_join!(&df1, &df2, left(...))`
//! - `df_outer!(&df1, &df2, ...)` is a synonym for `df_join!(&df1, &df2, sort(), outer(...))`
//! 
//! See the `df_join!()` macro documentation for details on join statement syntax.
//! 
//! ```
//! // unfiltered, unsorted joins of two DataFrames by the hash join method
//! let df_join = df_join!(&df1, &df2, inner(...));
//! let df_join = df_join!(&df1, &df2, left(...));
//! let df_join = df_inner!(&df1, &df2, ...);
//! let df_join = df_left!(&df1, &df2, ...);
//! 
//! // unfiltered, sorted joins of two DataFrames by the merge-sort join method
//! let df_join = df_join!(&df1, &df2, sort(), inner(...));
//! let df_join = df_join!(&df1, &df2, sort(), left(...));
//! let df_join = df_join!(&df1, &df2, sort(), outer(...));
//! let df_join = df_outer!(&df1, &df2, ...);
//! 
//! // add pre-join filtering to joins
//! let df_join = df_join!(&df1, &df2, filter(...), inner(...));
//! let df_join = df_join!(&df1, &df2, filter(...), sort(), inner(...));
//! // etc.
//! 
//! // join multiple DataFrames in a left-associative series
//! let df_join = df_join!(&df1, &df2, &df3, ..., inner(...));
//! // etc.
//! 
//! // apply join to temporary DataFrames calculated on the fly
//! let df_join = df_join!(
//!     &df_query!(&df1, filter(...), select(col, ...)),
//!     &df_query!(&df2, filter(...), select(col, ...)),
//!     inner(...)
//! );
//! ```

// modules
pub mod column;
pub mod macros;
pub mod display;
pub mod bind;
pub mod query;
pub mod key;
pub mod join;
pub mod slice;
pub mod index;
pub mod r#trait;
pub mod prelude;

// dependencies
use std::io::{Read, BufReader};
use std::collections::HashMap;
use csv::{StringRecord, ReaderBuilder, Trim};
use rayon::prelude::*;
use crate::rlike::types::Do;
use column::{Column, get::{ColVec, ColCell}};
use query::{QueryStatus, Query};
use slice::DataFrameSlice;
use index::RowIndex;
use r#trait::DataFrameTrait;
use crate::throw;

/* -----------------------------------------------------------------------------
DataFrame structure definition; metadata and a set of named Column instances.
----------------------------------------------------------------------------- */
/// A DataFrame is a columnar data structure stored as a HashMap of named Columns.
pub struct DataFrame {
    n_row:         usize,
    n_col:         usize,
    columns:       HashMap<String, Column>,
    col_names:     Vec<String>,
    col_types:     HashMap<String, String>,
    pub status:    QueryStatus,
    pub row_index: RowIndex,
    pub print_max_rows:      usize,
    pub print_max_col_width: usize,
}
impl DataFrame {
    /* -----------------------------------------------------------------------------
    DataFrame constructors and destructors
    ----------------------------------------------------------------------------- */
    /// Create a new, empty DataFrame, to which you subsequently add Columns.
    pub fn new() -> Self {
        Self {
            n_row:      0,
            n_col:      0,
            columns:    HashMap::new(),
            col_names:  Vec::new(),
            col_types:  HashMap::new(),
            status:     QueryStatus::new(),
            row_index:  RowIndex::new(),
            print_max_rows:      20,
            print_max_col_width: 25,
        }
    }
    /// Create a new, empty data frame with the same schema as an existing one.
    pub fn from_schema(df_src: &DataFrame) -> Self {
        let mut df_dst = DataFrame::new();
        df_src.col_names.iter().for_each(|col_name| {
            let col_type = df_src.col_types[col_name].clone();
            Column::add_empty_col(&mut df_dst, col_name, &col_type)
        });
        df_dst
    }
    /// Create a new data frame from one or more rows of an existing DataFrame,
    /// i.e., take a potentially non-contiguous slice of the rows of a DataFrame
    /// by copying values from cells.
    pub fn from_rows(&self, row_i: Vec<usize>) -> Self {
        let mut df_dst = DataFrame::new();
        self.col_names.iter().for_each(|col_name| {
            Column::copy_col_rows(self, &mut df_dst, col_name, &row_i);
        });
        df_dst
    }
    /// Reserve capacity for at least additional more rows to be inserted in a DataFrame. 
    /// 
    /// Calling `df.reserve(usize)` can limit copying and improve performance when you anticipate 
    /// adding many rows to a DataFrame, e.g., through iterative `rbind` operations.
    pub fn reserve(&mut self, additional: usize) {
        for (_, col) in &mut self.columns {
            col.reserve(additional);
        }
    }
    /// Add a new Column to a DataFrame. 
    /// 
    /// Columns are passed in as Vec<RL>, i.e., Vec<Option<T>>, to be owned by the DataFrame.
    /// 
    /// If any existing columns or the new column have zero or one rows, they are recycled 
    /// to the length of the other column(s) using None or the single Option<T> value, respectively. 
    /// Otherwise, the number of rows in the new column must match the number of rows in the 
    /// DataFrame, unless it is currently empty. 
    /// 
    /// All new columns must be named differently than any existing columns to prevent collisions.
    pub fn add_col<T: 'static + Clone>(&mut self, col_name: &str, mut col_data: Vec<Option<T>>) -> &mut Self 
    where Vec<Option<T>>: ColVec {
        let n_row_col = col_data.len();
        if self.is_empty() { // incoming column is the first column
            self.n_row = n_row_col;
        } else if self.n_row == 0 && n_row_col > 0 || // adding to a DataFrame with columns but no rows, recycle None as needed
                  self.n_row == 1 && n_row_col > 1 {  // adding to a DataFrame one row, recycle df column Option<T> as needed
            for col in self.columns.values_mut() {
                col.recycle(self.n_row, n_row_col);
            }
            self.n_row = n_row_col;
        } else if n_row_col == 0 && self.n_row > 0 || // adding empty column to a DataFrame with row data, recycle None
                  n_row_col == 1 && self.n_row > 1 {  // adding single-row column to a DataFrame with multiple rows, recycle incoming Option<T>
            col_data.resize(self.n_row, if n_row_col == 0 { None } else { col_data[0].clone() } );
        } else { // both DataFrame and incoming column have multiple rows, which must match exactly (multiples recycling not supported)
            Column::check_n_row_equality(self.n_row, n_row_col, "add_col");
        }
        let (col_type, col) = col_data.to_col();
        self.add_col_col(col_name, col_type.to_string(), col)
    }
    // internal function to add a column from a pre-assembled, pre-checked Column
    fn add_col_col(&mut self, col_name: &str, col_type: String, col: Column) -> &mut Self{
        self.columns.insert(col_name.to_string(), col);
        self.col_names.push(col_name.to_string()); // keep track of column creation order
        self.col_types.insert(col_name.to_string(), col_type);
        self.n_col += 1;
        self
    }
    /// Like DataFrame::add_col, but replace an existing column if it exists without error or warning.
    pub fn replace_or_add_col<T: 'static + Clone>(&mut self, col_name: &str, col_data: Vec<Option<T>>) 
    where Vec<Option<T>>: ColVec {
        if self.columns.contains_key(col_name) {
            let col_names_curr = self.col_names.clone();
            let is_factor = self.col_types[col_name] == "u16";
            let col_labels = if is_factor { self.get_labels(col_name) } else { Vec::new() };
            self.drop_col(col_name);
            self.add_col(col_name, col_data); // updates col_types appropriately
            if is_factor { self.set_labels(col_name, col_labels.iter().map(|x| x.as_str()).collect()); }
            self.col_names = col_names_curr; // thus, retain column order
        } else {
            self.add_col(col_name, col_data);
        }
    }
    /// Remove a Column from a DataFrame based on the column name.
    pub fn drop_col(&mut self, col_name: &str) -> &mut Self {
        if let Some(_col) = self.columns.remove(col_name) {
            self.col_names.retain(|name| name != col_name);
            self.col_types.remove(col_name);
            self.n_col -= 1;
        } else {
            throw!("DataFrame::drop_col error: column {col_name} not found.");
        }
        self
    }
    /// Keep only the columns in a DataFrame that are listed in argument `retain_col_names`.
    pub fn retain_cols(&mut self, retain_col_names: Vec<String>) -> &mut Self {
        for col_name in &retain_col_names {
            if !self.col_names.contains(col_name) {
                throw!("DataFrame::retain_cols error: column {col_name} not found.");
            }
        }
        for col_name in &self.col_names {
            if !retain_col_names.contains(col_name) {
                self.columns.remove(col_name);
                self.col_types.remove(col_name);
            }
        }
        self.n_col = retain_col_names.len();
        self.col_names = retain_col_names;
        self
    }
    /* -----------------------------------------------------------------------------
    DataFrame bulk data read from file or STDIN
    ----------------------------------------------------------------------------- */
    /// Fill or extend a data frame from a buffered reader.
    pub fn read<R: Read>(
        &mut self, 
        reader:   BufReader<R>, 
        header:   bool,
        sep:      u8,
        capacity: usize
    ) -> &mut Self {

        // accept multiple types of readers from df_read! macro
        let mut rdr = ReaderBuilder::new()
            .has_headers(header)
            .delimiter(sep)
            .trim(Trim::All)
            .from_reader(reader); 

        // pre-allocate a buffer of StringRecords to hold the input data
        let mut records: Vec<StringRecord> = (0..capacity).map(|_| StringRecord::new()).collect();

        // read records from the input stream and process them in buffered chunks
        let mut load_i: usize = 0;
        loop {
            match rdr.read_record(&mut records[load_i]) {
                Ok(true) => {
                    load_i += 1;
                    if load_i == capacity {
                        self.process_records(&records[0..load_i]);
                        load_i = 0;
                    }
                }
                Ok(false) => break, // End of file
                Err(e) => throw!("DataFrame::read error: {}", e),
            }
        }

        // finish the last buffer chunk as needed
        if load_i > 0 {
            self.process_records(&records[0..load_i]);
        }
        self
    }
    // Fill or extend a data frame from one buffer of StringRecord, in parallel by column.
    fn process_records(&mut self, records: &[StringRecord]) {
        self.columns.par_iter_mut().for_each(|(col_name, col)| {
            let j = self.col_names.iter().position(|name| name == col_name).unwrap();
            let str_refs: Vec<&str> = records.iter().map(|record| {
                match record.get(j) {
                    Some(str_ref) => str_ref,
                    _ => throw!("DataFrame::read error: column {col_name} not found in input stream.")
                }
            }).collect();
            col.deserialize(str_refs);
        });
        self.n_row += records.len();
    }
    /* -----------------------------------------------------------------------------
    DataFrame special column type support
    ----------------------------------------------------------------------------- */
    /// Establish pre-defined factor labels for an RFactor column.
    pub fn set_labels(&mut self, col_name: &str, labels: Vec<&str>) -> &mut Self {
        if self.col_types[col_name] != "u16" {
            throw!("DataFrame::set_labels error: column {col_name} is not type RFactor/u16.");
        }
        if let Some(col) = self.columns.get_mut(col_name) {
            col.set_labels(labels);
        } else {
            throw!("DataFrame::set_labels error: column {col_name} not found.");
        }
        self
    }
    /// Transfer factor labels for an RFactor column from df_src to self.
    pub fn copy_labels(&mut self, df_src: &Self, col_name: &str) {
        self.set_labels(
            col_name, 
            df_src.get_labels(col_name).iter().map(|s| s.as_str()).collect()
        );
    }
    /// Return the ordered factor labels for an RFactor column.
    pub fn get_labels(&self, col_name: &str) -> Vec<String> {
        if let Some(col) = self.columns.get(col_name) {
            col.get_labels()
        } else {
            throw!("DataFrame::get_labels error: column {col_name} not found.");
        }
    }
    /// Return the factor levels for an RFactor column as a column HashMap.
    pub fn get_levels(&self, col_name: &str) -> HashMap<String, u16> {
        if let Some(col) = self.columns.get(col_name) {
            col.get_levels()
        } else {
            throw!("DataFrame::get_levels error: column {col_name} not found.");
        }
    }
    /* -----------------------------------------------------------------------------
    DataFrame slices as collections of contiguous, read-only Column slices, i.e., a DataFrameSlice
    ----------------------------------------------------------------------------- */
    pub fn slice(&self, start_row_i: usize, n_row: usize) -> DataFrameSlice {
        DataFrameSlice::new(self, start_row_i, n_row)
    }
    /* -----------------------------------------------------------------------------
    DataFrame column-level getters
    ----------------------------------------------------------------------------- */
    // Ensure that a named Column exists in a DataFrame, and if so, return it.
    // These are internal functions; don't expect users to need to access Column objects.
    fn get_column<'a>(&'a self, col_name: &str, caller: &str) -> &'a Column {
        if let Some(col) = self.columns.get(col_name) {
            col
        } else {
            throw!("DataFrame::{caller} error: column {col_name} not found.")
        }
    }
    fn get_column_mut<'a>(&'a mut self, col_name: &str, caller: &str) -> &'a mut Column {
        if let Some(col) = self.columns.get_mut(col_name) {
            col
        } else {
            throw!("DataFrame::{caller} error: column {col_name} not found.")
        }
    }
    /// Return a mutable reference to the Vec<Option<T>> held in a DataFrame Column by column name.
    pub fn get_ref_mut<'a, T>(&'a mut self, col_name: &str) -> &'a mut Vec<Option<T>> 
    where Vec<Option<T>>: ColVec {
        let col = self.get_column_mut(col_name, "get_col_data_mut");
        col.get_ref_mut(col_name)
    }
    /* -----------------------------------------------------------------------------
    DataFrame column-level setters for `set` actions
    ----------------------------------------------------------------------------- */
    /// Create or update a column from Vec<T> as input (i.e. from zero current columns).
    pub fn set_col_0<
        O: Clone + 'static,
    >(
        &mut self, qry: &Query,
        out_name: &str,
        mut out_col_data: Vec<Option<O>>
    ) where Vec<Option<O>>: ColVec {
        if qry.has_been_filtered {
            let row_defaults = self.get_set_row_defaults(qry, out_name);
            qry.kept_rows.iter().enumerate().for_each(|(i, matches_filter)| {
                if !*matches_filter { out_col_data[i] = row_defaults[i].clone() }
            });
        }
        self.replace_or_add_col(out_name, out_col_data);
    }
    /// Create or update a column from a single column as input.
    pub fn set_col_1<A, O>(
        &mut self, qry: &Query, 
        a_name: &str, out_name: &str,
        na_val: Option<O>, op: impl Fn(&A) -> O + Send + Sync
    ) where 
        A: Copy + Send + Sync,
        O: Copy + Send + Sync + 'static,
        Vec<Option<A>>: ColVec,
        Vec<Option<O>>: ColVec 
    {
        let row_defaults: Vec<Option<O>> = self.get_set_row_defaults(qry, out_name); 
        let out_col_data: Vec<Option<O>> = self.get_ref(a_name)
            .par_iter()
            .enumerate()
            .map(|(i, opt_a)| {
                if qry.has_been_filtered && !qry.kept_rows[i] {
                    row_defaults[i].clone()
                } else {
                    match opt_a { 
                        Some(a) => Some(op(a)), 
                        _ => na_val
                    }
                }
            })
            .collect();
        self.replace_or_add_col(out_name, out_col_data);
    }
    /// Create or update a column from two columns as input.
    pub fn set_col_2<A, B, O>(
        &mut self, qry: &Query, 
        a_name: &str, b_name: &str, out_name: &str,
        na_val: Option<O>, op: impl Fn(&A, &B) -> O + Send + Sync
    ) where 
        A: Copy + Send + Sync,
        B: Copy + Send + Sync,
        O: Copy + Send + Sync + 'static,
        Vec<Option<A>>: ColVec,
        Vec<Option<B>>: ColVec,
        Vec<Option<O>>: ColVec 
    {
        let row_defaults: Vec<Option<O>> = self.get_set_row_defaults(qry, out_name); 
        let out_col_data: Vec<Option<O>> = self.get_ref(a_name)
            .par_iter()
            .zip( self.get_ref(b_name).par_iter() )
            .enumerate()
            .map(|(i, (opt_a, opt_b))| {
                if qry.has_been_filtered && !qry.kept_rows[i] {
                    row_defaults[i].clone()
                } else {
                    match (opt_a, opt_b) {
                        (Some(a), Some(b)) => Some(op(a, b)),
                        _ => na_val
                    }
                }
            })
            .collect();
        self.replace_or_add_col(out_name, out_col_data);
    }
    /// Create or update a column from three columns as input.
    pub fn set_col_3<A, B, C, O>(
        &mut self, qry: &Query, 
        a_name: &str, b_name: &str, c_name: &str, out_name: &str,
        na_val: Option<O>, op: impl Fn(&A, &B, &C) -> O + Send + Sync
    ) where 
        A: Copy + Send + Sync,
        B: Copy + Send + Sync,
        C: Copy + Send + Sync,
        O: Copy + Send + Sync + 'static,
        Vec<Option<A>>: ColVec,
        Vec<Option<B>>: ColVec,
        Vec<Option<C>>: ColVec,
        Vec<Option<O>>: ColVec 
    {
        let row_defaults: Vec<Option<O>> = self.get_set_row_defaults(qry, out_name); 
        let out_col_data: Vec<Option<O>> = self.get_ref(a_name)
            .par_iter()
            .zip( self.get_ref(b_name).par_iter() )
            .zip( self.get_ref(c_name).par_iter() )
            .enumerate()
            .map(|(i, ((opt_a, opt_b), opt_c))| {
                if qry.has_been_filtered && !qry.kept_rows[i] {
                    row_defaults[i].clone()
                } else {
                    match (opt_a, opt_b, opt_c) {
                        (Some(a), Some(b), Some(c)) => Some(op(a, b, c)),
                        _ => na_val
                    }
                }
            })
            .collect();
        self.replace_or_add_col(out_name, out_col_data);
    }
    /// Create or update a column from four columns as input.
    pub fn set_col_4<A, B, C, D, O>(
        &mut self, qry: &Query, 
        a_name: &str, b_name: &str, c_name: &str, d_name: &str, out_name: &str,
        na_val: Option<O>, op: impl Fn(&A, &B, &C, &D) -> O + Send + Sync
    ) where 
        A: Copy + Send + Sync,
        B: Copy + Send + Sync,
        C: Copy + Send + Sync,
        D: Copy + Send + Sync,
        O: Copy + Send + Sync + 'static,
        Vec<Option<A>>: ColVec,
        Vec<Option<B>>: ColVec,
        Vec<Option<C>>: ColVec,
        Vec<Option<D>>: ColVec,
        Vec<Option<O>>: ColVec 
    {
        let row_defaults: Vec<Option<O>> = self.get_set_row_defaults(qry, out_name); 
        let out_col_data: Vec<Option<O>> = self.get_ref(a_name)
            .par_iter()
            .zip( self.get_ref(b_name).par_iter() )
            .zip( self.get_ref(c_name).par_iter() )
            .zip( self.get_ref(d_name).par_iter() )
            .enumerate()
            .map(|(i, (((opt_a, opt_b), opt_c), opt_d))| {
                if qry.has_been_filtered && !qry.kept_rows[i] {
                    row_defaults[i].clone()
                } else {
                    match (opt_a, opt_b, opt_c, opt_d) {
                        (Some(a), Some(b), Some(c), Some(d)) => Some(op(a, b, c, d)),
                        _ => na_val
                    }
                }
            })
            .collect();
        self.replace_or_add_col(out_name, out_col_data);
    }
    // get the default contents of column rows that do not match a set filter
    fn get_set_row_defaults<O: Clone>(
        &self, qry: &Query, 
        out_name: &str
    ) -> Vec<Option<O>> 
    where 
        O: Clone + 'static,
        Vec<Option<O>>: ColVec
    {
        if !qry.has_been_filtered {
            vec![] // nothing to do; thus, copying and allocation only happens for filterered set calls
        } else if self.columns.contains_key(out_name){
            self.get(out_name) // unmatched rows in existing columns pass as is
        } else {
            vec![None; self.n_row] // umatched rows in new columns default to NA
        }
    }
    /* -----------------------------------------------------------------------------
    DataFrame column-level setters for `inject` actions
    ----------------------------------------------------------------------------- */
    /// Create or update a column from single Option<T> as input, recycling as needed.
    pub fn inject_col_const<
        O: Clone + 'static,
    >(
        &mut self,
        out_name: &str, 
        fill_val: Option<O>
    ) where Vec<Option<O>>: ColVec {
        let n_row = if self.n_row() > 1 { self.n_row() } else { 1 };
        let out_col_data = vec![fill_val; n_row];
        self.replace_or_add_col(out_name, out_col_data);
    }
    /// Create or update a column from Vec<Option<T>> as input, with option NA replacement.
    pub fn inject_col_vec<
        O: Copy + Send + Sync + 'static,
    >(
        &mut self,
        out_name: &str, 
        mut out_col_data: Vec<Option<O>>, na_replace: Option<O>
    ) where Vec<Option<O>>: ColVec {
        if let Some(na_replace) = na_replace {
            Do::na_replace(&mut out_col_data, na_replace);
        }
        self.replace_or_add_col(out_name, out_col_data);
    }
    // note: unlike set, do no deploy inject methods for column operations since df_inject!  
    // macro supports dynamic dispatch to either DataFrame or DataFrameSlice methods as df_src
    /* -----------------------------------------------------------------------------
    DataFrame cell-level getters and setters
    ----------------------------------------------------------------------------- */
    /// Return the String representation of a specific DataFrame cell by column name and integer row index.
    pub fn cell_string(&self, col_name: &str, row_i: usize) -> String {
        Column::check_i_bound(self.n_row, row_i, "get_as_string");
        self.get_column(col_name, "get_as_string").cell_string(row_i)
    }
    /// Return the Option<T> value of a specific DataFrame cell by column name and integer row index.
    pub fn cell<T: 'static + Clone>(&self, col_name: &str, row_i: usize) -> Option<T>  
    where Option<T>: ColCell {
        Column::check_i_bound(self.n_row, row_i, "cell");
        self.get_column(col_name, "cell").cell(col_name, row_i)
    }
    /// Set the Option<T> value of a specific cell in a DataFrame by integer row index and column name.
    pub fn set<T: 'static + Clone>(&mut self, col_name: &str, row_i: usize, value: Option<T>) 
    where Option<T>: ColCell {
        Column::check_i_bound(self.n_row, row_i, "set");
        self.get_column_mut(col_name, "set").set(row_i, value, col_name);
    }
    /* -----------------------------------------------------------------------------
    DataFrame support for indexed row retrieval
    ----------------------------------------------------------------------------- */
    /// Prepare a DataFrame for indexed row retrieval by creating a row index
    /// on one or more key columns.
    pub fn set_index(self, key_cols: Vec<String>) -> DataFrame {
        RowIndex::set_index(self, key_cols)
    }
    /// Return a DataFrameSlice of the rows in an indexed DataFrame that match the 
    /// specific key column values.
    pub fn get_indexed(&mut self, dk: DataFrame) -> DataFrameSlice {
        RowIndex::get_indexed(self, dk)
    }
}
