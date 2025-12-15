//! This binary script demonstrates the usage of the RLike DataFrame API.
//! 
//! It builds the simple example DataFrame used in `rlike_data_model.md`,
//! then illustrates core DataFrame operations with the following outline
//! (read in order, it gets progressively more complex).
//!   - Imports      = bring DataFrame features into scope
//!   - Constructors = create DataFrames
//!   - Display      = inspect DataFrames
//!   - Getters      = extract data from DataFrames as column vectors or cell values
//!   - Setters      = modify data in DataFrames in place
//!   - Queries      = ask questions of DataFrames; create new DataFrames from results
//!   - Aggregation  = summarize DataFrames by (sorted) row groups
//!   - Pivots       = long-to-wide reshaping of DataFrames
//!   - Indexing     = data retrieval using key columns for fast data access
//!   - Binding      = create new DataFrames as row/column-wise combinations of existing DataFrames
//!   - Joins        = combine DataFrames by matching column values
//! 
//! Usage here emphasizes DataFrame macros that offer a concise and expressive syntax
//! for table operations. Many actions can also be accomplished using method calls.
//! 
//! While this example covers most things you will commonly do with DataFrames, it is
//! not exhaustive of all features or the different ways actions can be accomplished.
//! See the documentation for individual macros and methods for more details.
//! 
//! Don't be deceived by the very simple and small DataFrames used here! See example
//! `data_frame_stress_test.rs` to explore DataFrame performance and scalability with
//! data sets encompassing millions of rows (or as many as you care to test).

use core::panic;

/*----------------------------------------------------------------------------
Imports = bring DataFrame features into scope
--------------------------------------------------------------------------- */
use mdi::data_frame::prelude::*; // one line enables all DataFrame features

