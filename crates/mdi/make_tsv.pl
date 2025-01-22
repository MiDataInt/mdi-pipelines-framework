# action:
#   generate a simple tab-delimited stream on STDOUT useful for testing mdi_streamer
# output:
#   unheadered tab-delimited stream on STDOUT with columns:
#       group (integer)
#       record_in_group (integer)
#       random_value (integer)
# consistent with Rust:
#    struct InputRecord {
#        group:  u32,
#        record: u32,
#        random: u32,
#    }

use strict;
use warnings;

my $n_groups = 10000;
my $max_records_per_group = 5;
my @names = map { $_ x 5 } qw(A B C D E);

foreach my $group(1..$n_groups){
    my $n_records_in_group = int(rand($max_records_per_group)) + 1;
    foreach my $record_in_group(1..$n_records_in_group){
        print join("\t", $group, $record_in_group, $names[$record_in_group - 1], int(rand(100000))), "\n";
    }
}
