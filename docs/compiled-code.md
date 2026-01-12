---
title: Compiled Code
has_children: false
nav_order: 50
---

## {{page.title}}

The MDI Pipelines Framework provide support tools for integrating 
compiled code into your pipeline.

### Rust

The MDI Pipelines Framework provides the most extensive support
for supporting pipelines with tools written in the Rust languange.
Rust is an oustanding system-level language for writing HPC 
data processing pipelines.

All of the `rust` commands operate as the level of a tool suite.
However, it is necessary to activiate the commands by calling
then on a specific pipeline of that suite. It does not matter which
pipeline you use, it just has to be part of the parent suite of interest.

```sh
# example command to compile Rust code
# `basecall` is any of the pipelines from tool suite of interest
hf3 -d basecall rust --gcc "module load gcc/15.1.0" --compile 1.92
```
