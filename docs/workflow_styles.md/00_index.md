---
title: Workflow Styles
has_children: true
nav_order: 10
---

## {{page.title}}

The MDI makes few demands of how you create your workflows.
The only structural requirement is that a pipeline action
be defined by the contents of script:

```
pipelines/<pipelineName>/<actionName>/Workflow.sh
```

but that script can contain any executable code you wish.

With that said, the MDI provides support mechanisms that can make 
pipelines easier to construct and more robust if you use them
in your action script.

At present, we support two workflow styles summarized in this 
section. Again, feel free to adopt any other style or workflow
language - just make sure any required software
is declared in:

```yml
# pipeline.yml
actions:
    actionName:
        condaFamilies:
```
