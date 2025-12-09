//! The 'get' macros are used to extract values from a DataFrame,
//! allowing allow for quote-free calls to DataFrame[Slice]::get[_ref]().

/// Get a vector of values as Vec<Option<T>> suitable for populating a DataFrame Column,
/// working from a source DataFrame or DataFrameSlice, by either:
/// - copying values from a single source Column
/// - applying a vectorized operation to one or more Columns
/// 
/// Alternatively, get a DataFrameSlice of rows matching specific key column values
/// of an indexed DataFrame.
/// 
/// # Examples
/// ```
/// // get a vector of column values; df can be a DataFrame or DataFrameSlice
/// let vals: Vec<Option<i32>> = df_get!(&df, col1); // copies row data from source col1 to vals
/// let val:  Vec<Option<i32>> = df_get!(&df, col1, Do::sum); // yields a single row value aggregated over col1
/// let vals: Vec<Option<i32>> = df_get!(&df, col1, col2, Do::add); // yields a vector the same length as col1 and col2
/// let vals: Vec<Option<i32>> = df_get!(&df, col1, col2, |a: &[Option<i32], b: &[Option<i32]| ...); // a custom operation
/// 
/// // get a DataFrameSlice of rows matching specific key column values
/// let ds: DataFrameSlice = df_get!(&df, col1 = Some(1), col2 = Some(2.0)); // copies all rows matching col1=1 and col2=2; df must be indexed
/// ```
#[macro_export]
macro_rules! df_get {

    // get all rows that match specific key column values
    ($df:expr, $($col_name:ident:$data_type:ty = $col_val:expr),+ $(,)?) => {
        {
            let mut dk = DataFrame::new();
            $( dk.add_col::<$data_type>(stringify!($col_name), vec![$col_val]); )+
            $df.get_indexed(dk)
        }
    };

    // three-column operations
    // throughout, df can be a DataFrame or DataFrameSlice
    ($df:expr, $a_name:ident, $b_name:ident, $c_name:ident, $op:expr $(,)?) => {
        {
            $op(
                $df.get_ref(stringify!($a_name)),
                $df.get_ref(stringify!($b_name)),
                $df.get_ref(stringify!($c_name))
            )
        }
    };
    // two-column operations
    ($df:expr, $a_name:ident, $b_name:ident, $op:expr $(,)?) => {
        {
            $op(
                $df.get_ref(stringify!($a_name)),
                $df.get_ref(stringify!($b_name))
            )
        }
    };
    // single-column operations
    ($df:expr, $a_name:ident, $op:expr $(,)?) => {
        {
            $op(
                $df.get_ref(stringify!($a_name))
            )
        }
    };
    // return the copied values of a column
    ($df:expr, $a_name:ident $(,)?) => {
        {
            $df.get(stringify!($a_name))
        }
    };
}
