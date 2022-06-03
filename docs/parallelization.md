---
title: Parallelization
has_children: false
nav_order: 40
---

## {{page.title}}

We encourage you to use modern parallelization techniques 
in your pipeline code to promote efficient data analysis.

### Array jobs
A first level of parallelization is implicit to the structure
and interpretation of MDI job configuration files, where is
it is easy for users to create 
[array jobs](/mdi/docs/job_config_files.html#option-recycling---parallel-array-jobs). 
This is functionality is automatically provided to all pipelines by the framework.


### Parallel jobs

A second level of parallelization is specified in pipeline.yml
configuration files via
[parallel execution threads](/mdi-suite-template/docs/pipelines/pipeline_yml.html#execution-threads), which allow different pipeline actions to be run
in parallel jobs.

### Parallelization resources available to action scripts

Finally, and most importantly, the pipelines framework automatically adds 
two options to all pipelines that give users a consistent nomenclature 
for communicating the resources they have allocated to a pipeline job.


- **-p,--n-cpu** = <integer> number of CPUs used for parallel processing
- **-r,--ram-per-cpu** = <string> RAM allocated per CPU (e.g., 500M, 4G)

These and other job options are 
[transformed into environment variables](/mdi-pipelines-framework/environment_variables.html/)
such as N_CPU. You should use those environment variables in your pipeline code to determine the extent of parallelization and memory available to your programs, e.g.

```bash
sort --parallel ${N_CPU} --buffer-size ${TOTAL_RAM_INT}b
```
