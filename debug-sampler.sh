#!/bin/bash
# Create: 2013-07-03 John C. Petrucci
# Modify: 2013-07-09 John C. Petrucci
# http://johncpetrucci.com
# Purpose: Educational.  Generate sample data for every possible kernel debug of Check Point Firewall kernel (module).
# Usage: Takes a single optional argument; a file name containing MODULE and FLAG names in the format of
#	  |+ 'module flag' with one entry per line.  If no argument is given, automatic discovery will be used
#	  \+ to determine all of the available modules and flags.
# Examples: 
#		./debug-sampler.sh
#		./debug-sampler.sh modules.txt
# *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
#

trap trapExit 2 15 # Upon a SIGINT (ctl-C) or SIGTERM (default level kill command) we will run this function to cleanly exit.
ME=`basename $0` # Pretty-print the name of this script.
DEBUGDURATION=30 # Allow the debug to run and collect data for this time (seconds).

# Before exiting run this
trapExit() {
	fw ctl debug 0 # Set all debug options back to default.
	rm -vf $$*tmp # Clean up all temporary files.  They may already be deleted at this point if script was not interrupted.
	echo Cleanly exiting $ME at $(\date +%T' on '%F) >/dev/stderr # Print the datestamp that we exit.
	exit 0
}

# Ran with no arguments we can get a listing of all available modules and flags.  Parse this to build our list.
fw ctl debug -m > $$.tmp 2>/dev/null # Create a temporary file named with self PID so we can save time and don't have to execute fw ctl repeatedly per module.

# Check that the type/frequency thresholds are not modified.
grep -qEi "(type\=(none|err|wrn|notice))|(freq\=rare)" $$.tmp && echo "`tput smso` WARNING! `tput rmso`  Modified type / frequency thresholds are detected.  This may result in less output than expected.";

# Define the function to zero-out debug options, set a single debug flag, start the debug, let it run X seconds, and finally stop.
runDebug() {
	MODULE=$1 # Set variable to first positional parameter.
	FLAG=$2 # Set variable to second positional parameter.
	fw ctl debug -x >/dev/null # Zero out debug modules and flags.
	fw ctl debug -buf 16000 >/dev/null # Set the buffer size.
	fw ctl debug -m ${MODULE} ${FLAG} >/dev/null # Set the module and flag we will test.  By not using MODULE -->PLUS<-- FLAG we are setting only that flag and unsetting all others for that module.
	RESULTFILE=Debug_log_for_${MODULE}.${FLAG}.txt # Create file for output and name it with what debug we're running currently.
	#fw ctl debug -m ${MODULE} >> $RESULTFILE # Write the current debug conditions (for this module) to the file for easy reference. EDIT: This is done automatically by kdebug.
	echo -e This debug run at $(\date +%T' on '%F) \\n >> $RESULTFILE # Datestamp this and insert line break.
	fw ctl kdebug -T -f >>$RESULTFILE 2>&1 & # Start debugging and background the job (so sleep can start now).  Use microsecond timestamps, and redirect both STDOUT + STDERR.
	sleep $DEBUGDURATION # Allow the debug to run and collect data for this time (seconds).
	fw ctl debug -x >/dev/null # Using this as a way to kill the backgrounded debug without having to deal with PIDs.
	echo -e \\nThis debug ended at $(\date +%T' on '%F) >> $RESULTFILE # Datestamp this.
	unset MODULE FLAG RESULTFILE # Unset the variables.
}

# Option to read modules and flags from user-defined file
if [ -f $1 ] && [ ! -z $1 ]; then
	NUMBEROFFLAGS=`wc -l $1 | awk '{print $1}'` # Count the number of flags provided.
	# For each flag of each module, call runDebug()
	i=0; # Used to show progress.
	while read -a MODULE_FLAG_ARRAY; do
		i=$(($i + 1))
		MODULE=$(echo ${MODULE_FLAG_ARRAY[@]} | awk '{print $1}') # Parse the txt file and grab the module in the line.
		FLAG=$(echo ${MODULE_FLAG_ARRAY[@]} | awk '{print $2}') # Parse the txt file and grab the flag in the line.
		echo Debug $i of $NUMBEROFFLAGS [ -m $MODULE + $FLAG ]
		runDebug $MODULE $FLAG
	done < $1 # Read the file into the loop.
	unset i # Free up $i variable.

	trapExit # Exit nicely.
fi

# Main parsing of modules and flags for automatic discovery
MODULEARRAY=( $(grep "Module: " $$.tmp | sed -e 's/Module: //g') ) # Build array of possible modules from temp file.
for i in ${MODULEARRAY[@]}; do
	j=0 # Bash lacks multi-dimensional arrays, so this is a weak hack allowing us to have pseudo sub-arrays (suffixing a unique number).
	TEMPARRAY=( $(grep -A1 "Module: $i" $$.tmp | tail -1 | sed -e 's/Kernel debugging options: //g') ) # Grep for the current module (variable $i).  Get all flags for this specific module (tail).
	for k in ${TEMPARRAY[@]}; do # For each flag of this module...
		echo FLAG_FOR_${i}_${j}=$k >> $$.vars.tmp # ...write a line to our fake array file.  Ensure uniqueness w/ variable $j.
		j=$(($j + 1)) # Increment the unique variable for the next pass.
	done
done
rm -v $$.tmp # Clean up temporary file containing raw output.  Leave the other ($$.vars.tmp) for now.
NUMBEROFFLAGS=`wc -l $$.vars.tmp | awk '{print $1}'` # Count the number of flags found.

echo Located $NUMBEROFFLAGS different debug flags.  Estimated completion time: about $((($DEBUGDURATION * $NUMBEROFFLAGS) / 60 )) minutes. # Provide an estimate for runtime.  Flags can add up quickly!

# For each flag of each module, call runDebug()
i=0; # Used to show progress.
while read -a MODULE_FLAG_ARRAY; do
	i=$(($i + 1))
	MODULE=$(echo ${MODULE_FLAG_ARRAY[@]} | sed -r 's/FLAG_FOR_([a-zA-Z0-9_]+)_[0-9]+\=([a-zA-Z0-9]+)/\1/') # Parse the txt file and grab the module in the line.
	FLAG=$(echo ${MODULE_FLAG_ARRAY[@]} | sed -r 's/FLAG_FOR_([a-zA-Z0-9_]+)_[0-9]+\=([a-zA-Z0-9]+)/\2/') # Parse the txt file and grab the flag in the line.
	echo Debug $i of $NUMBEROFFLAGS [ -m $MODULE + $FLAG ]
	runDebug $MODULE $FLAG
done < $$.vars.tmp # Read the txt file into the loop.
rm -v $$.vars.tmp # Clean up temporary file.
unset i # Free up $i variable.

trapExit # Exit nicely.
