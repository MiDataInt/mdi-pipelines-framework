use strict;
use warnings;

#========================================================================
# 'environment.pl' returns the environment variables passed to queued jobs
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $envDir %allJobs %targetJobIDs $separatorLength %qInUse);
my $envDelimiter = " = ";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qEnvironment {
    $options{'no-chain'} = 1;  # report action restricted to requested jobs 
    getJobStatusInfo();
    parseJobOption(\%allJobs, 'environment');  
    showEnvironments();
} 
#========================================================================

#========================================================================
# echo environment variables
#------------------------------------------------------------------------
sub showEnvironments { 
    my @jobIDs = sort {$a <=> $b} keys %targetJobIDs;
    if(@jobIDs){
        foreach my $jobID(@jobIDs){
            print "=" x $separatorLength, "\n";
            $options{'_q_remote_'} and print "ENVIRONMENT: ";
            print "job: $jobID", "\n";      
            print "-" x $separatorLength, "\n";  
            my ($qType, $array) = @{$targetJobIDs{$jobID}};            
            my $inFile = getEnvFile($qType, $jobID);
            my $fileContents;
            if(-e $inFile){
                print "$inFile\n";                 
                print "-" x $separatorLength, "\n";           
                $fileContents = slurpFile($inFile);
            } else {
                $fileContents = "could not recover stored environment variables\n";
            }
            print $fileContents, "\n";            
        }
        print "=" x $separatorLength, "\n";
    } else {
        print "no jobs matched '--job $options{'job'}'\n";
    }
}
#========================================================================

#========================================================================
# environment files
#------------------------------------------------------------------------
sub getEnvFile {
    my ($qType, $jobID) = @_;
    return "$envDir/$qType/$jobID.env";
}
sub saveEnvironment {  # during submit, save a copy of all environment variables
    my ($qType, $jobID) = @_;
    my $envFile = getEnvFile($qType, $jobID);
    open my $outH, ">", $envFile or die "could not open $envFile for writing: $!\n";
    foreach my $key (sort {$a cmp $b} keys %ENV) { 
        defined $ENV{$key} or next;
        print $outH "$key$envDelimiter$ENV{$key}\n";
    }
    close $outH;
    return $envFile;
}
sub setEnvironment {
    my ($qType, $jobID) = @_;
    my $envFile = getEnvFile($qType, $jobID);
    open my $inH, "<", $envFile or die "could not open $envFile for reading: $!\n";
    while(my $line = <$inH>){
        chomp $line;
        $line =~ m|(.+?)$envDelimiter(.*)| or next;
        defined $2 or next;
        $ENV{$1} = $2;
    }
    close $inH;  
}
#=======================================================================

1;

