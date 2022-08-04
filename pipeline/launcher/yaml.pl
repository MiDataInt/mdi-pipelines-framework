use strict;
use warnings;

# generic subs for loading simple YAML files (instead of requiring YAML::Tiny)
# only handles definitions in the following forms
# supports a simplified subset of YAMl:
#    # a comment
#    key: value # a single key-value pair
#    key:
#        key: value # nested keys
#        key: # an array of values
#            - value1
#            - value2
#        key: [value3, value4] # another array of values

use constant {
    KEYED => 'KEYED',
    ARRAY => 'ARRAY',
    #------------
    TYPE => 0,
    KEY => 1,
    VALUE => 2,
    PRIORITY => 3,
    LINE_NUMBER => 4
};
my $errorSeparator = "!" x 80; # since this script may be called separately from others

# read a single simplified YAML file
sub loadYamlFile { # despite the name, also loads YAMl from a string reference
    my ($yml, $priority, $returnParsed, $fillModules, $suppressNull) = @_;
    my $errorFile = ref($yml) ? "" : ":\n    $yml";

    # first pass: read simplified lines from YAML
    open my $inH, "<", $yml or throwError("could not open YAML$errorFile:\n$!");    
    my ($prevIndent, $indentLen, @lines, @indents, @addenda) = (0);
    while (my $line = <$inH>) {
        # read the config line internal to the YAML
        $line = trimYamlLine($line) or next; # ignore blank lines
        $line =~ m/^(\s*)/;
        my $indent = length $1;
        $line =~ s/^\s+//g;
        push @lines, $line;
        push @indents, $indent;
        !defined $indentLen and $indent > 0 and $indentLen = $indent;
        $indent <= $prevIndent or $indent == $prevIndent + $indentLen or throwError(
            "bad indentation in yml$errorFile\n".
            "please use a constant number of spaces for progressive indentation"
        );
        $indentLen and $indent % $indentLen and throwError("inconsistent indenting in yml$errorFile");
        $prevIndent = $indent;

        # implicitly incorporate invoked action modules
        $fillModules and $indentLen and $indent == 2 * $indentLen and $line =~ m/^module:/ and
            addActionModule($yml, $line, \$prevIndent, $indentLen, \@lines, \@indents, \@addenda);  
    }
    close $inH;
    
    # if modules added any lines for the end (e.g., optionFamilies, add them now)
    foreach my $line(@addenda) {
        push @lines, $$line[0];
        push @indents, $$line[1];
    }

    # record the indent levels of all lines
    $indentLen or $indentLen = 4; # for YAML that has no indented elements
    my @levels = map { $_ / $indentLen } @indents;  

    # adjust non-indented yaml array format to indented (i.e., expect indent of "-" items under a dictionary)
    my $lastDictionaryI = 0;
    foreach my $i(0..$#lines){
        if($lines[$i] =~ m/^-/){
            $levels[$i] == $levels[$lastDictionaryI] or next;
            $levels[$i]++;
        } else {
            $lastDictionaryI = $i;
        }
    }
    
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
            $value = getYamlValue($line, $suppressNull); # always returns an array reference
            defined $value or next; # discard items without any value
            push @$array, $$value[0];
            $returnParsed and push @parsed, [ 
                ARRAY,
                join(":", @keys[0..($level-1)]),
                defined $$value[0] ? $$value[0] : 'null',
                $priority,
                $i
            ];

        # keyed values
        } elsif($i == $#lines or $levels[$i+1] <= $level){
            $line =~ s/\s+/ /g;
            ($key, $value) = $line =~ m/(.+):$/ ? ($1) : split(': ', $line, 2);
            $value = getYamlValue($value, $suppressNull); # always returns an array reference
            defined $value or next; # discard keys without any value
            $hashes[$level]{$key} = $value;
            if ($returnParsed) {
                my $keys = $level >= 0 ? join(":", @keys[0..($level-1)], $key) : $key;
                push @parsed, [
                    KEYED,
                    $keys,
                    defined $value ? $value : 'null',
                    $priority,
                    $i
                ];
            }

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
            $returnParsed and $keys[$level] = $key;
        } 
    }
    
    # return the yaml hash; optionally including parsed strings suitable for YAML merging
    $returnParsed and $yaml{parsed_} = \@parsed;
    \%yaml;
}

# clean up input lines to yield pure, still-indented YAML
sub trimYamlLine {
    my ($str, $trimLeading) = @_;
    defined($str) or return $str;
    chomp $str;
    $str =~ s/\r//g;                     # Windows-safe
    $str eq '---' and return "";         # ignore YAML leader line
    $str eq '...' and return "";         # ignore YAML end line
    $str =~ m/^\s*#/ and return "";      # ignore comment lines
    $str =~ m/(.+)\s*#(^")*/ and $str = $1; # strip trailing comments        
    $str =~ s/\s+$//g;                   # trim trailing whitespace
    $trimLeading and $str =~ s/^\s+//g;  # trim leading whitespace if requested
    $str =~ s/\@/\\\@/g;                 # prevent unintended interpolation of @ symbols in values
    $str;
}

