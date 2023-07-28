#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use File::Path qw(rmtree);

# TODO: extend clean action to singularity containers

#========================================================================
# 'clean.pl' identifies and offers to delete all unused conda environments
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $separatorLength);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiClean { 

    # scan for environment claims
    print "Scanning active pipelines for environment claims...\n";
    my $claims = fillAllEnvironmentClaims();

    # list the currently installed environments
    my @environments = map { -d $_ ? $_ : () } glob("$ENV{MDI_DIR}/environments/*");

    # count claims for each current environment
    my %environments;
    foreach my $environment(@environments){
        my $name = basename($environment);
        $name eq "mamba" and next;
        my $yml = "$ENV{MDI_DIR}/environments/$name/$name.yml";
        if($$claims{$yml}){
            $environments{claimed}{$environment} = $$claims{$yml};
        } else {
            $environments{unclaimed}{$environment}++;
        }
    }

    # list the claimed and unclaimed environments
    print "\nThe following environments are claimed by at least one pipeline and WILL NOT be deleted:\n";
    foreach my $environment(keys %{$environments{claimed}}){
        print "\t$environment\t($environments{claimed}{$environment} claims)\n";
    }
    if(scalar(keys %{$environments{unclaimed}})){
        print "\n\nThe following environments are unclaimed and **WILL BE DELETED**:\n";
        foreach my $environment(keys %{$environments{unclaimed}}){
            print "\t$environment\n";
        }

        # get permission and execute environment deletion
        if(getPermission("Permanently delete the listed conda environments (deletion will take a long time)?")){
            foreach my $environment(keys %{$environments{unclaimed}}){
                rmtree $environment;
            }
        }

    # abort with nothing to do
    } else {
        print "\nThere are no unclaimed environments; nothing to clean.\n\n;"
    }
    exit;
}
sub fillAllEnvironmentClaims {

    # parse tools from directory names
    my @paths = glob("$ENV{MDI_DIR}/suites/*/*/pipelines/*");
    my %pipelines;
    foreach my $path(@paths){
        -d $path or next;
        my @path = split('/', $path);
        my $pipeline = $path[$#path];
        $pipeline =~ m/^_/ and next; 
        my $fork  = $path[$#path - 3];
        my $suite = $path[$#path - 3 + 1];
        $pipelines{"$suite/$pipeline"}++;
    }

    # fill claims of each unique pipeline
    my %claims;
    foreach my $pipeline(keys %pipelines){
        fillPipelineEnvironmentClaims($pipeline, \%claims);
    }
    return \%claims;
}
sub fillPipelineEnvironmentClaims {
    my ($pipeline, $claims) = @_;
    foreach my $version(qw(latest main)){
        print "  $pipeline:$version\n";
        open my $inH, "-|", "$ENV{MDI_DIR}/mdi $pipeline conda --version $version --list 2>&1" or die "fatal error in clean listPipelineActions()\n";
        while (my $line = <$inH>){
            if($line =~ m/^error:/){
                print "    !!! ERROR: local changes to one or more suite files would be overridden by checkout\n";
                last;
            }
            chomp $line;
            $line =~ m/\.yml$/ and $$claims{$line}++;
        }            
        close $inH;
    }
}
#========================================================================

1;
