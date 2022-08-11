# MDI Pipelines Framework

The [Michigan Data Interface](https://midataint.github.io/) (MDI) 
is a framework for developing, installing and running 
Stage 1 HPC **pipelines** and Stage 2 interactive web applications 
(i.e., **apps**) in a standardized design interface.

This is the repository for the **MDI pipelines framework**. 
We use 'pipeline' synonymously with 'workflow' to 
refer to a series of analysis actions coordinated by scripts.

The pipelines framework does not encode the data analysis pipelines themselves, 
which are found in other code repositories called 'tool suites'
created from our suite repository template:

- tool suite template: <https://github.com/MiDataInt/mdi-suite-template>

Instead, the pipelines framework encodes scripts that:

- allow YAML configuration files to be used to define a pipeline
- wrap pipelines into a common command-line executable 
- coordinate pipeline job submission to HPC schedulers

## Installation and use

This repository is not used directly. Instead, it is cloned
and managed by the MDI installer and manager utilities found here:

- MDI Desktop app: <https://github.com/MiDataInt/mdi-desktop-app>
- MDI installation script: <https://github.com/MiDataInt/mdi>
- MDI manager R package: <https://github.com/MiDataInt/mdi-manager>
