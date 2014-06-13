bash-debug-sampler
==================
#### Purpose: 
Educational.  Generate sample data for every possible kernel debug of Check Point Firewall kernel (module).
#### Usage: 
Takes a single optional argument; a file name containing MODULE and FLAG names in the format of
'module flag' with one entry per line.  If no argument is given, automatic discovery will be used
to determine all of the available modules and flags.
#### Examples:
```
               ./debug-sampler.sh
               ./debug-sampler.sh modules.txt
```
