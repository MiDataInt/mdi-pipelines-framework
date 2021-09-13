
# Michigan Data Interface

The Michigan Data Interface (MDI) is a framework for developing,
installing and running a variety of HPC data analysis pipelines
and interactive R Shiny data visualization applications
within a standardized design and implementation interface.

## Organization and contents

### MDI code stages

Data analysis in the MDI is logically separated
into two stages of code execution called Stage 1 HPC **pipelines**
and Stage 2 web applications (i.e., **apps**).

### Repository contents

This is the repository for the **MDI pipelines
framework**. We use 'pipeline' synonymously with 'workflow' to 
refer to a series of analysis actions coordinated by scripts.

**Stage 1 pipelines** are generally:

- sample autonomous, i.e., they are executed "per sample"
- executed only once on an input data set, not iteratively
- executed the same way on every sample, regardless of the experiment
- hands-off, i.e. not interactive
- resource intensive, in storage and/or CPU needs
- executed on a high-performance compute (HPC) cluster
- dependent on large input data files
- capable of producing small output data files suitable for Stage 2 apps

Although the above properties are not hard-and-fast rules, 
they collectively make Stage 1 pipelines well suited to being 
run by a core facility or data producer according to agreed upon best
practices. They are also ideal for a cluster server, which the
'mdi' command line utility helps manage. 

Common examples of Stage 1 pipelines are read alignment to
a genome, bulk image processing, and training of machine
learning algorithms.

The pipelines framework does not encode
the data analysis pipelines themselves, which are found in other
code repositories called 'pipelines suites'. Instead, the pipelines
frameworks encodes script utilities that:

- allow simple YAML configuration files to be used to define a pipeline
- wrap pipelines into a friendly command-line executable function
- coordinate pipeline job submission to HPC schedulers

## Installation and usage

### Web-based pipeline execution via the MDI server

The preferred way to use the MDI pipelines is via the 
MDI manager utility found here:

https://github.com/MiDataInt/mdi

which will allow you to configure and run pipelines via a web
interface for greatest clarity and ease.

### Command line pipeline execution

As a robust alternative to using the web interface, you can
also execute all pipelines using the 'mdi' command line
helper function. To do so, you must still install the MDI
using the steps in the 'MiDataInt/mdi' repository above.
Then, simply close and reopen your command shell and type:

```
mdi
```

which will provide help information on using the command line 
utility to run and queue pipeline jobs.

### Prerequisites

Only two specialized programs are required to run pipelines:
git and conda. Git is always available on Great Lakes,
and conda can be loaded with:

```
module load python3.7-anaconda
```

On other systems, install git and conda as needed:

https://git-scm.com/book/en/v2/Getting-Started-Installing-Git  
https://docs.conda.io/en/latest/miniconda.html

If you use the job manager utility to submit pipeline jobs
on a cluster server (recommended), you need to work on a
Linux server running the bash command shell.

## General pipeline organization

As noted above, pipelines are defined by code in
other pipelines suite repositories following the
structure provided by the framework in this repository.
Some of the general properties expected of pipelines are
enumerated here.

All pipelines use conda to construct an appropriate execution
environment with proper versions of all required program
dependencies, for explicit version control, reproducibility
and portability. These might include any program called from 
the command line or a shell script to do data analysis work.

Wherever possible, pipeline default configurations are set
for immediate use on the
[UM Great Lakes](https://arc-ts.umich.edu/greatlakes/)
server cluster, but simple configurations allow them to run
on any Linux-compatible computer.

## Job configuration files (specifying pipeline options)

You may provide all options through the command line 
as you would for any typical program.  Use '--help' to
see the available options. 

However, we recommend instead writing a '<myData>.yml'
configuration file to set options, and then providing
the path to that file to the pipeline. This makes
it easy to assemble jobs and to keep a history of what
was done, especially if you use our job manager.

Config files are valid YAML files, although the interpeter
we use to read them only processes a subset of YAML features.
Learn more about YAML on the internet, or just proceed, it is
intuitive and easy.

### Config file templates

To get a template to help you write your config file
(you can also copy it from the report of jobs you ran previously),
use:

```
mdi <pipelineName> template --help
mdi <pipelineName> template -a -c
```

In general, the syntax is:

```
# <myData>.yml
---
pipeline: pipelineName
variables:
    VAR_NAME: value
pipelineCommand:
    optionFamily:
        optionName1: $VAR_NAME # a single keyed option value
        optionName2:
            - valueA # an array of option values, executed in parallel
            - valueB
execute:
    - pipelineCommand
```

As a convenience for when you get tired of have many files
with the same option values (e.g. a data directory), you may
also create a file called 'pipeline.yml' or '<pipelineName.yml>'
in the same directory as '<myData.yml>'. Options will be read
from 'pipeline.yml' first, then '<myData.yml>', then finally
from any values you specific on the commands line, in that
order of precedence.

