#!/bin/bash
# Create: 2013-07-03 John C. Petrucci
# http://johncpetrucci.com
# Purpose: Educational.  Generate sample data for every possible kernel debug of Check Point Firewall kernel (module).
# Usage: Takes a single optional argument; a file name containing TYPE, MODULE and FLAG names in the format of:
#	  TYPE MODULE FLAG [FLAG [FLAG]]...
#	  ..separated by newline.  TYPE is one of {fw1|fwaccel|sim}.
#	  Multiple FLAGs can be given per debug line (e.g. `fw1 fw conn drop`, where 'conn' & 'drop' are flags).
#	  Multi-flag debugs are only possible when a manual file is specified, as the automatic discovery mechanism
#	  simply iterates through each discovered flag one by one.
#
#	  If no argument is given, automatic discovery will be used to determine all of the available modules and flags.
# Examples: 
#		./debug-sampler.sh
#		./debug-sampler.sh modules.txt
# *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
#

trap 'trapExit early' 2 15 # Upon a SIGINT (ctl-C) or SIGTERM (default level kill command) we will run this function to cleanly exit.
me="$(basename $0)" # Pretty-print the name of this script.
debugduration=30 # Allow the debug to run and collect data for this time (seconds).

# Before exiting run this
trapExit() {
	[[ -n "$1" ]] && printf "\nCaught interrupt, shutting down!\n"
	fw ctl debug 0 # Set all debug options back to default.
	fwaccel dbg resetall >/dev/null # Zero out debug modules and flags.
	sim dbg resetall >/dev/null # Zero out debug modules and flags.
	rm -vf $$*tmp # Clean up all temporary files.  They may already be deleted at this point if script was not interrupted.
	printf "Cleanly exiting %s at %s\n" "$me" "$(\date +%T' on '%F)" >&2 # Print the datestamp that we exit.
	exit 0
}

# Ran with no arguments we can get a listing of all available modules and flags.  Parse this to build our list.  This step is needed regardless of automatic parse, so we can check for modified type/frequency thresholds.
printf "Generating temporary file: %s\n" "$$.fw1.tmp" >&2
fw ctl debug -m > $$.fw1.tmp 2>/dev/null # Create a temporary file named with self PID so we can parse all modules and flags
printf "Generating temporary file: %s\n" "$$.fwaccel.tmp" >&2
fwaccel dbg > $$.fwaccel.tmp 2>/dev/null
printf "Generating temporary file: %s\n" "$$.sim.tmp" >&2
sim dbg > $$.sim.tmp 2>/dev/null

# Check that the type/frequency thresholds are not modified.
grep -qEi "(type\=(none|err|wrn|notice))|(freq\=rare)" $$.fw1.tmp && echo "$(tput smso) WARNING! $(tput rmso)  Modified type / frequency thresholds are detected.  This may result in less output than expected.";

# Define the function to zero-out debug options, set a single debug flag, start the debug, let it run X seconds, and finally stop.
runDebug() {
	TYPE="$1"
	MODULE="$2"
	FLAG="$3"
	printf "Debug %'d of %'d: %s [ -m %s + %s ]\n" "$i" "$NUMBEROFFLAGS" "$TYPE" "$MODULE" "$FLAG"
	fw ctl debug -x >/dev/null # Zero out debug modules and flags.
	fwaccel dbg resetall >/dev/null # Zero out debug modules and flags.
	sim dbg resetall >/dev/null # Zero out debug modules and flags.
	fw ctl debug -buf 16000 >/dev/null # Set the buffer size.
	RESULTFILE=Debug_log_for_${TYPE}_${MODULE}_${FLAG// /_}.txt # Create file for output and name it with what debug we're running currently.
	
	# Selector for different types of debugs (fw1/fwaccel/sim).
	case "$TYPE" in
		    fw1)	fw ctl debug -m ${MODULE} ${FLAG} >/dev/null ;; # Set the module and flag we will test.  By not using MODULE -->PLUS<-- FLAG we are setting only that flag and unsetting all others for that module.
		fwaccel)	fwaccel dbg -m ${MODULE} + ${FLAG} >/dev/null; # Requires "+ flag", unlike fw ctl debug. 
					fwaccel dbg list | cat <(printf "Current fwaccel debugs:\n") - >> "$RESULTFILE";; # Write the current debug conditions to the file for easy reference.
		    sim)	sim dbg -m ${MODULE} + ${FLAG} >/dev/null; # Requires "+ flag", unlike fw ctl debug. 
					sim dbg list | cat <(printf "Current sim debugs:\n") - >> "$RESULTFILE";; # Write the current debug conditions to the file for easy reference.
	esac
	
	printf "This debug run at %s.\n" "$(\date +%T' on '%F)" >> "$RESULTFILE" # Datestamp this and insert line break.
	fw ctl kdebug -T -f >> "$RESULTFILE" 2>&1 & # Start debugging and background the job (so sleep can start now).  Use microsecond timestamps, and redirect both STDOUT + STDERR.
	sleep $debugduration # Allow the debug to run and collect data for this time (seconds).
	fw ctl debug -x >/dev/null # Using this as a way to kill the backgrounded debug without having to deal with PIDs.
	printf "\nThis debug ended at %s" "$(\date +%T' on '%F)" >> "$RESULTFILE" # Datestamp this.
	unset MODULE FLAG RESULTFILE # Unset the variables.
}

