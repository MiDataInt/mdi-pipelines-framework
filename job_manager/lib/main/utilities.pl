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
    ($options{'force'} or $ENV{IS_PIPELINE_RUNNER}) and return 1;  # user has already given permission at command line
    print "\nWARNING!\n"."$queryMessage\n\n";
    $ENV{IS_PIPELINE_RUNNER} and return 1;
    print "Continue? [y|N]: ";
    my $permission = <STDIN>;
    chomp $permission;
    $permission = "\U$permission";
    ($permission eq 'YES' or $permission eq 'Y') or return undef;
    $noForceUpdate or $options{'force'} = 1;  # granting permission is synonymous with setting --force
    return 1;      
}
sub getPermissionGeneral {
    my ($msg, $suppressDie) = @_;
    my $leader = "-" x 80;
    print "\n$leader\n$msg\n";  
    print "Continue? [y|N]: ";
    my $permission = <STDIN>;
    chomp $permission;
    $permission = "\U$permission";
    ($permission eq 'YES' or $permission eq 'Y') and return 1;
    $suppressDie and return undef;
    print "aborting with no action taken\n\n";
    exit 1;
}
sub getUserSelection {
    my ($msg, $default, $noPrompt, @allowed) = @_;
    my $leader = "-" x 80;
    print STDERR "\n$leader\n$msg";  
    $noPrompt or print STDERR "\nPlease enter your selection by its number (e.g., 1): ";
    my $selection = <STDIN>;
    chomp $selection;
    $selection eq "" and defined $default and $selection = $default;
    if($selection eq ""){
        print STDERR "\naborting with no action taken\n\n";
        exit 1;
    } elsif(@allowed) {
        my %allowed = map { $_ => 1} @allowed;
        $allowed{$selection} and return $selection;
        print STDERR "\nunrecognized selection\naborting with no action taken\n\n";
        exit 1;
    } else {
        return $selection;
    }
}
#========================================================================

1;