# convert special YAML value labels into Perl-compatibles
sub getYamlValue {
    my ($value, $suppressNull) = @_;
    defined($value) or return;
    $value =~ s/^\s+//g;  # trim leading whitespace    
    $value eq '' and return;
    if ($value eq '~' or
        lc($value) eq 'null' or
        $value eq '_REQUIRED_') {
        $suppressNull ? undef : []
    } elsif(lc($value) eq "true" or lc($value) eq "yes") { # boolean to perl 1/0
        [1]   
    } elsif(lc($value) eq "false" or lc($value) eq "no") {
        [0]  
    } elsif($value =~ m/^\[(.*)\]$/) { # handle [] array format 
        [ map { getYamlValue($_) } split(",", $1) ]; 
    #} elsif($value =~ m/^\{(.*)\}$/) { # handle {} dictionary/hash format 
    #    { map {
    #        $_ =~ s/\s+/ /g;
    #        my ($key, $value) = split(': ', $_, 2);
    #        $key => getYamlValue($value)
    #    } split(",", $1) };  
    # TODO: enable system calls via bash-alikes
    } else { # everything else passes as is (no distinction between number and string) 
        [$value]
    }
}

# nest all keys in parsed yaml under a set of caller provided keys
# e.g., make input 'KEY:1' become output 'X:Y:KEY:1'
sub prependYamlKeys {
    my ($yml, @keys) = @_;
    foreach my $x(@{$$yml{parsed_}}){
        $$x[1] = join(":", @keys, $$x[1]);
    }
}

# merge multiple YAML read by loadYamlFile with $returnParsed = TRUE
sub mergeYAML {
    my (@yamls) = @_;
    
    # use loadYamlFile $priority to resolve duplicated parameters
    # higher-numbered priorities take precedence
    my @parsed;
    foreach my $yaml(@yamls){ $$yaml{parsed_} and push @parsed, @{$$yaml{parsed_}} }
    @parsed or return {};
    @parsed = sort { $$a[KEY] cmp $$b[KEY] or 
                     $$a[PRIORITY] <=> $$b[PRIORITY] or 
                     $$a[LINE_NUMBER] <=> $$b[LINE_NUMBER]} @parsed; # to preserve array order
    my %collapsed;
    foreach my $line(@parsed){
        if ($$line[TYPE] eq KEYED) { $collapsed{$$line[KEY]} = $$line[VALUE] }
        else { push @{$collapsed{$$line[KEY]}}, $$line[VALUE] }   
    }

    # expand keys to nested YAML hash
    my %yaml;
    foreach my $key(sort keys %collapsed){
        my $value = $collapsed{$key}; # always an array reference
        $key =~ s/:/"}{"/g;
        my $expr = join("", '$yaml{"', $key, '"}');
        @$value or @$value = ('null');
        my @values = map {
            $_ eq '' and $_ = 'null';
            $_ =~ s/\$/\\\$/g; # make sure that $VAR_NAME stays escaped
            $_ =~ s/\"/\\\"/g; # make sure that double quote persists
            '"'.$_.'"'
        } @$value;
        $expr = join(" ", $expr, ' = ', '['.join(",", @values).']');            
        eval $expr;
    }
    \%yaml;
}

# print YAML hash to a bare bones .yml file
sub printYAML {
    my ($yaml, $ymlFile, $comment, $stdout, @primaryKeys) = @_;
    our $outH;
    if($stdout){
        $outH = *STDOUT;
    } else {
        open $outH, ">", $ymlFile or throwError("could not open for writing:\n    $ymlFile\n$!");
    }
    sub printYAML_ { # recursively write the revised lines
        my ($x, $indentLevel) = @_;
        my $indent = " " x ($indentLevel * 4);
        if (ref($x) eq "HASH") {
            foreach my $key(sort keys %$x){
                print $outH "\n", $indent, "$key:"; # keys
                printYAML_($$x{$key}, $indentLevel + 1);
            }
        } elsif(@$x == 1){ # single keyed values
            my $value = $$x[0];
            defined $value or $value = "null";
            $value eq '' and $value = "null";
            print $outH " $value"; 
        } else { # arrayed values
            foreach my $value(@$x){ print $outH "\n$indent- $value" }
        }  
    }
    $comment or $comment = "";
    print $outH "\n", $comment, "\n";
    print $outH "\n---";
    if(@primaryKeys){ # allow caller to force the order of the primary yaml keys
        foreach my $key(@primaryKeys){ 
            $$yaml{$key} or next;
            print $outH "\n$key:";
            printYAML_($$yaml{$key}, 1); 
        }
    } else {
        printYAML_($yaml, 0);
    }
    print $outH "\n\n";
    close $outH;
}

1;
