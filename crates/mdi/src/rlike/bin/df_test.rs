use rayon::prelude::*;
use rlike::data_frame::{DataFrame, slice::DataFrameSlice};
use rlike::data_frame::query::Query;
use rlike::types::{ToRLVec, Agg, Do};
use rlike::data_frame::join::{Join, JoinType};
use rlike::data_frame::r#trait::DataFrameTrait;
use rlike::*;

pub const MY_LABELS: [&str; 6] = [
    "Ee90",
    "Aa12", 
    "Bb34", 
    "Cc56",
    "Dd78",
    "_XX"
];

fn main() {
    let (mut df_file, mut df_cpy) = (DataFrame::new(), DataFrame::new());
    println!();
    println!("==================================================================");
    for arg in std::env::args() {
        match arg.as_str() {
            "target/debug/df_test" => {},
            "bind" => {
                if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                df_file = test_bind(df_file);
            },
            "select" => {
                if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                df_file = test_select(df_file);
            },
            "set" => {
                if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                df_file = test_set(df_file);
            },
            "pivot" => {
                if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                df_file = test_pivot(df_file);
            },
            "aggregate" => {
                // if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                test_group_and_aggregate();
            },
            "do" => {
                if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                df_file = test_group_and_do(df_file);
            },
            "join" => {
                test_join();
            },
            "index" => {
                if df_file.is_empty() { (df_file, df_cpy) = load_data() }
                df_file = test_index(df_file);
            },
            _ => {
                println!("unrecognized test type: {}", arg);
            }
        }
    }
    println!("\nAll tests completed successfully!");
}

// test df_new! and df_read! macros
fn load_data() -> (DataFrame, DataFrame) {
    println!("initializing schema");
    let mut df_file = df_new!(
        capacity = 1e6,
        group_i:usize,
        record_i:usize,
        integer:i32,
        numeric:f64,
        logical:bool,
        factor:u16[MY_LABELS], // simplest form provides factor labels during schema creation
        // timestamp:i64,
    );
    // df.set_labels("factor", MY_LABELS.to_vec()); // alternative ways to set the factor labels
    // df_set_labels!(&mut df, factor = MY_LABELS);

    println!("reading data from file");
    df_read!(df_file, file = "test.txt");

    println!("creating an identical copy");
    let mut df_cpy = df_select!(&df_file);

    df_print!(df_file);
    (df_file, df_cpy)
}

// test df_set! macro
fn test_set(df_file: DataFrame) -> DataFrame {
    println!("setting columns in place");
    let n_row = df_file.n_row();
    let mut df_cpy = df_select!(&df_file);
    df_set!(
        &mut df_cpy,
        filter( // only matching rows are updated
            group_i:usize => |a| a == Some(2);
            // numeric:f64 => |a| a.is_none();
        ),
        do(
            fill1:u16 = 1;
            fill2:i32 = None;
            fill3:usize = Some(2);
            fill3:usize = fill3 => |a| a + 1_usize;
            fill4:i32 = integer => |a| a + 1;
            factor:u16 = vec![Some(2); n_row];
            test1a:bool[false] = logical => |a: &bool| !a;
            test1b:bool = logical => |a: &bool| !a;
            test1c:bool = integer => |a: &i32| *a > 5000;
            test2a:bool[false] = logical, test1a => |a: &bool, b: &bool| !a && !b;
            test2b: bool = logical, test1a => |a: &bool, b: &bool| !a && !b;
            test2c: bool = integer, test1a => |a: &i32, b: &bool| *a > 5000 && !b;
        )
    );
    println!("{}", df_cpy);
    df_file
}

// test df_cbind! and df_rbind! macros
fn test_bind(df_file: DataFrame) -> DataFrame {

    println!("cbinding");
    let df1 = df_query!(&df_file, select(group_i, integer));
    let df2 = df_query!(&df_file, select(record_i, numeric, factor));
    // let df_bind = df_cbind!(
    //     df1,
    //     df2,
    //     df_query!(&df_file, select(logical))
    // );
    let df_bind = df_cbind_ref!(
        &df1,
        &df2,
        &df_query!(&df_file, select(logical))
    );
    println!("{}", df_bind);

    println!("rbinding");
    let df1 = df_query!(&df_file, select(group_i, integer));
    let df2 = df_query!(&df_file, select(group_i, integer));
    // let df_bind = df_rbind!(
    //     df1,
    //     df2,
    //     df_query!(&df_file, select(group_i, integer))
    // );
    let df_bind = df_rbind_ref!(
        &df1,
        &df2,
        &df_query!(&df_file, select(group_i, integer))
    );
    println!("{}", df_bind);

    df_file
}

