#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'add.pl' adds one tool suite repository to config.yml and re-installs the MDI
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
my $leader = "---
#----------------------------------------------------------------------
# MDI tool suites to install
#----------------------------------------------------------------------
#   - entries should point to GitHub repositories
#   - developers should _not_ list their repo forks here
#   - when a pipeline/app name is in multiple suites, the first match is used
#----------------------------------------------------------------------
# !! Re-run 'mdi::install()' or 'mdi install' after updating this list !!
#----------------------------------------------------------------------
suites:\n";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiAdd { 
    my $newSuite = stripGitUrl( $options{'suite'} );

    # if needed, modify config.yml to include the requested tool suite
    my $suitesFile = "$ENV{MDI_DIR}/config/suites.yml";
    my $yamls = loadYamlFromString( slurpFile($suitesFile) );
    my $suites = $$yamls{parsed}[0]{suites};
    $suites or $suites = [];
    my $suiteExists;
    foreach my $suite(@$suites){
        $suite = stripGitUrl( $suite );
        $newSuite eq $suite and $suiteExists = 1;
    }
    if(!$suiteExists){
        push @$suites, $newSuite;
        open my $outH, ">", $suitesFile or die "could not open $suitesFile for writing: $!\n";
        print $outH $leader;
        foreach my $suite(@$suites){
            print $outH "  - $suite\n";
        }
        print "\n";
        close $outH;
    } 

    # run the complete installation process
    my $installPackages = $options{'install-packages'} ? "TRUE" : "FALSE";
    exec "Rscript -e 'mdi::install(\"$ENV{MDI_DIR}\", ".
         "installPackages = $installPackages, confirm = FALSE, addToPATH = FALSE, ".
         "clone = TRUE, force = FALSE)'";
}
sub stripGitUrl {
    my ($suite) = @_;
    $suite =~ s/^https:\/\/github.com\///;
    $suite =~ s/\.git$//;
    $suite;
}
#========================================================================

1;
