---
title: Script Utilities
has_children: false
nav_order: 20
---

## {{page.title}}

All running pipelines source shell scripts that expose functions
that can be very useful in your action scripts.

We only describe those functions designed to be called by your pipeline actions.
See the following file for more information and for additional, mostly internal, functions:

- <https://github.com/MiDataInt/mdi-pipelines-framework/blob/main/pipeline/workflow/workflow.sh>

## Support for MDI step-style workflows

The following functions are the core of MDI step-style pipeline actions.

### runWorkflowStep

- **Usage**: runWorkflowStep $STEP_NUMBER $STEP_NAME $STEP_SCRIPT  
- **Action**:   
- **Result**:

### checkWorkflowStep

**Usage**: checkWorkflowStep $STEP_NUMBER $STEP_NAME $STEP_SCRIPT  
**Action**:  
**Result**:

### finishWorkflowStep

**Usage**: finishWorkflowStep $STEP_NUMBER $STEP_NAME $STEP_SCRIPT  
**Action**:  
**Result**:

## Check success of all program handler in a data stream

**Usage**: checkPipe
**Action**: Check the exit status of every program handler in the prior bash command sequence  
**Result**: Dies if any handler had a non-zero exit status  

## Data integrity checks

The following functions aren't as commonly used but can help your pipeline
make sure it has appropriate data to work on.

### checkForData

**Usage**: checkForData $COMMAND  
**Action**: Ensure that a data stream will have at least one line of data  
**Result**: Script exits quietly if stream is empty  

### waitForFile

**Usage**: waitForFile $FILE [$TIME_OUT = 60]  
**Action**: Wait for a file to appear on the file system  
**Result**: Script dies does not appear within $TIME_OUT seconds  

### checkFileExists

**Usage**: checkFileExists \<$FILE | $GLOB\>  
**Action**: Verify that $FILE, or the first file of $GLOB, exists and is not empty
**Result**: Script dies if file is empty or not found
