#!/usr/bin/env sh

# Build script for the afm-forcecurve-analysis software.
# This build script runs on Linux.
#
# Build steps:
# * Deletes the old build folder
# * Generates the PDF manual from Latex source. A Tex distribution with pdflatex and necessary latex packages must be installed on the machine.
# * Builds a zip archive with the program files and the PDF manual


buildfolder="build"
zipfilename="afm-forcecurve-analysis.zip"
docsourcefolder="doc"
doctargetfolder="manual"
manualbasename="afm-forcecurve-analysis-manual"

rm -rf "$buildfolder"
mkdir -p "$buildfolder/$doctargetfolder"
rootdir="$(pwd)"

cd "$docsourcefolder"
pdflatex -output-directory "../$buildfolder/$doctargetfolder" "$manualbasename.tex" \
    && pdflatex -output-directory "../$buildfolder/$doctargetfolder" "$manualbasename.tex"

cd "$rootdir"
zip -r "$buildfolder/$zipfilename" config lib forcecurve-analysis.ipf LICENSE README.md

cd "$buildfolder"
zip "$zipfilename" "$doctargetfolder/$manualbasename.pdf"

cd "$rootdir"