// test simple filter/sort/select queries
fn test_select(df_file: DataFrame) -> DataFrame {

    println!("querying (filter/sort/select)");
    let df_qry = df_query!(
        &df_file,
        filter(
            integer:i32 => |a| a >= Some(40000);
        ),
        sort(integer),
        select(integer, factor, logical)
    );
    println!("{}", df_qry);

    println!("query chain with pass-through");
    let df_qry = df_query!(
        &df_cbind_ref!(
            &df_query!(&df_file, select(group_i, integer)),
            &df_query!(&df_file, select(record_i, factor))
        ),
        filter(
            integer:i32 => |a| a >= Some(10000);
        ),
        sort(_integer, factor, record_i),
        // set(
        //     integer:i32 => |a| a + 1;
        // ),
        select(integer, factor, record_i)
    );
    println!("{}", df_qry);

    df_file
}

// test pivot queries
fn test_pivot(df_file: DataFrame) -> DataFrame {
    println!("pivoting");
    let df_pvt = df_query!(
        &df_file,
        filter(
            integer:i32 => |a| a <= Some(5000);
            // logical:bool  => |a| a;
        ),
        sort(),
        pivot(
            f64[0.0] = record_i ~ factor as numeric => Agg::sum;
            // f64 = record_i ~ factor as numeric => Agg::sum;
            // f64[0.0] = record_i ~ factor as integer => Agg::mean::<i32>;
            // f64 = record_i ~ factor as integer => |a: Vec<i32>| a[0] as f64;
            // i32 = record_i ~ factor as integer:i32 => |a| a[0];
            // bool = factor ~ record_i;
            // bool = _record_i ~ factor;
            // usize = _record_i ~ factor; 
        )
    );
    println!("{}", df_pvt);

    df_file
}

// test group and aggregate
fn test_group_and_aggregate(){
    println!("creating df");
    let df = df_new!(
        record_i = vec![10,11,12,13,14,15,16,17,18,19].to_rl(),
        int_col  = vec![99,99,0,99,99,99,0,99,99,99,].to_rl(),
        num_col  = vec![0.0,1.1,0.0,3.3,1.1,2.2,0.0,3.3,4.4,3.3,].to_rl(),
    );
    println!("{}", df);

    let df_qry = df_query!(
        &df,
        filter(
            int_col:i32 => |a| a != Some(0);
        ),
        sort(),
        // select(),
        group(num_col ~ record_i + int_col),
        aggregate(
            record_i:i32 = record_i => Agg::first;
            int_col:i32 = int_col => Agg::first;
            // record_i:f64 = record_i => Agg::mean::<i32>;
            // int_col:f64 = int_col => Agg::mean::<i32>;
        )
    );
    println!("{}", df_qry);
}

// test group and do queries
fn test_group_and_do(df_file: DataFrame) -> DataFrame {
    println!("doing DataFrame group and do");
    let df_do = df_query!(
        &df_file,
        filter(
            integer:i32 => |a| a <= Some(50);
        ),
        // sort(),
        // sort(record_i, integer),
        group(record_i ~ factor + integer + logical + numeric),
        do(|grp_i, grp, rows|{ // declare grp DataFrame as mutable to modify it with df_inject!()
            
            // as needed, execute artbitrary code to collect needed output data
            let n_grp_rows = rows.n_row();

            // use rows to inject new columns into grp or any other DataFrame
            df_inject!(
                // inject new rows into the `grp` DataFrame from the `rows` DataFrameSlice to include the grouping keys in the output
                // use `df_inject!(df_cbind_slice!(&grp, &rows), &rows, ...)` to include all key and non-key columns in the output
                // use `df_inject!(df_new!(), &rows, ...)` to exclude key columns from the output
                grp, 
                // df_cbind_slice!(&grp, &rows),
                // df_new!(),
                &rows,

                // single group values drawn from somewhere other than the group rows
                literal:bool = true;        // literal constant, wrapped and recycled to all output group rows as Vec<Option<T>>
                none:bool    = None;        // NA, recycled to all output group rows
                grp_i:usize  = Some(grp_i); // single expression result, wrapped and recycled to all output group rows
                n_row:usize  = vec![Some(n_grp_rows)]; // one-length Vec<Option<T>> recycled to all output group rows

                // single group values calculated from one or more group rows
                sum:i32 = integer => Do::sum; // single-column operation, same input and output data types
                sum_into:f64 = integer => Do::sum_into::<i32, _>; // single-column operation, different input and output data types
                custom_1:f64 = integer => |a: &[Option<i32>]| vec!(Some(a[0].unwrap() as f64)); // custom operation
                custom_2:f64[2.3] = integer => |_a: &[Option<i32>]| vec!(None); // custom operation, with NA replacement

                // // values vectors with one output row for each input row, passed as is or modified by an operation
                // integer:i32  = df_get![rows, integer]; // multi-row Vec<Option<T>> causes group to have rows.len() output rows
                // na_replace:i32[99] = vec![None; rows.n_row()]; // NA replacement value, applied as needed to all NA output group rows
                // add:i32[0] = integer, integer => Do::add; // two-column operation, same input and output data types, with NA replacement
                // custom_3:f64[-1.0] = integer, numeric => |a: &[Option<i32>], b: &[Option<f64>]| { // two-column custom operation
                //     a.par_iter().zip(b).map(|(a, b)| {
                //         if a.is_none() || b.is_none() { None } else { Some(a.unwrap() as f64 + b.unwrap() * 33.0) }
                //     }).collect()
                // };

                // // examples of additional functions that calculate row-level values from a group of rows
                // freq:f64 = integer => Do::freq::<i32>; // single-column operation, same input and output data types
                // cumsum:f64 = integer => Do::cumsum_into::<i32, _>; // single-column operation, same input and output data types
            )
        })
        // ,
        // // use query chains to calculate further derived values
        // set(cumfreq:f64 = cumsum, sum_into => |a, b| a / b;),
        // select()
    );
    println!("{}", df_do);

    println!("doing Vec group and do");
    let df_do = df_query!(
        &df_file,
        filter(
            integer:i32 => |a| a <= Some(50);
        ),
        sort(record_i, integer),
        group(record_i ~ factor + integer + logical + numeric),
        do::<i32>(|_grp_i, _grp, rows|{
            // df_get!(rows, integer).into_iter().flatten().collect::<Vec<i32>>() // remove NA values to yield primitive Vec
            df_get!(rows, integer, Do::na_rm) // same as above
        })
    ); 
    println!();
    println!("{:?}", df_do);

    df_file
}

