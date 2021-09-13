use strict;
use warnings;

#========================================================================
# 'protect.pl' add and removes write permission for designated data output files
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $masterFile $getOutputFiles);
our %protectFileGlobs;
#========================================================================

#========================================================================
# main execution blocks
#------------------------------------------------------------------------
sub qProtect { # remove write permission for all classes
    getOutputFiles('protect');
    callChmod('a', '-', 'protected', 'protecting');
}
sub qUnprotect { # add write permission for --who
    getOutputFiles('unprotect');
    callChmod($options{'who'}, '+', 'unprotected', 'unprotecting');
}
#========================================================================

#========================================================================
# write protection subs
#------------------------------------------------------------------------
sub getOutputFiles { # scan instructions for files marked for protection/backup
    my ($action) = @_;
    $getOutputFiles = 1;
    $options{'_suppress-echo_'} = 1;
    $action and print "scanning for files to $action\n"; 
    executeInstructions( getEnvFiles('q') ); 
    initializeAutoThread('pre');    
    initializeAutoThread('main');    
    executeInstructions($masterFile); 
    initializeAutoThread('post');   
}
#------------------------------------------------------------------------
sub callChmod { # execute permission change
    my ($classes, $operator, $actioned, $actioning) = @_;
    $classes =~ s/,//g; # in case user used comma-delimited class list
    checkClasses($classes);
    my $chmod = "chmod $classes$operator"."w";
    if($options{'dry-run'}){
        $options{'quiet'} or print "the following files will be write $actioned ($chmod)\n";
    } else {
        print "write $actioning files ($chmod)\n";
    }
    foreach my $fileGlob(sort {$a cmp $b} keys %protectFileGlobs){
        $options{'quiet'} or print "  $fileGlob\n";
        unless($options{'dry-run'}){
            if($fileGlob =~ m/^find .+/){ # allow use of find instead of file glob; protect against unspecified global find
                qx/$fileGlob -print0 | xargs -0 $chmod/;   
            } else {
                qx/$chmod $fileGlob/;   
            }
        }
    }
}
sub checkClasses { # make sure --who provides valid chmod classes
    my ($classes) = @_;
    $classes =~ s/[a|u|g|o]//g;
    length($classes) and die "unrecognized chmod classes in --who\n".
                           "valid classes are:\n".
                           "  u=user\n".
                           "  g=group\n".
                           "  o=other\n".
                           "  a=all\n";
}
#------------------------------------------------------------------------
sub isProtectedOutput {  # determine whether output files to be protected already exist in a write-protected state from a prior run
    foreach my $fileGlob(keys %protectFileGlobs){
        my $ls = $fileGlob =~ m/^find .+/ ? 
                 "$fileGlob | xargs -I FILE ls -l FILE" : 
                 "ls -l $fileGlob 2>/dev/null";
        qx/$ls | awk 'BEGIN{FS=""}\$3=="-"{print 1; exit}'/ and return 1;  # return true if any file is write protected
    }
}
#========================================================================

1;

