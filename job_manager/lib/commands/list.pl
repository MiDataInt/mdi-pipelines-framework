#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'list.pl' lists all pipelines and apps available in an MDI installation
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
my $pipelinesLabel = "Stage 1 Pipelines";
my $appsLabel      = "Stage 2 Apps";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiList { 
    print "\nInstalled Tools\n";
    print "\n$ENV{MDI_DIR}\n";
    listInstalledTools($pipelinesLabel, "pipelines",  3);
    listInstalledTools($appsLabel,      "shiny/apps", 4);
    exit;
}
sub listInstalledTools {
    my ($label, $searchPath,, $offset) = @_; 

    # parse tools from directory names
    my @paths = glob("$ENV{MDI_DIR}/suites/*/*/$searchPath/*");
    my %tools;
    foreach my $path(@paths){
        -d $path or next;
        my @path = split('/', $path);
        my $tool = $path[$#path];
        $tool =~ m/^_/ and next; 
        my $fork  = $path[$#path - $offset];
        my $suite = $path[$#path - $offset + 1];
        push @{$tools{"$suite//$tool"}}, $fork;
    }

    # print a tabular report of the tools
    print "\n$label\n";
    foreach my $tool(keys %tools){
        my $forks = join("\t", @{$tools{$tool}});
        print "  $tool\t$forks\n";
    }
    print "\n";
}
#========================================================================

1;

# ./suites/definitive/wilsontelab-mdi-tools/pipelines/_template
# ./suites/definitive/wilsontelab-mdi-tools/pipelines/download

# ./suites/developer-forks/wilsontelab-mdi-tools/pipelines/_template
# ./suites/developer-forks/wilsontelab-mdi-tools/pipelines/download

# ./suites/definitive/wilsontelab-mdi-tools/shiny/apps/_template
# ./suites/definitive/wilsontelab-mdi-tools/shiny/apps/wgaSeq

# ./suites/developer-forks/wilsontelab-mdi-tools/shiny/apps/_template
# ./suites/developer-forks/wilsontelab-mdi-tools/shiny/apps/wgaSeq
