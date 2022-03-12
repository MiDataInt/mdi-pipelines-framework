#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);

#========================================================================
# help create all output directories required by a job configuration file
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $parsedYamls $pipelineName $pipelineOptions);
my (%paths, @paths);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qMkdir { 
    $pipelineOptions = "";

    # loop every pipeline execution chunk in data.yml
    foreach my $ymlChunk(@$parsedYamls){ 
        $$ymlChunk{pipeline} or next;
        $pipelineName = $$ymlChunk{pipeline}[0] or next; # [suiteName/]pipelineName[:suiteVersion]
        $pipelineName =~ m/(\S+):/ and $pipelineName = $1; # strip ':suiteVersion', only [suiteName/]pipelineName persists

        # parse all output directories required by the pipeline chunk
        my $yamls = getConfigFromLauncher();
        foreach my $i(0..$#{$$yamls{parsed}}){
            my $parsed = $$yamls{parsed}[$i];
            $$parsed{execute} or next; # the jobs configs we need to act on, in series (jobs may be arrays)
            my $pipelineAction = $$parsed{execute}[0];          
            my $optionFamilies = $$parsed{$pipelineAction};
            $optionFamilies or next;
            my $outputDir = $$optionFamilies{output}{'output-dir'} or next;
            checkMkdirPath($$outputDir[0]);
        }
    }

    # assemble the list of paths to be created
    my $message = "The following directories will be created:\n";
    my @missingPaths = ();
    foreach my $dir(@paths){
        $dir eq $paths{$dir} and next;
        push @missingPaths, $dir;
        $message .= "\n".
                    "    create: $dir\n".
                    "    exists: $paths{$dir}\n";
    }
    
    # confirm and execute directory creation
    if(@missingPaths){
        $options{'force'} or getPermissionGeneral($message);
        make_path(@missingPaths);
        print "\nall output directories created\n\n";

    # else nothing to do
    } else {
        print "\nall output directories already exist\n".
              "nothing to do\n\n";
    }
}
#========================================================================

#========================================================================
# output directory existence check
#------------------------------------------------------------------------
sub checkMkdirPath {
    my ($dir) = @_;
    $paths{$dir} and return; # already checked this path
    push @paths, $dir;
    -d $dir and $paths{$dir} = $dir and return;
    my @parts = split("/", $dir); # @parts has a leading "" if $dir starts with "/"
    my $i = 0;
    foreach my $j(1..$#parts){
        my $path = join("/", @parts[0..$j]);
        -d $path or last;
        $i = $j;
    }
    $paths{$dir} = join("/", @parts[0..$i]); # the path prefix that already exists
}
#========================================================================

1;
