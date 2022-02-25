use strict;
use warnings;

# subs for handling import of action modules into a pipeline's config

# working variables
use vars qw($mdiDir);
my $modulesDir = "$mdiDir/modules";

#------------------------------------------------------------------------------
# import a called action module
#   - imported action lines appear inline with pipeline.yml after module: key
#   - imported family lines appear at the end of the file
#------------------------------------------------------------------------------
sub addActionModule {
    my ($file, $line, $prevIndent, $parentIndentLen, $lines, $indents, $addenda) = @_;
    $line =~ m/\s*module:\s+(\S+)/ or throwError("malformed module call:\n    $file:\n    $line");
    my $moduleFile = getSharedFile($modulesDir, "$1/module.yml", 'module', 1);

    # discover the indent length of the module file (could be different than parent)
    open my $inH, "<", $moduleFile or throwError("could not open:\n    $moduleFile:\n$!");    
    my $moduleIndentLen;
    while (!$moduleIndentLen and my $line = <$inH>) {
        $line = trimYamlLine($line) or next; # ignore blank lines
        $line =~ m/^(\s*)/;
        my $indent = length($1);
        $indent > 0 and $moduleIndentLen = $indent;
    }
    close $inH;
    $moduleIndentLen or throwError("malformed module file, no indented lines:\n    $moduleFile");
    
    # read module.yml lines
    my $inAction;
    open $inH, "<", $moduleFile or throwError("could not open:\n    $moduleFile:\n$!");
    while (my $line = <$inH>) {
        
        # get this lines indentation
        $line = trimYamlLine($line) or next; # ignore blank lines
        $line =~ m/^(\s*)/;
        my $indent = length($1);
        $indent % $moduleIndentLen and throwError("inconsistent indenting in file:\n    $moduleFile");
        my $nIndent = $indent / $moduleIndentLen;    
    
        # determine which block type we are in
        $line =~ s/^\s+//g;
        if($line =~ m/^version:/){ # ignore version key, used for internal tracking only
            next;  
        } elsif ($line eq 'action:') {
            $inAction = 1;
            next; # don't need to process this line; parent sets the action name
        } elsif($indent == 0){ # e.g., optionFamilies, condaFamilies definition sections
            $inAction = 0;
        }

        # print action keys with revised indentation to match parent yml
        if ($inAction) {
            my $revisedIndent = ($nIndent + 1) * $parentIndentLen; # +1 accounts for missing action name in module.yml
            push @$lines, $line;
            push @$indents, $revisedIndent;
            $$prevIndent = $revisedIndent;
            
        # store optionFamilies and condaFamilies for appending to end of parent yml file
        # can't do immediately, or we could disrupt the parent's actions list
        } else {
            push @$addenda, [$line, $nIndent * $parentIndentLen];
        }
    }
    close $inH;
}

1;
