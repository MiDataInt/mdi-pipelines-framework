use strict;
use warnings;

#========================================================================
# 'start.pl' shows the estimated start time of all pending jobs queued by a job file
# based on a system call to Slurm's `squeue --start`
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($qType $pipelineOptions %deletable);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qStart { 
    if($qType eq "slurm"){
        updateStatusFiles();

        # report the current time as a convenience
        my ($sec, $min, $hour, $day, $month, $year) = localtime();
        my $fmonth = sprintf("%02d", $month + 1);
        my $fyear = $year + 1900;
        print "\nthe current time is: $fyear-$fmonth-$day $hour:$min\n\n";

        # parse the header
        open my $inH, "-|", "squeue --start";
        my $header = <$inH>;
        $header =~ s/^\s+|\s+$//;
        my $i = 0;
        my %header = map { $_ => $i++ } split(/\s+/, $header);
        print join("\t", "JOBID\t", "START_TIME\t", "NODE(S)"), "\n";

        # parse start lines for pending jobs, which will be 1) on the start list, and 2) deletable by the job file
        while(my $line = <$inH>){
            chomp $line;
            $line =~ s/^\s+|\s+$//;
            my @line = split(/\s+/, $line);
            my $jobId = $line[$header{JOBID}];     
            $deletable{$jobId} or next; 
            my $startTime = $line[$header{START_TIME}];
            if($startTime =~ m/(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/){
                my ($jyear, $jmonth, $jday, $jhour, $jmin, $jsec) = ($1, $2, $3, $4, $5, $6);
                $startTime = "$jyear-$jmonth-$jday $jhour:$jmin";
            }            
            my $nodes = $line[$header{SCHEDNODES}];
            $nodes eq "(null)" and $nodes = "";
            print join("\t", $jobId, $startTime, $nodes), "\n";
        }
    } else {
        print STDERR "command 'start' is only available for the Slurm job scheduler\n";
    }
}
#========================================================================

1;
