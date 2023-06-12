use strict;
use warnings;

# generic subs for loading simple YAML files (instead of requiring YAML::Tiny)

# working variables
my $keepLogical; # do not convert true/false to perl 0/1

# read a single simplified YAML file
sub loadYamlFromString {
    my ($str, $keepLogical_) = @_;
    $keepLogical = $keepLogical_;
    $str =~ m/^\s*---/ or $str = "---\n$str";
    open my $inH, "<", \$str or throwError("could not open yml string:\n$!");

    # first pass: read simplified lines from files
    my ($prevIndent, $indentLen, @rawYamls, @lines, @indents, @indentLens) = (0);
    my ($yamlI, $inYaml) = (-1);
    while (my $line = <$inH>) {
        chomp $line;
        if($line eq '---'){
            ($prevIndent, $indentLen) = (0);            
            $yamlI++; # expect input to potentially have mutliple yaml blocks
            $inYaml = 1;
            push @{$rawYamls[$yamlI]}, $line;
            next;
        }
        if($line eq '...'){
            push @{$rawYamls[$yamlI]}, $line;
            $inYaml = 0;
            next;
        }
        $inYaml or next;
        push @{$rawYamls[$yamlI]}, $line;        
        $line = trimYamlLine($line) or next; # ignore blank lines        
        $line =~ m/^(\s*)/;
        my $indent = length $1;
        $line =~ s/^\s+//g;
        push @{$lines[$yamlI]}, $line;
        push @{$indents[$yamlI]}, $indent;
        if(!defined $indentLen and $indent > 0){
            $indentLen = $indent;
            $indentLens[$yamlI] = $indentLen;
        }
        $indent <= $prevIndent or $indent == $prevIndent + $indentLen or throwError(
            "bad indentation in yml string:\n".
            "please use a constant number of spaces for progressive indentation"
        );
        $prevIndent = $indent;
    }
    close $inH;
    
    # process each yaml block
    my @yamls;
    foreach my $yamlI(0..$#lines){
        my @lines   = @{$lines[$yamlI]};
        my @indents = @{$indents[$yamlI]};
        my $indentLen = $indentLens[$yamlI] || 1;
 
        # record the indent levels of all lines
        my @levels = map { $_ / $indentLen } @indents;    
        
        # second pass: parse simplified YAML lines
        my @hashes = (\my %yaml);
        my ($array, @keys, @parsed);
        foreach my $i(0..$#lines){
            my $line  = $lines[$i];
            my $level = $levels[$i];
            my ($key, $value);    
            
            # arrayed values, - format
            if ($line =~ m/^-/) {
                $line =~ s/^-//;
                $line =~ s/\s+/ /g;
                $value = getYamlValue($line); # always returns an array reference
                defined $value or next; # discard items without any value
                push @$array, $$value[0];
    
            # keyed values
            } elsif($i == $#lines or $levels[$i+1] <= $level){
                $line =~ s/\s+/ /g;
                ($key, $value) = $line =~ m/(.+):$/ ? ($1) : split(': ', $line, 2);
                $value = getYamlValue($value); # always returns an array reference
                defined $value or next; # discard keys without any value
                $hashes[$level]{$key} = $value;
    
            # nested hashes
            } else {
                $key = (split(':', $line))[0];
                if ($lines[$i+1] =~ m/^-/) {
                    $hashes[$level]{$key} = [];
                    $array = $hashes[$level]{$key};
                } else {
                    $hashes[$level]{$key} = {};
                    $hashes[$level + 1] = $hashes[$level]{$key}; 
                }
            } 
        }
        push @yamls, \%yaml;
    }

    # return the yaml hashes
    {raw => \@rawYamls, parsed => \@yamls};
}

# clean up input lines to yield pure, still-indented YAML
sub trimYamlLine {
    my ($str, $trimLeading) = @_;
    defined($str) or return $str;
    chomp $str;
    $str =~ s/\r//g;                     # Windows-safe
    $str =~ m/^\s*#/ and return "";      # ignore comment lines
    $str =~ m/(.+)\s*#(^")*/ and $str = $1; # strip trailing comments        
    $str =~ s/\s+$//g;                   # trim trailing whitespace
    $trimLeading and $str =~ s/^\s+//g;  # trim leading whitespace if requested
    $str =~ s/\@/__AT_SYMBOL__/g;                 # prevent unintended interpolation of @ symbols in values
    $str;
}

# convert special YAML value labels into Perl-compatibles
sub getYamlValue {
    my ($value) = @_;
    defined($value) or return;
    $value =~ s/^\s+//g;  # trim leading whitespace    
    $value eq '' and return;
    if ($value eq '~' or
        lc($value) eq 'null' or
        $value eq '_REQUIRED_') {
        []
    } elsif((lc($value) eq "true"  or lc($value) eq "yes") and !$keepLogical) { # boolean to perl 1/0
        [1]   
    } elsif((lc($value) eq "false" or lc($value) eq "no")  and !$keepLogical) {
        [0]  
    } elsif($value =~ m/^\[(.*)\]$/) { # handle [] array format 
        [ map { getYamlValue($_) } split(",", $1) ]; 
    } else { # everything else passes as is (no distinction between number and string) 
        [$value]
    }
}

1;

