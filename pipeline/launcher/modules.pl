use strict;
use warnings;

# subs for handling import of command modules into a pipeline's config

# working variables
use vars qw($mainDir);
my $modulesDir = "$mainDir/modules";

#------------------------------------------------------------------------------
# import a called step module
#   - imported command lines appear inline with pipeline.yml after module: key
#   - imported family lines appear at the end of the file
#------------------------------------------------------------------------------
sub addCommandModule {
    my ($file, $line, $prevIndent, $parentIndentLen, $lines, $indents, $addenda) = @_;
    $line =~ m/\s*module:\s+(\S+)/ or throwError("malformed module call:\n    $file:\n    $line");
    my $module = $1;
    my $moduleFile = "$modulesDir/$module/module.yml";

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
    my $inCommand;
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
        if ($line eq 'command:') {
            $inCommand = 1;
            next; # don't need to process this line; parent sets the command name
        } elsif($indent == 0){ # e.g. optionFamilies, condaFamilies
            $inCommand = 0;
        }

        # print command keys with revised indentation to match parent yml
        if ($inCommand) {
            my $revisedIndent = ($nIndent + 1) * $parentIndentLen; # +1 accounts for missing commandName in module.yml
            push @$lines, $line;
            push @$indents, $revisedIndent;
            $$prevIndent = $revisedIndent;
            
        # store optionFamilies and condaFamilies for appending to end of parent yml file
        # can't do immediately, or we could disrupt the parent's commands list
        } else {
            push @$addenda, [$line, $nIndent * $parentIndentLen];
        }
    }
    close $inH;
}

1;

