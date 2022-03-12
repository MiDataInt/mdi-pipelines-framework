use strict;
use warnings;

#========================================================================
# 'top.pl' run the 'top' system monitor on the host running a job as $USER
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($pipelineOptions);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qTop { 
    $pipelineOptions = "top -u $ENV{USER}";
    qSsh('top');
}
#========================================================================

1;