fn main() {

    /*------------------------------------------------------------------------
    Constructors = create DataFrames
    ----------------------------------------------------------------------- */
    // Create a new DataFrame with initial data using the `df_new!()` macro.
    // Here, column data types are inferred from input data.
    // Values are wrapped in `Option<T>`, either manually or using `to_rl()`, to represent NA/nulls.
    // Other ways of filling data frames from IO are illustrated in example `data_frame_stress_test.rs`,
    // including the use of additional specially handled data types.
    let mut df1 = df_new!(
        record_i = (10..=19).collect::<Vec<_>>().to_rl(), // entries are separated by commas
        int_col  = vec![99, 99, 0, 99, 99, 99, 0, 99, 99, 99].to_rl(),
        num_col  = vec![Some(0.0), Some(1.1), None, Some(3.3), Some(1.1), 
                        Some(2.2), None, Some(3.3), Some(4.4), Some(3.3)],
    );

    // Copy a data frame using the query interface (see more below) with no operations.
    let mut df2 = df_query!(&df1, select());
    let _df3 = df_select!(&df1); // synonymous with previous line

    // Initialize an empty DataFrame to be filled later using the `new()` method.
    // This DataFrame has no columns or rows.
    let df4 = DataFrame::new();

    // Initialize an empty DataFrame using another DataFrame's columns as a schema.
    // This DataFrame has the same columns and data types as `df1` but no rows.
    let mut df5 = DataFrame::from_schema(&df1);
    df5.reserve(1000); // reserve space for expected rows to minimize reallocation

    // Initialize an empty DataFrame with a schema you define.
    let _df6 = df_new!(
        capacity = 1000, // optional initial capacity (default is 100K rows)
        record_i: i32,
        int_col:  i32,
        num_col:  f64
    );

    /*------------------------------------------------------------------------
    Display = inspect DataFrames
    ----------------------------------------------------------------------- */
    // Print a summary of a DataFrame's structure and contents by exploiting its Display trait.
    // Adjust the layout by setting `df1.print_max_rows` and `df1.print_max_col_width`.
    eprint!("\ndf1 (initial data){}\n", df1);
    // DataFrame: 10 rows × 3 columns
    // record_i <i32> int_col <i32> num_col <f64> 
    // -------------- ------------- ------------- 
    // 10             99            0             
    // 11             99            1.1           
    // 12             0             NA            
    // 13             99            3.3           
    // 14             99            1.1           
    // 15             99            2.2           
    // 16             0             NA            
    // 17             99            3.3           
    // 18             99            4.4           
    // 19             99            3.3   
    eprint!("df4 (empty){}", df4);
    // DataFrame: 0 rows × 0 columns
    eprint!("df5 (from schema){}\n", df5);
    // DataFrame: 0 rows × 3 columns
    // record_i <i32> int_col <i32> num_col <f64>
    // -------------- ------------- ------------- 

    /*------------------------------------------------------------------------
    Getters = extract data from DataFrames as column vectors or cell values
    ----------------------------------------------------------------------- */
    // Extract data from a column as a vector using the `df_get!()` macro.
    // Note that no quotes are needed on column names in macro statements, unlike methods.
    let df1_int_col: Vec<Option<i32>> = df_get!(&df1, int_col);
    let df1_num_col: Vec<Option<f64>> = df1.get("num_col"); // or `df.get_ref("num_col")`
    let df1_num_col_row_3: Option<f64> = df1.cell("num_col", 3);
    eprint!("Extracted int_col values:\n{:?}\n\n", df1_int_col);
    eprint!("Extracted num_col values:\n{:?}\n\n", df1_num_col);
    assert_eq !(df1_num_col_row_3.unwrap(), 3.3); // row_i 3 uses 0-based row numbering

    // Data manipulations can be performed on the fly while extracting data using `df_get!()`.
    let record_i_sum: Vec<Option<i32>> = df_get!(&df1, record_i, Do::sum); // a single value aggregated over record_i
    let vectorized_sum: Vec<Option<i32>> = df_get!(&df1, record_i, int_col, Do::add); // a vector of length df1.n_row()
    assert_eq !(record_i_sum[0].unwrap(), 145); // sum of 10 through 19
    assert_eq !(vectorized_sum, vec![
        Some(109), Some(110), Some(12), Some(112), Some(113), // pairwise sums by row
        Some(114), Some(16), Some(116), Some(117), Some(118)
    ]);

    /*------------------------------------------------------------------------
    Setters = modify data in DataFrames in place
    ----------------------------------------------------------------------- */
    // Add and modify all rows of target columns using the `df_set!()` macro.
    // Here, operations are strongly typed, i.e., output column data types must be specified
    // (Rust Analyzer/cargo will tell you if type declaration is needed in closures).
    // The set statement syntax, which ends with a semicolon, is:
    //      `out_col:type[na_replace] = in_col ... => |a ...| ...;`,
    // which in natural language reads from left-to-right as:
    //      "create output column of this name and data type [with this NA replacement value]  
    //       from these input columns mapped into this operation"
    // where operations can be any closure or function that accepts value(s) from one row.
    let n_row = df2.n_row(); // n_col() also available, see DataFrame methods
    df_set!(&mut df2, 
        const_fill:i32 = Some(33);                   // constant fill with row recycling
        vec_fill:usize = (0..n_row).collect::<Vec<usize>>().to_rl(); // vector fill
        int_col_add_1:i32 = int_col => |a| a + 1;    // new column from op on existing column
        num_col:f64 = num_col => |a: &f64| a + 0.5;  // modify existing column in place
        int_add_num:f64[0.0] = int_col, num_col =>   // multi-column operation with default value 0.0
            |a: &i32, b: &f64| (*a as f64) + b;
    );

    // Column updates can be applied to only those rows matching a condition
    // using the 'filter and do' variation of `df_set!()`. See the query
    // interface below for details on the filter statement syntax.
    df_set!(&mut df2,
        filter( int_col:i32 => |a| a == Some(0); ),
        do( record_i:i32 = Some(666); )
    );
    eprint!("modified df2{}\n", df2);
    // DataFrame: 10 rows × 7 columns
    // record_i <i32> int_col <i32> num_col <f64> const_fill <i32> vec_fill <usize> int_col_add_1 <i32> int_add_num <f64>
    // -------------- ------------- ------------- ---------------- ---------------- ------------------- ----------------- 
    // 10             99            0.5           33               0                100                 99.5           
    // 11             99            1.6           33               1                100                 100.6          
    // 666            0             NA            33               2                1                   0              
    // 13             99            3.8           33               3                100                 102.8          
    // 14             99            1.6           33               4                100                 100.6          
    // 15             99            2.7           33               5                100                 101.7          
    // 666            0             NA            33               6                1                   0              
    // 17             99            3.8           33               7                100                 102.8          
    // 18             99            4.9           33               8                100                 103.9          
    // 19             99            3.8           33               9                100                 102.8   

    // Use the `df_drop!()` and `df_retain!()` macros to quickly remove columns from a DataFrame.
    // Like same-column `df_set!()` ops, these macros modify DataFrames in place with no new memory allocation.
    df_drop!(&mut df2, int_col_add_1, int_add_num);
    assert_eq !(*df2.col_names(), vec!["record_i", "int_col", "num_col", "const_fill", "vec_fill"]);
    df_retain!(&mut df2, const_fill, vec_fill);
    assert_eq !(*df2.col_names(), vec!["const_fill", "vec_fill"]);

    /*------------------------------------------------------------------------
    Queries = ask questions of DataFrames; create new DataFrames from results
    ----------------------------------------------------------------------- */
    // Query DataFrames using the `df_query!()` macro, making sequential calls to query 'actions'.
    // Basic queries follow ordered `filter()`, `sort()`, and `select()`, i.e., "FSS" actions,
    // where `select()` is required and optionally preceded by `filter()` and/or `sort()`.
    // The filter statement syntax, which ends with a semicolon and returns bool, is:
    //      `col:type [, col:type ...] => |a [, ...]| ...;`,
    // which in natural language reads from left-to-right as:
    //      "use these columns of these names and data types mapped into this operation to filter rows"
    let df7 = df_query!(&df1,
        filter( int_col:i32 => |a| a != Some(0); ), // filter to rows where int_col != 0 or None
        sort( num_col ),                            // sort by num_col ascending
        select( record_i, num_col )                 // select output columns
    );
    eprint!("df7 (simple filter and sort){}\n", df7);
    // DataFrame: 8 rows × 2 columns
    // record_i <i32> num_col <f64> 
    // -------------- ------------- 
    // 10             0             
    // 11             1.1           
    // 14             1.1           
    // 15             2.2           
    // 13             3.3           
    // 17             3.3           
    // 19             3.3           
    // 18             4.4  

    // Multi-statement/column filtering and sorting is supported. Multi-statement filters use AND logic.
    // Filter conditions can also be built using multiple columns, e.g., for OR logic or arithmetic.
    // Non-string sorts can be negated using the '_' prefix to indicate descending order.
    let df7 = df_query!(&df1,
        filter( 
            int_col:i32 => |a| a != Some(0); // use as many conditions as needed
            num_col:f64 => |a| a >= Some(2.0);
            int_col:i32, num_col:f64 => |a, b| a != Some(0) || b >= Some(2.0); // a multi-column condition
        ),
        sort( _num_col, record_i), // sort by num_col descending, then record_i ascending
        select( record_i, num_col )
    );
    eprint!("df7 (multi-statement/column filters, descending sort){}\n", df7);
    // DataFrame: 5 rows × 2 columns
    // record_i <i32> num_col <f64> 
    // -------------- ------------- 
    // 18             4.4           
    // 13             3.3           
    // 17             3.3           
    // 19             3.3           
    // 15             2.2  

    // A single call to `df_query!()` can perform chained queries - just continue
    // to call another query sequence after calling `select()`.
    let df7 = df_query!(&df1,
        select( record_i, num_col ),                  // the first query sequence in a chain
        filter( record_i:i32 => |a| a >= Some(15); ), // the second query sequence in a chain
        select(num_col) // a trivial example, you would not normally do this but it works
    );
    eprint!("df7 (query chain){}\n", df7);
    // DataFrame: 5 rows × 1 columns
    // num_col <f64> 
    // ------------- 
    // 2.2           
    // NA            
    // 3.3           
    // 4.4           
    // 3.3  

    /*------------------------------------------------------------------------
    Aggregation = summarize DataFrames by (sorted) row groups
    ----------------------------------------------------------------------- */
    // Grouping queries are performed using `df_query!()` with `group()` and `aggregate()` 
    // actions following optional `filter()` and `sort()` actions, instead of `select()`.
    // The group statement syntax is:
    //      `grouping_cols + ... ~ agg_cols + ...`,
    // which evokes the R formula syntax with columns of different roles separated by '~'.
    // The aggregate statement syntax, which ends with a semicolon, is:
    //      `out_col:out_type[na_replace] = in_col [, in_col...] => |a ...| ...`,
    // which in natural language reads from left-to-right as:
    //      "create output column of this name and data type [with this NA replacement value] 
    //       by mapping these columns into this aggregation operation"
    let df8 = df_query!(
        &df1,
        filter( int_col:i32 => |a| a != Some(0); ),
        sort( num_col, int_col ), // you can sort by more than the grouping columns, but grouping columns come first
        group( num_col ~ record_i + int_col ), // group by num_col, aggregate over record_i and int_col
        aggregate( // aggregation statements, yielding a single value from Vec<T>
            record_i:i32 = record_i => Agg::first;       // using predefined aggregation functions
            int_col:i32 = int_col => |a: Vec<i32>| a[0]; // the same 'first' op using a custom closure
        )
    );
    eprint!("df8 (sorted group by){}\n", df8);
    // DataFrame: 5 rows × 3 columns
    // num_col <f64> record_i <i32> int_col <i32> 
    // ------------- -------------- ------------- 
    // 0             10             99            
    // 1.1           11             99            
    // 2.2           15             99            
    // 3.3           13             99            
    // 4.4           18             99    

    // If the `sort()` action is omitted before `group()`, grouping is done using hashes in a
    // manner that returns results in the order that groups were first encounted in the DataFrame.
    let df8 = df_query!(
        &df1,
        filter( int_col:i32 => |a| a != Some(0); ),
        group( num_col ~ record_i + int_col ), // same grouping query without pre-sorting
        aggregate(
            record_i:i32 = record_i => Agg::first;
            int_col:i32 = int_col => |a: Vec<i32>| a[0];
        )
    );
    eprint!("df8 (unsorted group by){}\n", df8);
    // DataFrame: 5 rows × 3 columns
    // num_col <f64> record_i <i32> int_col <i32> 
    // ------------- -------------- ------------- 
    // 0             10             99            
    // 1.1           11             99            
    // 3.3           13             99            <<<<< row order differs from prior example
    // 2.2           15             99            
    // 4.4           18             99  

    // More complex aggregation operations, including generating entirely new
    // DataFrames, are achieved using the 'group and do' variation of `df_query!()`,
    // where `aggregate()` is replaced with `do()`. `do()` takes a closure with signature:
    //      `|grp_i: usize, grp: DataFrame, rows: DataFrameSlice| -> DataFrame`, where:
    //  `grp_i` is a 0-referenced index of the target group that can be used as a simplified group key
    //  `grp` is an owned, single-row DataFrame containing the key column(s) of the target group
    //  `rows` is a DataFrameSlice from which the group's non-key columns can be accessed for operations
    // Often you will inject data from `rows` into `grp` using the `df_inject!()` macro as illustrated,
    // using the same statement syntax as `df_set!()`.
    let df8 = df_query!(
        &df1,
        filter( int_col:i32 => |a| a != Some(0); ),
        group( num_col ~ record_i + int_col ),
        do( |grp_i, grp, rows| {
            // tasks in the `do` closure can be as complex as needed and return any DataFrame
            df_inject!(grp, &rows, // like df_set!(), but injects from rows into grp
                grp_i:usize      = Some(grp_i);
                row_count:usize  = Some(rows.n_row());
                sum_record_i:i32 = record_i => Do::sum; // or Do::cumsum for a running total per group
            )
        }),
        select( grp_i, num_col, row_count, sum_record_i )
    );
    eprint!("df8 (group and do){}\n", df8);
    // DataFrame: 5 rows × 4 columns
    // grp_i <usize> num_col <f64> row_count <usize> sum_record_i <i32> 
    // ------------- ------------- ----------------- ------------------ 
    // 0             0             1                 10                 
    // 1             1.1           2                 25                 
    // 2             3.3           3                 49                 
    // 3             2.2           1                 15                 
    // 4             4.4           1                 18  

    /*------------------------------------------------------------------------
    Pivots = long-to-wide reshaping of DataFrames
    ----------------------------------------------------------------------- */
    // A pivot query is similar to a grouping query except that the new aggregation 
    // columns are created based on the unique values of a single pivot column.
    // Two common pivot actions use the following shorthand statement syntax:
    //      `bool  = key_col [+ key_col ...] ~ pivot_col;`
    //      `usize = key_col [+ key_col ...] ~ pivot_col;`:
    // where the formula LHS are the grouping key columns, and the RHS is the pivot column.
    let df9 = df_query!(
        &df1,
        sort( _num_col ),
        pivot( usize = num_col ~ int_col; ) // or bool = ... to report true/false presence
    );
    eprint!("df9 (simple pivot, count){}\n", df9);
    // DataFrame: 6 rows × 3 columns
    // num_col <f64> 0 <usize> 99 <usize>  <<<<< unique values of int_col
    // ------------- --------- ---------- 
    // NA            2         0           <<<<< row counts by num_col group
    // 4.4           0         1          
    // 3.3           0         3          
    // 2.2           0         1          
    // 1.1           0         2          
    // 0             0         1 

    // Custom pivot fill operations are supported by the extended statement syntax:
    //      `out_type[NA_value] = key_col [+ key_col ...] ~ pivot_col as fill_col => |a| ...;`
    // where the new element is fill_col, which could be a key_col, the pivot_col, or another column
    // used to fill pivoted output cells via a provided operation that acts on Vec<fill_col type>.
    let df9 = df_query!(
        &df1,
        sort( _num_col ),
        pivot( f64[-1.0] = num_col ~ int_col as record_i => Agg::mean::<i32>; ) 
    );
    eprint!("df9 (custom pivot, mean){}\n", df9);
    // DataFrame: 6 rows × 3 columns
    // num_col <f64> 0 <f64> 99 <f64>           
    // ------------- ------- ------------------ 
    // NA            14      -1                 
    // 4.4           -1      18                 
    // 3.3           -1      16.333333333333332  <<<<< mean of record_i by num_col group
    // 2.2           -1      15                 
    // 1.1           -1      12.5               
    // 0             -1      10  

    /*------------------------------------------------------------------------
    Indexing = data retrieval using key columns for fast data access
    ----------------------------------------------------------------------- */
    // Set an index on a DataFrame using named columns as keys.
    df1 = df_index!(df1, record_i, num_col); // pass and reclaim as owned in case df1 needs to be sorted

    // Extract a DataFrameSlice using the `df_get_indexed!()` macro with requested key value(s).
    let ds1 = df_get_indexed!(&df1, record_i = Some(17), num_col = Some(3.3));
    eprint!("ds1 (indexed DataFrameSlice, matching key){}\n", ds1.to_df());

    // If no match is found, an empty DataFrameSlice is returned.
    let ds1 = df_get_indexed!(&df1, record_i = Some(17), num_col = Some(4.4));
    eprint!("ds1 (indexed DataFrameSlice, unmatched key){}\n", ds1.to_df());

    /*------------------------------------------------------------------------
    Binding = create new DataFrames as row/column-wise combinations of existing DataFrames
    ----------------------------------------------------------------------- */
    // Combine DataFrames with the same number of rows by pasting their columns (cbind).
    // Column binding recycles empty and single-column DataFrames to match the number 
    // of rows in the larger DataFrame.
    let df1 = df_new!(
        col1  = vec![1, 2, 3].to_rl(),
        col2  = vec![4, 5, 6].to_rl(),
    );
    let df2 = df_new!(
        col3  = vec![1, 2, 3].to_rl(),
        col4  = vec![4, 5, 6].to_rl(),
    );
    let df3 = df_new!(
        col5  = vec![7].to_rl(),
        col6  = vec![8].to_rl(),
    );
    // The first macro version, `df_cbind_ref!()`, retains the input DataFrames but is  
    // slower as it must clone data. Inputs are immutable DataFrame references.
    let _df4 = df_cbind_ref!(&df1, &df2, &df3);
    // The second macro version, `df_cbind!()`, consumes the input DataFrames and is faster.
    // Bind macros are variadic and accept any number of data frames as input.
    let df4 = df_cbind!(df1, df2, df3);
    eprint!("df4 (cbind){}\n", df4);
    // DataFrame: 3 rows × 6 columns
    // col1 <i32> col2 <i32> col3 <i32> col4 <i32> col5 <i32> col6 <i32> 
    // ---------- ---------- ---------- ---------- ---------- ---------- 
    // 1          4          1          4          7          8           <<<<< col5/6 recycled
    // 2          5          2          5          7          8          
    // 3          6          3          6          7          8   

    // Combine new DataFrames with the same column schema by stacking their rows (rbind).
    let df1 = df_new!(
        col1  = vec![1, 2, 3].to_rl(),
        col2  = vec![4, 5, 6].to_rl(),
    );
    let df2 = df_new!(
        col1  = vec![1, 2, 3].to_rl(),
        col2  = vec![4, 5, 6].to_rl(),
    );
    let df3 = df_new!(
        col1  = vec![7].to_rl(),
        col2  = vec![8].to_rl(),
    );
    let _df4 = df_rbind_ref!(&df1, &df2, &df3); // again, _ref retains input DataFrames
    let df4 = df_rbind!(df1, df2, df3);         // while this version consumes them
    eprint!("df4 (rbind){}\n", df4);
    // DataFrame: 7 rows × 2 columns
    // col1 <i32> col2 <i32> 
    // ---------- ---------- 
    // 1          4          
    // 2          5          
    // 3          6          
    // 1          4          
    // 2          5          
    // 3          6          
    // 7          8  

    // If DataFrames have unshared columns when using `df_rbind!()`, you can drop some "on the fly" 
    // without storing intermediate DataFrames - you will find many uses for such transient DataFrames.
    let df1 = df_new!(
        col1  = vec![1, 2, 3].to_rl(),
        col2  = vec![4, 5, 6].to_rl(),
    );
    let df2 = df_new!(
        col1  = vec![1, 2, 3].to_rl(),
        col2  = vec![4, 5, 6].to_rl(),
        col3  = vec![7, 8, 9].to_rl(),
    );
    eprint!("transient df (on the fly rbind){}\n", df_rbind!(
        df1,
        df_select!(&df2, col1, col2) // omit col3 from df2 before binding
    ));
    // DataFrame: 6 rows × 2 columns
    // col1 <i32> col2 <i32> 
    // ---------- ---------- 
    // 1          4          
    // 2          5          
    // 3          6          
    // 1          4          
    // 2          5          
    // 3          6  

    /*------------------------------------------------------------------------
    Joins = combine DataFrames by matching column values
    ----------------------------------------------------------------------- */
    // Perform SQL-like joins (R-like merges) between two DataFrames with shared 
    // columns using the `df_join!()` macro, which acts on two DataFrames and 
    // substitutes actions `inner()`, `left()`, or `outer()`, following similar 
    // `filter()` and `sort()` actions as for `df_query!()`.
    // The join statement syntax, which ends with a semicolon, is:
    //      `key_col [+ key_col ...] ~ select_col [+ select_col ...];`,
    // where key_col(s) are the shared columns used to match rows between DataFrames,
    // and select_col(s) are input-specific columns to include in the output DataFrame.
    let df1 = df_new!(
        col1  = vec![1, 2, 3, 11].to_rl(),
        col2  = vec![4, 5, 6, 12].to_rl(),
    );
    let df2 = df_new!(
        col1  = vec![1, 2, 3, 13].to_rl(),
        col3  = vec![7, 8, 9, 14].to_rl(),
    );
    let df3 = df_join!(&df1, &df2,
        inner(col1 ~ col2 + col3;) // unsorted joins use hashes internally
    );
    eprint!("df3 (unsorted inner join){}\n", df3);
    // DataFrame: 3 rows × 3 columns
    // col1 <i32> col2 <i32> col3 <i32> 
    // ---------- ---------- ---------- 
    // 1          4          7          
    // 2          5          8          
    // 3          6          9   
    let df3 = df_join!(&df1, &df2,
        sort(), // pre-sort on implicit key columns, i.e., don't provide column names here
        left(col1 ~ col2 + col3;)
    );
    eprint!("df3 (sorted left join){}\n", df3);
    // DataFrame: 4 rows × 3 columns
    // col1 <i32> col2 <i32> col3 <i32> 
    // ---------- ---------- ---------- 
    // 1          4          7          
    // 2          5          8          
    // 3          6          9          
    // 11         12         NA      
    let df3 = df_join!(&df1, &df2,
        sort(), // sorting is required for outer joins
        outer(col1 ~ col2 + col3;)
    );
    eprint!("df3 (outer join){}\n", df3);
    // DataFrame: 5 rows × 3 columns
    // col1 <i32> col2 <i32> col3 <i32> 
    // ---------- ---------- ---------- 
    // 1          4          7          
    // 2          5          8          
    // 3          6          9          
    // 11         12         NA         
    // 13         NA         14 

}
