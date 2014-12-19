bash-debug-sampler
==================
#### Purpose: 
Educational.  Generate sample data for every possible kernel debug of Check Point Firewall kernel (module).
#### Usage: 
Takes a single optional argument; a file name containing TYPE, MODULE and FLAG names in the format of:  
`TYPE MODULE FLAG [FLAG [FLAG]]...`  
..separated by newline. TYPE is one of {fw1|fwaccel|sim}.  
Multiple FLAGs can be given per debug line (e.g. `fw1 fw conn drop`, where 'conn' & 'drop' are flags).  
Multi-flag debugs are only possible when a manual file is specified, as the automatic discovery mechanism simply iterates through each discovered flag one by one.  
   
If no argument is given, automatic discovery will be used to determine all of the available modules and flags.
#### Examples:
```
               ./debug-sampler.sh
               ./debug-sampler.sh myflags.txt
```
#### Demo:
[Demo asciicast](https://asciinema.org/a/14244)