// test df_new! and df_read! macros
fn test_join() {
    let mut strings = vec!["B"; 4];
    strings.extend(vec!["C"; 6]);

    println!("creating df1");
    let df1 = df_new!(
        key  = vec![ 6,7,8,10,            2,3,3,4,4,6 ].to_rl(),
        key2 = vec![ 6,7,8,10,            2,3,3,4,4,6 ].to_rl(),
        df1 = vec![ 6.12,7.11,8.11,10.11, 2.11,3.11,3.12,4.11,4.12,6.11 ].to_rl(),
        factor[MY_LABELS] = vec![2_u16; 10].to_rl(),
        string = strings.to_rl(),
    );
    println!("{}", df1);

    println!("creating df2");
    let df2 = df_new!(
        key  = vec![1,2,2,4,5,6,6,8,9].to_rl(),
        key2 = vec![1,2,2,4,5,6,6,8,9].to_rl(),
        df2 = vec![1.21,2.21,2.22,4.21,5.21,6.21,6.22,8.21,9.21].to_rl(),
        string = vec!["A"; 9].to_rl(),
    );
    println!("{}", df2);

    println!("creating df3");
    let mut df3 = df_select!(&df1, key);
    df_set!(&mut df3, df3:f64 = 55.0;);
    println!("{}", df3);

    println!("joining df1, df2, and df3");
    let df_join = df_join!(
        &df1, 
        &df2,
        // &df_query!(&df2, select(key, df2)),
        &df_query!(&df3, select(key, df3)), 
        filter( key:i32 => |a| a < Some(5); ),
        sort(),
        // inner( integer ~ *; )
        // inner( integer ~ record_i; )
        // filter( key:i32 => |a| a <= 6; ),
        // left( key ~ df1 + df2 + df3; )
        outer( key ~ df1 + df2 + df3; )
        // outer( key + key2 ~ *; )
    );
    println!("{}", df_join);
}

// test df_index! macro
fn test_index(df_file: DataFrame) -> DataFrame {

    // println!("copying unsorted data frame");
    // let df_qry = df_query!(&df_file, select());

    println!("pre-sorting data frame");
    let df_qry = df_query!(&df_file, sort(integer, logical), select());
    println!("{}", df_qry);

    // println!("aggregating data frame");
    // let df_qry = df_query!(&df_qry, 
    //     sort(),
    //     // group(record_i + logical ~ integer), 
    //     group(integer ~ logical + numeric), 
    //     aggregate(
    //         mean:f64 = numeric => Agg::mean::<f64>;
    //         count:usize = numeric => Agg::count::<f64>;
    //     )
    // );
    // println!("{}", df_qry);

    println!("pivoting");
    let df_qry = df_query!(
        &df_qry,
        // filter(
        //     integer:i32 => |a| a <= Some(5000);
        //     // logical:bool  => |a| a;
        // ),
        // sort(),
        pivot(
            // f64[0.0] = record_i ~ factor as numeric => Agg::sum;
            // f64 = record_i ~ factor as numeric => Agg::sum;
            // f64[0.0] = record_i ~ factor as integer => Agg::mean::<i32>;
            // f64 = record_i ~ factor as integer => |a: Vec<i32>| a[0] as f64;
            // i32 = record_i ~ factor as integer:i32 => |a| a[0];
            // bool = factor ~ record_i;
            // bool = _record_i ~ factor;
            // usize = _record_i ~ factor; 
            usize = integer ~ factor;
        )
    );
    println!("{}", df_qry);

    println!("indexing data frame");
    // let df_qry = df_index!(df_qry, record_i, logical);
    let df_qry = df_index!(df_qry, integer);
    // println!("{}", df_qry);

    println!("doing indexed retrieval");
    // let ds = df_get!(
    //     df_qry,
    //     record_i:usize = Some(23598), 
    //     logical:bool = None
    // );
    let ds = df_get!(
        df_qry,
        integer:i32 = Some(23598)
    );
    println!("{}", ds.to_df());

    df_file
}
