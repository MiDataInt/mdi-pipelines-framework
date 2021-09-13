use strict;
use warnings;

# working variables
use vars qw(%options);

#========================================================================
# system utility subroutines
#------------------------------------------------------------------------
sub slurpFile {  # read the entire contents of a disk file into memory
    my ($file) = @_;
    local $/ = undef; 
    open my $inH, "<", $file or die "could not open $file for reading: $!\n";
    my $contents = <$inH>; 
    close $inH;
    return $contents;
}
#------------------------------------------------------------------------
sub getTime { # status update times
    my ($sec, $min, $hr, $day, $month, $year) = localtime(time);
    $year = $year + 1900;
    $month++;
    return "$month/$day/$year $hr:$min:$sec";
}
#------------------------------------------------------------------------
sub getPermission {  # get permission for jobs that will duplicate a job or delete/overwrite a file
    my ($queryMessage, $noForceUpdate) = @_;
    $options{'force'} and return 1;  # user has already given permission at command line
    print "\nWARNING!\n"."$queryMessage\n";
    print "continue? <yes or no>:  ";
    my $permission = <STDIN>;
    chomp $permission;
    $permission = "\U$permission";
    ($permission eq 'YES' or $permission eq 'Y') or return undef;
    $noForceUpdate or $options{'force'} = 1;  # granting permission is synonymous with setting --force
    return 1;      
}
#========================================================================

1;

