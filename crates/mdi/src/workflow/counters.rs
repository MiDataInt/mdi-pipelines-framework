//! The Counters structure stores count values that can be passed to  
//! data processing functions as a single variable.
//! 
// dependencies
use std::collections::HashMap;
use num_format::{Locale, ToFormattedString};

// define a constant to print a separator line when printing counters
pub const COUNTER_SEPARATOR: &str = "------------------------------------------------------------";

/// The Counters struct stores keyed usize count values in a HashMap.
/// 
/// By convention, Counters objects are named `ctrs`.
pub struct Counters {
    tool:                 String,
    // regular counter fields, for things like record tallies
    keys:                 Vec<String>,
    descriptions:         HashMap<String, String>,
    counts:               HashMap<String, usize>,
    // keyed counter fields, for things like per-category tallies
    keyed_keys:           Vec<String>,
    keyed_descriptions:   HashMap<String, String>,
    keyed_counts:         HashMap<String, HashMap<String, usize>>,
    // indexed counter fields, for things like length distributions
    indexed_keys:         Vec<String>,
    indexed_descriptions: HashMap<String, String>,
    indexed_counts:       HashMap<String, Vec<usize>>,
}
impl Counters {
    /// Create a new Counters instance with specified "regular" counters keys 
    /// initialized to zero.
    /// 
    /// Pass requested counters as a slice of tuples of form `&[(&str, &str)]`,
    /// where the first element of each tuple is the counter key and the second
    /// element is the counter description.
    /// 
    /// Pass (COUNTER_SEPARATOR, "".to_string()) to insert a separator line
    /// between groups of related counters.
    /// 
    /// By convention, Counters objects are named `ctrs`.
    pub fn new(tool: &str, counters: &[(&str, &str)]) -> Self {
        let mut keys: Vec<String> = Vec::new();
        let mut descriptions: HashMap<String, String> = HashMap::new();
        let mut counts: HashMap<String, usize> = HashMap::new();
        let mut n_separators = 0_usize;
        for (key, description) in counters {
            let mut final_key = key.to_string();
            if *key == COUNTER_SEPARATOR {
                final_key = format!("{}{}", COUNTER_SEPARATOR.to_string(), n_separators);
                descriptions.insert(final_key.clone(), COUNTER_SEPARATOR.to_string());
                n_separators += 1;
            } else {
                descriptions.insert(final_key.clone(), (*description).to_string());
                counts.insert(final_key.clone(), 0);
            }
            keys.push(final_key);
        }
        Counters {
            tool: tool.to_string(),
            keys,
            descriptions,
            counts,
            keyed_keys:     Vec::new(),
            keyed_descriptions: HashMap::new(),
            keyed_counts:   HashMap::new(),
            indexed_keys:   Vec::new(),
            indexed_descriptions: HashMap::new(),
            indexed_counts: HashMap::new(),
        }
    }
    /// Add one or more regular counters to the Counters instance.
    pub fn add_counters(&mut self, counters: &[(&str, &str)]) -> &mut Self {
        for (key, description) in counters {
            self.keys.push(key.to_string());
            self.descriptions.insert(key.to_string(), (*description).to_string());
            self.counts.insert(key.to_string(), 0);
        }
        self
    }
    /// Add one or more keyed counters to the Counters instance.
    pub fn add_keyed_counters(&mut self, counters: &[(&str, &str)]) -> &mut Self {
        for (key, description) in counters {
            self.keyed_keys.push(key.to_string());
            self.keyed_descriptions.insert(key.to_string(), (*description).to_string());
            self.keyed_counts.insert(key.to_string(), HashMap::new());
        }
        self
    }
    /// Add one or more indexed counters to the Counters instance.
    pub fn add_indexed_counters(&mut self, counters: &[(&str, &str)]) -> &mut Self {
        for (key, description) in counters {
            self.indexed_keys.push(key.to_string());
            self.indexed_descriptions.insert(key.to_string(), (*description).to_string());
            self.indexed_counts.insert(key.to_string(), Vec::new());
        }
        self
    }
    /* ------------------------------------------------------------------
    regular counter methods
    ------------------------------------------------------------------ */
    /// Increment the count for the specified counter key by one.
    /// 
    /// Panic if the key is not found.
    pub fn increment(&mut self, key: &str) {
        let counter = self.counts.get_mut(key).unwrap_or_else(|| 
            panic!("Counters::increment error: key '{}' not found", key)
        );
        *counter += 1;
    }
    /// Increment the count for the specified counter key an arbitrary amount.
    /// 
    /// Panic if the key is not found.
    pub fn add_to(&mut self, key: &str, value: usize) {
        let counter = self.counts.get_mut(key).unwrap_or_else(|| 
            panic!("Counters::add_to error: key '{}' not found", key)
        );
        *counter += value;
    }
    /* ------------------------------------------------------------------
    keyed counter methods, with outer and inner keys, stored in HashMap
    ------------------------------------------------------------------ */
    /// Increment the count for the specified keyed counter key by one.
    /// 
    /// Panic if the outer key is not found.
    pub fn increment_keyed(&mut self, outer_key: &str, inner_key: &str) {
        let keyed_counter = self.keyed_counts.get_mut(outer_key).unwrap_or_else(|| 
            panic!("Counters::increment_keyed error: outer key '{}' not found", outer_key)
        );
        keyed_counter.entry(inner_key.to_string()).and_modify(|c| *c += 1).or_insert(1);
    }
    /// Increment the count for the specified keyed counter key an arbitrary amount.
    /// 
    /// Panic if the outer key is not found.
    pub fn add_to_keyed(&mut self, outer_key: &str, inner_key: &str, value: usize) {
        let keyed_counter = self.keyed_counts.get_mut(outer_key).unwrap_or_else(|| 
            panic!("Counters::add_to_keyed error: outer key '{}' not found", outer_key)
        );
        keyed_counter.entry(inner_key.to_string()).and_modify(|c| *c += value).or_insert(value);
    }
    /* ------------------------------------------------------------------
    indexed counter methods, with outer key and inner index, stored in Vec
    ------------------------------------------------------------------ */
    /// Increment the count for the specified indexed counter key by one.
    /// 
    /// Panic if the outer key is not found.
    pub fn increment_indexed(&mut self, key: &str, index: usize) {
        let indexed_counter = self.indexed_counts.get_mut(key).unwrap_or_else(|| 
            panic!("Counters::increment_indexed error: key '{}' not found", key)
        );
        indexed_counter.resize(index + 1, 0);
        indexed_counter[index] += 1;
    }
    /// Increment the count for the specified indexed counter key by one.
    /// 
    /// Panic if the outer key is not found.
    pub fn add_to_indexed(&mut self, key: &str, index: usize, value: usize) {
        let indexed_counter = self.indexed_counts.get_mut(key).unwrap_or_else(|| 
            panic!("Counters::add_to_indexed error: key '{}' not found", key)
        );
        indexed_counter.resize(index + 1, 0);
        indexed_counter[index] += value;
    }
    /* ------------------------------------------------------------------
    count reporting
    ------------------------------------------------------------------ */
    /// Print the value of all regular counters with their descriptions 
    /// to STDERR in the order they were initialized.
    pub fn print_all(&self) {
        for key in &self.keys {
            let description = self.descriptions.get(key).unwrap();
            if key.starts_with(COUNTER_SEPARATOR) {
                eprintln!("{}", description);
            } else {
                let count = self.counts.get(key).unwrap();
                eprintln!("{}\t{}\t{}\t{}", 
                    self.tool, 
                    count.to_formatted_string(&Locale::en), 
                    key, 
                    description
                );
            }
        }
    }
}
