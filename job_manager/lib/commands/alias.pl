#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# create an alias, i.e., named shortcut, to this MDI program target
# can have multiple aliases to the same mdi target, but only one alias of a given name
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
my $aliasTag = "# written by MDI alias\n";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiAlias { 

    # parse the options and apply defaults
    my $alias = $options{'alias'} || "mdi";
    my $profileFile = $options{'profile'} || "~/.bashrc";
    my $outLine = "alias $alias=\"$ENV{MDI_DIR}/mdi $aliasTag\"";

    # check the profile file path
    -f $profileFile or throwError("file not found:\n    $profileFile", 'alias');

    # get user permission to modify their profile
    getPermissionGeneral(
        "The following line:\n".
        "    $outLine\n".  
        "will be written to file:\n".
        "    $profileFile\n"
    ) or exit;

    # collect the contents of the current file as an array of lines
    my @profile;    
    open my $inH, "<", $profileFile or die "could not read file: $profileFile: $1\n";
    while (my $line = <$inH>){
        $line eq $outLine and exit; # nothing to do, exit quietly
        if($line =~ m/^alias\s+$alias=/){ 
            getPermissionGeneral(
                "Alias '$alias' already exists and will be overwritten from:\n". 
                "    $line\n".
                "to:\n".
                "    $outLine\n"
            ) or exit;
            push @profile, $outLine; 
        } else {
            push @profile, $line;
        }
    }
    close $inH;

    # print the new file
    print join("", @profile);
}
#========================================================================

1;
