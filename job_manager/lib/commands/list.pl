#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'list.pl' lists all pipelines and apps available in an MDI installation
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $separatorLength);
my $pipelinesLabel = "Stage 1 Pipelines";
my $appsLabel      = "Stage 2 Apps";
my $definitive = "definitive";
my $developer  = "developer-forks";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiList { 
    print "\nInstalled Tools\n";
    print "\n$ENV{MDI_DIR}\n";
    listInstalledTools($pipelinesLabel, "pipelines",  3);
    listInstalledTools($appsLabel,      "shiny/apps", 4);
    print "~" x $separatorLength, "\n";
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
        $tools{"$suite/$tool"}{$fork}++;
    }

    # print a tabular report of the tools
    my $maxLength = 0;
    foreach my $tool(keys %tools){
        my $length = length($tool);
        $length > $maxLength and $maxLength = $length;
    }
    print "\n$label\n";
    my $space = " " x 4;
    foreach my $tool(sort {$a cmp $b} keys %tools){
        my $def = $tools{$tool}{$definitive} ? $definitive : (" " x length($definitive));
        my $dev = $tools{$tool}{$developer}  ? $developer  : (" " x length($developer));
        my $padding = " " x ($maxLength - length($tool));
        print "  $tool$padding$space$def$space$dev\n";
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
