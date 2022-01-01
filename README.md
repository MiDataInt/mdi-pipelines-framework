# Michigan Data Interface

The [Michigan Data Interface](https://midataint.github.io/) (MDI) 
is a framework for developing, installing and running a variety of 
HPC data analysis pipelines and interactive R Shiny data visualization 
applications within a standardized design and implementation interface.

Data analysis in the MDI is separated into 
[two stages of code execution](https://midataint.github.io/docs/analysis-flow/) 
called Stage 1 HPC **pipelines** and Stage 2 web applications (i.e., **apps**).
Collectively, pipelines and apps are referred to as **tools**.
Please read the [MDI documentation](https://midataint.github.io/) for 
more information.

## Repository contents

This is the repository for the **MDI pipelines framework**. 
We use 'pipeline' synonymously with 'workflow' to 
refer to a series of analysis actions coordinated by scripts.

The pipelines framework does not encode the data analysis pipelines themselves, 
which are found in other code repositories called 'tool suites'
created from our suite repository template:

- <https://github.com/MiDataInt/mdi-suite-template>

Instead, the pipelines frameworks encodes script utilities that:

- allow simple YAML configuration files to be used to define a pipeline
- wrap pipelines into a friendly command-line executable function
- coordinate pipeline job submission to HPC schedulers

## Installation and usage

This repository is not used directly. Instead, it is cloned
and managed by the MDI installer and manager utilities found here:

- <https://github.com/MiDataInt/mdi>
- <https://github.com/MiDataInt/mdi-manager>

Please follow the instructions in those repositories, being sure
to add the tool suites you wish to use to your MDI installation.
