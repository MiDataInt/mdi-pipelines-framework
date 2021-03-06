use strict;
use warnings;

# working variables
use vars qw($jobManagerDir %commands $command @args
            $dataYmlFile %options $separatorLength %suppressLinesCommands);
our ($dataYmlDir, $dataYmlName,
     $qDataDir, $makeDirs,
     $archiveDir, $logDir, $scriptDir,
     $statusFile, $archiveStem);

#-----------------------------------------------------------------------
sub checkConfigFile { # make sure data targets file was specified and exists
    $dataYmlFile or throwError("'data.yml' is missing");
    -e $dataYmlFile or throwError("could not find config file:\n    $dataYmlFile");    
    $dataYmlFile = abs_path($dataYmlFile);  # convert all relative paths to completes paths
    $dataYmlFile =~ m|(.*)/(.+)$| or die "error parsing config file path\n";     
    ($dataYmlDir, $dataYmlName) = ($1, $2);
    $qDataDir = "$dataYmlDir/.$dataYmlName.data";  # data for yml source stored in single, portable hidden directory  
    $makeDirs = !(-d $qDataDir);
    $makeDirs and mkdir $qDataDir; 
    $archiveDir = getQSubDir('archive');
    $logDir     = getQSubDir('log', 1);
    $scriptDir  = getQSubDir('script', 1);
    $statusFile = "$qDataDir/$dataYmlName.status";  # status file lives in top-level hidden directory
    $archiveStem = "$archiveDir/$dataYmlName.status";
    my $yamls = loadYamlFromString( slurpFile($dataYmlFile) );
    ($$yamls{parsed} and @{$$yamls{parsed}}) or throwError("invalid YAML:\n    $dataYmlFile");    
    $$yamls{parsed};
}
sub getQSubDir { # subdirectories hold specific q-generated files
    my ($dirName, $makeSubDirs) = @_;
    my $dir = "$qDataDir/$dirName";
    $makeDirs and mkdir $dir;
    if($makeDirs and $makeSubDirs){  # job files placed in subdirectories by execution synchronicity
        foreach my $qType(qw(local SGE PBS slurm)){
            my $qTypeDir = "$dir/$qType";
            -d $qTypeDir or mkdir $qTypeDir;
        }
    }
    return $dir;
}
#-----------------------------------------------------------------------
sub executeCommand { # load scripts and execute command
    map { require $_ } glob("$jobManagerDir/lib/commands/*.pl");
    my $noLines = $suppressLinesCommands{$command};
    $noLines or $options{'_suppress-echo_'} or print "~" x $separatorLength, "\n";
    &{${$commands{$command}}[0]}(@args); # add remaining @args since other subs recall utility with additional arguments
    $noLines or print "~" x $separatorLength, "\n";
}
#========================================================================

1;