# Provide an estimate for runtime.  Flags can add up quickly!
giveEta() {
	printf "Located %s different debug flags.  Estimated completion time: about %s minutes.\n" "$NUMBEROFFLAGS" "$((($debugduration * $NUMBEROFFLAGS) / 60 ))"
}

# Automatic parsing of modules and flags
automaticParse() {

	# Parse fw1
	printf "Parsing fw1 modules / flags...\n" >&2
	MODULEARRAY=( $(sed -nre 's/Module: (.+)/\1/gp' $$.fw1.tmp) ) # Build array of possible modules from temp file.
	for MODULE in ${MODULEARRAY[@]}; do
		j=0 # Bash lacks multi-dimensional arrays, so this is a weak hack allowing us to have pseudo sub-arrays (suffixing a unique number).
		FLAGARRAY=( $(grep -A1 "Module: $MODULE" $$.fw1.tmp | tail -1 | sed -e 's/Kernel debugging options: //g') ) # Grep for the current module (variable $MODULE).  Get all flags for this specific module (tail).
		for FLAG in ${FLAGARRAY[@]}; do # For each flag of this module...
			echo fw1 $MODULE $FLAG >> $$.flags.tmp # ...write a line to our fake array file.  Ensure uniqueness w/ variable $j.
			j=$(($j + 1)) # Increment the unique variable for the next pass.
		done
	done
	
	# Parse fwaccel
	printf "Parsing fwaccel modules / flags...\n" >&2
	MODULEARRAY=( $(sed -nre 's/Module: ([a-zA-Z]+)/\1/gp' $$.fwaccel.tmp) ) # Build array of possible modules from temp file.
	for MODULE in ${MODULEARRAY[@]}; do
		j=0 # Bash lacks multi-dimensional arrays, so this is a weak hack allowing us to have pseudo sub-arrays (suffixing a unique number).
		FLAGARRAY=( $(grep -A1 "Module: $MODULE" $$.fwaccel.tmp | tail -1) ) # Grep for the current module (variable $MODULE).  Get all flags for this specific module (tail).
		for FLAG in ${FLAGARRAY[@]}; do # For each flag of this module...
			echo fwaccel $MODULE $FLAG >> $$.flags.tmp # ...write a line to our fake array file.  Ensure uniqueness w/ variable $j.
			j=$(($j + 1)) # Increment the unique variable for the next pass.
		done
	done

	# Parse sim
	printf "Parsing sim modules / flags...\n" >&2
	MODULEARRAY=( $(sed -nre 's/Module: ([a-zA-Z]+)/\1/gp' $$.sim.tmp) ) # Build array of possible modules from temp file.
	for MODULE in ${MODULEARRAY[@]}; do
		j=0 # Bash lacks multi-dimensional arrays, so this is a weak hack allowing us to have pseudo sub-arrays (suffixing a unique number).
		FLAGARRAY=( $(grep -A1 "Module: $MODULE" $$.sim.tmp | tail -1) ) # Grep for the current module (variable $MODULE).  Get all flags for this specific module (tail).
		for FLAG in ${FLAGARRAY[@]}; do # For each flag of this module...
			echo sim $MODULE $FLAG >> $$.flags.tmp # ...write a line to our fake array file.  Ensure uniqueness w/ variable $j.
			j=$(($j + 1)) # Increment the unique variable for the next pass.
		done
	done
}

main() {
	[[ -z "$1" ]] && [[ ! -f "$1" ]] && automaticParse # Only do automatic parsing if no valid manual file is supplied.
	
	NUMBEROFFLAGS=$(wc -l "${1:-$$.flags.tmp}" | awk '{print $1}') # Count the number of flags provided.
	giveEta
	# For each flag of each module, call runDebug()
	i=0; # Used to show progress.
	while read -a TYPE_MODULE_FLAG_ARRAY; do
		i=$(($i + 1))
		TYPE=$(echo ${TYPE_MODULE_FLAG_ARRAY[@]} | cut -d' ' -f1) # Parse the txt file and grab the type in the line.
		MODULE=$(echo ${TYPE_MODULE_FLAG_ARRAY[@]} | cut -d' ' -f2) # Parse the txt file and grab the module in the line.
		FLAG=$(echo ${TYPE_MODULE_FLAG_ARRAY[@]} | cut -d' ' -f3-) # Parse the txt file and grab the flag in the line.
		runDebug "$TYPE" "$MODULE" "$FLAG"
	done < "${1:-$$.flags.tmp}" # Read the file into the loop.
	unset i # Free up $i variable.

	trapExit # Exit nicely.
}

main "$@"
