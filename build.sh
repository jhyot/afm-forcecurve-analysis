#!/usr/bin/env sh

# Builds a zip archive including all the necessary files to run this software in Igor.
#
# The desired zip file name can be passed as an argument, otherwise a default name will be used.


zipfilename="afm-forcecurve-analysis.zip"


case "$1" in
	-h | --help | -\?)
		echo "Usage: `basename $0` [zipfilename]"
		exit
		;;
	?*)
		zipfilename="$1"
		;;
esac

zip -rFS "$zipfilename" config lib forcecurve-analysis.ipf LICENSE README.md

