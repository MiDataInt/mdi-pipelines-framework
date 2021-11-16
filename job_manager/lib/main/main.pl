#!/usr/bin/perl
use strict;
use warnings;
use Cwd(qw(abs_path));
			
#========================================================================
# main execution block
#========================================================================
use vars qw($jobManagerDir $jobManagerName %commands @options);
our ($command, @args) = @ARGV;
our ($dataYmlFile, $pipelineOptions);
#------------------------------------------------------------------------
map { $_ !~ m/main.pl$/ and require $_ } glob("$jobManagerDir/lib/main/*.pl");
#------------------------------------------------------------------------
sub jobManagerMain {

    # parse the various arguments provided on the job manager command line
    checkCommand();
    my $isStage2 = $commands{$command}[2];
    @args or $isStage2 or (reportOptionHelp($command) and exit);

    my @pipelineOptions = setOptions();
    checkRequiredOptions();    
    $isStage2 and executeCommand(); # shortcut to stage2 mdi:XXX execution
    my @dataYmlFiles; # our target file(s) that specific data jobs
    while (defined $pipelineOptions[0] and $pipelineOptions[0] =~ m/\.yml$/) {
        my $dataYmlFile = shift @pipelineOptions;
        push @dataYmlFiles, $dataYmlFile;
    }
    $pipelineOptions = join(" ", @pipelineOptions); # option values provided to override data.yml    
    
    # job manager requires a data.yml config file for job queuing (i.e. when not acting as a surrogate)
    @dataYmlFiles == 0 and throwError("'$jobManagerName $command' requires a <data.yml> configuration file");
    
    # if multiple config files, recall the job manager once for each file, with the same options
    if (@dataYmlFiles > 1){ 
        my $jobManagerOptions = join(" ", @options); # option values provided to guide job queuing
        foreach $dataYmlFile (@dataYmlFiles){
            my $perl = "perl $0 $command $jobManagerOptions $dataYmlFile $pipelineOptions";
            system($perl) and exit 1;  # abort if any run dies
        }
        exit;
    } 
    
    # finish a terminal call on a single file
    ($dataYmlFile) = @dataYmlFiles;    
    checkConfigFile(); 
    executeCommand();  # request is valid, proceed with execution
}
#========================================================================

1;
