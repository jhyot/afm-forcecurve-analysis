// Copyright 2016 University of Basel
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma rtGlobals=3		// Use modern global access method.

#include <Waves Average>




Function LoopDFRFunc(f, dfpath, filter, [par1, par2])
	FUNCREF protof f
	String dfpath	// path to the data folder (without root:, without trailing ":"), empty string for operating in root
	String filter	// only go to data folders with this string, empty for all folders
	Variable par1, par2
	
	DFREF origdf = GetDataFolderDFR()
	
	SetDataFolder root:
	
	Variable i = 0
	Variable count = 0
	String dffullpath = "root:"
	if (strlen(dfpath) > 0)
		dffullpath += dfpath + ":"
	endif
	String df = ""
	for (i=0; i<CountObjects(dffullpath, 4); i+=1)
		df = GetIndexedObjName(dffullpath, 4, i)
		if(strlen(df)>0)
			if (strlen(filter) <= 0 || stringmatch(df, filter) == 1)
				SetDataFolder $(dffullpath + df)
				try
					f()
				catch
					print "Error in DF: " + dffullpath + df
					continue
				endtry
				count += 1
			endif
		endif
	endfor
	print "Executed " + num2str(count) + " times."
	
	SetDataFolder origdf
End


Function protof()
	Variable par1, par2
	print "proto"
End

Function genf()
	// Generic function, edit content, pass to LoopDFRFunc
	
	print GetDataFolder(1)
		
//	Variable/G :internalvars:noDialogs = 1
//	Analysis()
//	DoWindow/HIDE=1 kwtopwin
//	CalcRelStiffness(50,150)
//	Variable/G :internalvars:noDialogs = 0
	
//	Variable/G :internalvars:noDialogs = 1
//	NVAR deflfix
//	RecalcDeflSensAll(deflfix)
//	Analysis()
//	Variable/G :internalvars:noDialogs = 0
	
	//BrushHisto(2)
	//DoWindow/K kwtopwin
	
	//CalcHertzEMod(0.3)
	
	//MakeHisto("emod1_ring", "", .04e6, binmin=-.08e6)
	//MakeHisto("emod2_ring", "", .15e6)
	MakeHisto("brushheights_hole", "brushheights_hist", 1, binmin=-10)
	MakeHisto("relstiffness_hole", "relstiffness_hist", .15)	
	//MakeHisto("brushheights", "", 2, from=100)
	
	//Duplicate/O $"emodsplit", emodsplit_ring
	
	//AutoLoadFCFolder()
	
	//print BinSizeFreedmanDiaconis("emod2_hole"), BinSizeFreedmanDiaconis("emod2_ring")
	
	
	//WAVE/T fcmeta
	//FitDeflSensAndMakeTSD($"fc_aroundmu_avg_hole", fcmeta[2])
	
	//Concatenate/NP {$"hardwallforce_hole"}, $"::allrates:hardwallforce_hole"
	//Concatenate/NP {$"hardwallforce_ring"}, $"::allrates:hardwallforce_ring"
	
//	AppendToGraph $"emod2_ring_hist"
//	Variable num = ItemsInList(TraceNameList("", ";", 1)) - 1
//	ModifyGraph mode[num]=3, marker[num]=18, msize[num]=2
//	ChangeColorAccordingToFolder(num)
End


Function ChangeColorAccordingToFolder(index)
	Variable index		// trace index
	String list = "r29:65280,32768,58880;r09:32768,40704,65280;r03:65280,32512,16384;"
	list += "r01:0,52224,26368;r003:52224,52224,0"
	Variable r, g, b
	sscanf StringByKey(GetDataFolder(0), list), "%d,%d,%d", r, g, b
	ModifyGraph rgb[index]=(r,g,b)
End


// this is a "hack" function; before running it, make sure it really does
// what you want (hardcoded values etc.)
Function AutoLoadFCFolder(path)
	String path
	
	String df = GetDataFolder(0)
	String ptno = ""
	SplitString/E="pt(\\d{3})_" df, ptno
	
	PathInfo $path
	if (!V_flag)
		NewPath/Q $path
	endif
	
	// find correct folder
	Variable i = -1
	String foldername = ""
	String folderfound = ""
	do
		i += 1
		foldername = IndexedDir($path, i, 1)
		
		if (strlen(foldername) == 0)
			// no more folders
			break
		endif
		
		// manually exclude
		if (stringmatch(foldername, "*naso*"))
			continue
		endif
		
		if (stringmatch(foldername, "*_" + ptno))
			// found
			folderfound = foldername
			break
		endif
	while (1)
	
	
	if (strlen(folderfound) > 0)
		print "AutoLoadFCFolder: folder found: " + folderfound
		
		// execute what you want within this folder
		NewDataFolder/O internalvars
		Variable/G :internalvars:noDialogs = 1
		LoadAndAnalyseAllFC(folderfound)
		//LoadSingleFCFolder(folderfound)
		//ReadForceCurves()
		//recalcdeflsensall(8.6)
		//analysis()
		Variable/G :internalvars:noDialogs = 0
	else
		print "AutoLoadFCFolder: no folder found for df: " + df
	endif
End

// Creates datafolders from list and runs AutoLoadFCFolder() in each folder.
// Creates new datafolders in current datafolder.
Function AutoLoadListOfFolders(list)
	String list	// ; -separated list of datafolder names
	
	NewPath/Q autofolderpath
	
	Variable numdfs = ItemsInList(list)
	
	Variable i
	String df
	for (i=0; i < numdfs; i += 1)
		df = StringFromList(i, list)
		NewDataFolder/O/S $df
		AutoLoadFCFolder("autofolderpath")
		SetDataFolder ::
	endfor
	
	KillPath/Z autofolderpath
End


// "hack" function to traverse rate sud-datafolders in <df> and run functions on them
// beware of possible hardcoded values etc.
Function RatesCalcAndDisplay(df)
	String df		// "main" data folder (full path without "root:") whose children are the rate folders
					// use current if empty
		
	DFREF origdf = GetDataFolderDFR()
	
	if (strlen(df) == 0)
		df = GetDataFolder(1)
	else
		df = "root:" + df
	endif
	
	String subdflist = "r29;r09;r03;r01;r003;"
	
//	String deflsenslist = "r29:8.67;r09:8.71;r03:8.70;r01:8.59;r003:8.50;"
		
	Variable numfolders = ItemsInList(subdflist)
	Variable i
	String subdfitem = ""
	String subdf = ""
	String graph1name = ""
	String graph2name = ""
	for (i=0; i<numfolders; i+=1)
		SetDataFolder $df
		subdfitem = StringFromList(i, subdflist)
		subdf = FindSubDataFolder("*" + subdfitem + "*")
		if (strlen(subdf) == 0)
			print "[ERROR] did not find subfolder that matches '" + subdfitem +"'"
			return -1
		endif
		SetDataFolder $subdf
		
		
		// run desired custom code here
		
		MakeHisto("brushheights_full", "brushheights_hist", 1.5, binmin=-10)
		MakeHisto("relstiffness_full", "relstiffness_hist", 0.15)

		if (cmpstr(subdfitem, "r29") == 0)
			Display
			graph1name = MakeGraphName("brhist")
			DoWindow/C $graph1name
			Display
			graph2name = MakeGraphName("rehist")
			DoWindow/C $graph2name
		endif

		AppendToGraph/W=$graph1name $"brushheights_hist"
		AppendToGraph/W=$graph2name $"relstiffness_hist"

		// end custom code
		
	endfor
	
	// run custom post-loop code (in last subdatafolder)
	
	DoWindow/F $graph1name
	Execute/Q/Z "histocolors()"
	CreateLegendFromFolders(1)
	TextBox/C/N=legend0/A=RT/X=-5/Y=-5
	PutDFNameOnGraph()
	SetAxis/A left
	SetAxis/A bottom
	Label bottom "Brush height (nm)"
	
	DoWindow/F $graph2name
	Execute/Q/Z "histocolors()"
	CreateLegendFromFolders(1)
	TextBox/C/N=legend0/A=RT/X=0/Y=0
	PutDFNameOnGraph()
	SetAxis/A left
	SetAxis/A bottom
	Label bottom "rel. linear stiffness (pN/nm)"
	
//	DoWindow/F $graph1name
//	Execute/Q/Z "scattercolors()"
//	Tag/C/N=text0/F=0/X=0/Y=30/L=1/TL={dash=7}/A=RC bottom, 40,"Hole"
//	Tag/C/N=text1/F=0/X=0/Y=30/L=1/TL={dash=7}/A=LC bottom, 100,"Ring"
//	CreateLegendFromFolders(2)
//	TextBox/C/N=legend0/A=RB/X=-5/Y=-20
//	PutDFNameOnGraph()
//	SetAxis/A bottom
//	SetAxis left, 0, 45
//	Label left "brush height (nm)"
//	
//	DoWindow/F $graph2name
//	Execute/Q/Z "scattercolors()"
//	Tag/C/N=text0/F=0/X=0/Y=30/L=1/TL={dash=7}/A=RC bottom, 40,"Hole"
//	Tag/C/N=text1/F=0/X=0/Y=30/L=1/TL={dash=7}/A=LC bottom, 100,"Ring"
//	CreateLegendFromFolders(2)
//	TextBox/C/N=legend0/A=RB/X=-5/Y=-20
//	PutDFNameOnGraph()
//	SetAxis/A bottom
//	SetAxis left, 4, 8
//	Label left "rel. linear stiffness (pN/nm)"
	
	// end custom post-loop block
	
	SetDataFolder origdf
	
	return 0
End


// See MakeHisto for optional parameter meanings
Function/WAVE PoolData(list, wname, [edge, from, to])
	String list		// StringList of data folders
	String wname		// Wave name in each data folder to pool
	Variable edge, from, to
	
	edge = ParamIsDefault(edge) ? 0 : edge
	from = ParamIsDefault(from) ? 0 : from
	to = ParamIsDefault(to) ? 0 : to
	
	String df = ""
	Make/O/N=0/FREE pooled=0
	Variable wlen = 0
	Variable prevlen = 0
	Variable edgept = 0
	Variable len = ItemsInList(list)
	Variable i = 0
	for (i=0; i < len; i+=1)
		df = "root:" + StringFromList(i, list) + ":"
		WAVE w = $(df + wname)
		wlen = numpnts(w)
		if (edge)
			WAVE fc_z = $(df + "fc_z")
			FindLevel/Q/B=11/EDGE=1/P fc_z, edge
			if (V_Flag)
				print df + " Edge not found, don't include data"
				continue
			endif
			edgept = floor(V_LevelX)
		elseif(to != 0)
			edgept = to
		else
			edgept = wlen-1
		endif
		Duplicate/FREE/R=[from,edgept] w, wdup
		Concatenate/NP {wdup}, pooled
	endfor
	
	return pooled
End


// See MakeHisto for variable meaning
// Needs 2D text wave named 'pool'; each row has:
// 1st colum is target folder (relative to text wave; folders must exist),
// further columns are source folders (relative to root [without root:]).
// When executing function, must be in same folder as 'pool'.
Function PoolFoldersFromTable(wname, [edge, from, to])
	String wname
	Variable edge, from, to
	
	edge = ParamIsDefault(edge) ? 0 : edge
	from = ParamIsDefault(from) ? 0 : from
	to = ParamIsDefault(to) ? 0 : to
	
	PoolFoldersFromTableNamed(wname, wname, edge=edge, from=from, to=to)
	
	return 0
End


Function PoolFoldersFromTableNamed(wname, poolname, [edge, from, to])
	String wname
	String poolname		// name for pooled wave
	Variable edge, from, to
	
	edge = ParamIsDefault(edge) ? 0 : edge
	from = ParamIsDefault(from) ? 0 : from
	to = ParamIsDefault(to) ? 0 : to
	
	WAVE/T/Z pool
	
	if (!WAVEExists(pool))
		print "ERROR: didn't find wave 'pool'"
		return -1
	endif
	
	Variable i,j
	String list = ""
	for (i=0; i < DimSize(pool, 0); i+=1)
		list = ""
		for (j=1; j < DimSize(pool, 1); j+=1)
			if (strsearch(pool[i][j], ";", 0) > -1)
				print "ERROR: illegal character in wave name: " + pool[i][j]
				return -1
			endif
			list += pool[i][j] + ";"
		endfor
		WAVE wpool = PoolData(list, wname, edge=edge, from=from, to=to)
		Duplicate/O wpool, $(":" + pool[i][0] + ":" + poolname)
	endfor
	
	return 0
End



Function PoolHistoPctl(list, wname, histname, edge, binsize, pctl)
	String list		// StringList of data folders
	String wname		// Wave name in each data folder to pool
	String histname // Name of histogram to be generated
	Variable edge	// 0: no edge detection; >0: detect edge at this level (nm)
	Variable binsize
	Variable pctl	// Upper percentile up to which to scale the histogram
	
	WAVE w = PoolData(list, wname, edge=edge)	
	
	Variable binmin = -5
	
	Variable binmax = GetUpperPercentile(w, pctl)
	// Round to upper decade
	binmax = 10*ceil(binmax/10)
	
	Variable bins = (binmax - binmin)/binsize
	Make/O/N=(bins) $histname = 0
	WAVE h = $histname
	Histogram/P/B={binmin, binsize, bins} w, h
End


Function PoolHistoFullRange(list, wname, histname, edge, binsize)
	String list		// StringList of data folders
	String wname		// Wave name in each data folder to pool
	String histname // Name of histogram to be generated
	Variable edge	// 0: no edge detection; >0: detect edge at this level (nm)
	Variable binsize
	
	
	Variable binmin = -4e-3
	
	WAVE w = PoolData(list, wname, edge=edge)	
	WaveStats/Q/M=1 w		
	Variable binmax = V_max	
	Variable bins = ceil((binmax - binmin)/binsize)
	
	if (strlen(histname) == 0)
		histname = wname + "_hist"
	endif
	Make/O/N=(bins) $histname = 0
	WAVE h = $histname
	Histogram/P/B={binmin, binsize, bins} w, h
End


Function PoolScatter(list, wx, wy, wxnew, wynew)
	String list		// StringList of data folders
	String wx, wy	// Wave names for x and y axis of scatter plot (these will be pooled)
	String wxnew, wynew		// Wave names for the new wave with pooled data
	
	WAVE wxpool = PoolData(list, wx, edge=0)
	WAVE wypool = PoolData(list, wy, edge=0)
	
	Duplicate/O wxpool, $wxnew
	Duplicate/O wypool, $wynew
End


Function MakeHisto(wname, histname, binsize, [binmin, edge, from, to])
	String wname		// Wave name for data
	String histname // Name of histogram to be generated
	Variable binsize
	Variable binmin
	Variable edge	// 0: no edge detection; >0: detect edge at this level (nm)
	Variable from, to	// (exclusive with edge) first and last index to include in histogram
							// if either only from or to is specified,
							// the other is set to the beginning (from) or end (to), respectively
	
	binmin = ParamIsDefault(binmin) ? 0 : binmin
	edge = ParamIsDefault(edge) ? 0 : edge
	from = ParamIsDefault(from) ? 0 : from
	to = ParamIsDefault(to) ? 0 : to
	

	
	if (edge)
		WAVE fc_z
		FindLevel/Q/B=11/EDGE=1/P fc_z, edge
		if (V_Flag)
			print "Edge not found"
			Abort
		endif
		Variable edgept = floor(V_LevelX)
		Duplicate/FREE/R=[0,edgept] $wname, w
	elseif(to != 0)
		Duplicate/FREE/R=[from,to] $wname, w
	else
		Duplicate/FREE/R=[from,] $wname, w
	endif
	
	WaveStats/Q/M=1 w		
	Variable binmax = V_max	
	Variable bins = ceil((binmax - binmin)/binsize) + 2  // make 2 extra bins at the end
	
	if (strlen(histname) == 0)
		histname = wname + "_hist"
	endif
	Make/O/N=(bins) $histname = 0
	WAVE h = $histname
	Histogram/P/B={binmin, binsize, bins} w, h
	String notestr = "Created-by-MakeHisto;"
	notestr += "flags:P;source:" + wname + ";binmin:" + num2str(binmin) + ";"
	notestr += "bins:" + num2str(bins) + ";binsize:" + num2str(binsize) + ";"
	notestr += "edge:" + num2str(edge) + ";from:" + num2str(from) + ";to:" + num2str(to) + ";"
	Note/K h, notestr
End


Function MarkRelStiffness(lo, hi)
	Variable lo, hi	// stiffness to mark between lo and hi
	WAVE rw = relstiffness
	
	Make/N=(numpnts(rw))/O relstiffness_marked = NaN
	WAVE rm = relstiffness_marked
	
	rm[] = (rw[p] >= lo && rw[p] <= hi) ? rw[p] : NaN
End


Function DeflRef_DrawLines(numspots, numramps)
	Variable numspots	// num of different spots
	Variable numramps	// num of ramps in multiramp series
	
	DrawAction delete
	
	// full line *after* first set of spots
	SetDrawEnv xcoord=bottom, ycoord=prel, dash=0
	DrawLine numspots, 0, numspots, 1
	
	// dashed lines *at* each new spot
	Variable i
	for (i=numspots+numramps; i <(numspots + numspots*numramps); i+=numramps)
		SetDrawEnv xcoord=bottom, ycoord=prel, dash=1
		DrawLine i, 0, i, 1
	endfor

End


// Separates Defl Sens Ref curves into separate waves by type (each group has <numspots> waves):
// <newname>_sub_normal:  "normal" pt-shoot ramping (first group in data);
// <newname>_sub_first:  first ramps of multi-ramp at each spot
// <newname>_sub_last:  last ramps of multi-ramp at each spot
// Ramp series has to be: <numspots> x 1 ramp; then <numramps> ramps for each spot, <numspots> times
Function DeflRef_MakeSubWaves(numspots, numramps, origname, newname)
	Variable numspots	// num of different spots
	Variable numramps	// num of ramps in multiramp series
	String origname		// name of wave to split (original will be preserved)
	String newname		// beginning of name of new waves (if empty, use origwave)

	WAVE/Z o = $origname
	if (!WAVEExists(o))
		print "No such wave: " + origname
		return -1
	endif
	
	if (strlen(newname) == 0)
		newname = origname
	endif

	Make/O/N=(numspots) $(newname + "_sub_normal") = NaN
	Make/O/N=(numspots) $(newname + "_sub_first") = NaN
	Make/O/N=(numspots) $(newname + "_sub_last") = NaN
	
	WAVE normal = $(newname + "_sub_normal")
	WAVE first = $(newname + "_sub_first")
	WAVE last = $(newname + "_sub_last")
	
	
	normal[] = o[p]
	first[] = o[numspots + p*numramps]
	last[] = o[numspots + (p+1)*numramps-1]
	
	print "Split. New waves: normal " + num2str(numpnts(normal)) + ", first " + num2str(numpnts(first)) + ", last " + num2str(numpnts(last))
End



// Makes new folders (from subdirs list) in path, then moves files into them
// according to the numspots and numramps. Files moved are of type "...0000.xxx", "...0001.xxx" etc.
// File structure: 1 ramp per file. Ramp structure: <numspots> ramps, then for each numspot <numramps> ramps.
Function MakeFolderStructure(path, subdirs, numspots, numramps)
	String path			// path to create substructure in. Leave empty for prompt
	String subdirs		// a list like "dir1;dir2;dir3;"
	Variable numspots	// num of different spots
	Variable numramps	// num of ramps in multiramp series
	
	if (strlen(path) == 0)
		NewPath/M="Select base dir with files"/O/Q makefolderstructure_basepath
		if (V_flag != 0)
			print "User cancelled"
			return -1
		endif
	else
		NewPath/M="Select base dir with files"/O/Q makefolderstructure_basepath, path
	endif
	
	PathInfo makefolderstructure_basepath
	
	String basepath = S_path
	
	// check all files for correct pattern and count them first before doing anyhting,
	// to make sure that we have correct amount of files
	Variable i
	String allfiles = IndexedFile(makefolderstructure_basepath, -1, "????")
	String matchedfiles = ""
	String currfile = ""
	
	for (i=0; i <= ItemsInList(allfiles); i+=1)
		currfile = StringFromList(i, allfiles)
		if (GrepString(currfile, "\\d{3,}\\.\\d{3}$"))
			matchedfiles += currfile + ";"
		endif
	endfor
	
	Variable rampsperdir = numspots + numspots*numramps
	
	if (ItemsInList(matchedfiles) < ItemsInList(subdirs)*rampsperdir)
		print "Error: Less matched files in folder than needed based on spot and ramp numbers"
		return -1
	elseif (ItemsInList(matchedfiles) > ItemsInList(subdirs)*rampsperdir)
		print "Warning: More matched files in folder than needed based on spot and ramp numbers. Remaining files not moved."
	endif
	
	matchedfiles = SortList(matchedfiles, ";", 4)		// case-insensitive alphabetic sort
	
	Variable j, fileno
	String subdir = ""
	
	Variable nummoved = 0
	Variable retval = 0
	// loop through subdirs
	for (i=0; i < ItemsInList(subdirs); i+=1)
		if (retval == -1)
			// if broke in inner loop (below), break as well here
			break
		endif
		subdir = StringFromList(i, subdirs)
		NewPath/C/O/Q makefolderstructure_subpath, (basepath + subdir)
		if (V_flag != 0)
			print "Error: Couldn't create subdir: " + subdir
			retval = -1
			break
		endif

		// loop through files
		for (j=0; j < rampsperdir; j+=1)
			fileno = i*rampsperdir + j
			currfile = StringFromList(fileno, matchedfiles)
			MoveFile/D/P=makefolderstructure_basepath/Z currfile as subdir
			if (V_flag != 0)
				print "Error: couldn't move file: " + currfile
				retval = -1
				break
			else
				nummoved += 1
			endif
		endfor
	endfor
	
	print "Moved " + num2str(nummoved) + " files."
	
	return retval
End


// Replaces waves in a graph with other waves
// This is somewhat of a hack at the moment
// Only works with y waves (not y-vs-x waves)
Function ReplaceWavesBySubfolders(orig, new, subdflist)
	String orig		// original wave name in graph
	String new		// new wave name
	String subdflist		// semicolon-separated list of subfolders
						// if empty, use default hardcoded list (see below)
						
	if (strlen(subdflist) == 0)
		subdflist = "r29;r09;r03;r01;r003"
	endif
	
	// go up one level from graph's folder
	String maindf = GetGraphDF() + ":"
	
	DFREF origdf = GetDataFolderDFR()
		
	Variable numfolders = ItemsInList(subdflist)
	Variable i
	String subdfitem = ""
	String subdf = ""
	Variable numreplaced = 0
	// replace i'th trace with orig wavename with new wave from first subfolder
	// that matches i'th entry in rates list
	for (i=0; i<numfolders; i+=1)
		SetDataFolder $maindf
		subdfitem = StringFromList(i, subdflist)
		subdf = FindSubDataFolder("*" + subdfitem + "*")
		if (strlen(subdf) == 0)
			print "[ERROR] did not find subfolder that matches '" + subdfitem +"'"
			return -1
		endif
		SetDataFolder $subdf
		ReplaceWave trace=$orig, $new
		numreplaced += 1
	endfor
	
	print "[success] " + num2str(numreplaced) + " traces replaced"
	
	SetDataFolder origdf

	return 0
End


// Operates on current data folder
// Returns name of first data folder found matching matchstr (relative name)
// Returns empty string if nothing found
Function/S FindSubDataFolder(matchstr)
	String matchstr		// string to find, can include wildcards
	
	Variable numfolders = CountObjects(":", 4)
	Variable i
	String df = ""
	for (i=0; i < numfolders; i+=1)
		df = GetIndexedObjName(":", 4, i)
		if (stringmatch(df, matchstr) == 1)
			// found a folder
			break
		endif
	endfor
	
	return df
End


// Run in same data folder as indicated waves
// At the moment processes 2 ranges; (hardcoded below)
Function MarkCurvesAroundAvg(wlist, markwlist, avglist, tolerancelist)
	String wlist				// list of wave names, without folder names, to process
	
	String markwlist			// list of mark wave names (will be overwritten); must be 1 longer
								// than wave list; last entry is combination (logical AND) of all mark waves
								
	String avglist			// list of averages; waves with avg +/- tolerance will be marked
								// has 2 values per wave, one for each hardcoded range;
								// i.e. double the length of wave list
								
	String tolerancelist	// list of tolerances; must be length of wave list
	
	
	Variable range1start = 0
	Variable range1end = 40
	Variable range2start = 100
	
	
	Variable numitems = ItemsInList(wlist)
	
	if ((ItemsInList(avglist) != 2*numitems) || (ItemsInList(tolerancelist) != numitems) || (ItemsInList(markwlist) != numitems+1))
		print "[ERROR] List lengths do not match"
		return -1
	endif

	
	Variable i
	String wname
	String markname
	Variable avg1, avg2
	Variable tol
	for (i=0; i < numitems; i += 1)
		wname = StringFromList(i, wlist)
		markname = StringFromList(i, markwlist)
		avg1 = str2num(StringFromList(2*i, avglist))
		avg2 = str2num(StringFromList(2*i+1, avglist))
		tol = str2num(StringFromList(i, tolerancelist))
		
		Duplicate/O $wname, $markname
		WAVE markw = $markname
		WAVE w = $wname
		markw = NaN
		
		// 2 hardcoded ranges
		markw[range1start, range1end] = (abs(w[p] - avg1) < tol) ? 1 : NaN
		markw[range2start, ] = (abs(w[p] - avg2) < tol) ? 1 : NaN
	endfor
	
	
	// combined (logical AND) mark wave
	String combiname = StringFromList(numitems, markwlist)
	Duplicate/O markw, $combiname
	WAVE combiw = $combiname
	
	combiw = 1
	
	for (i=0; i < numitems; i += 1)
		markname = StringFromList(i, markwlist)
		WAVE markw = $markname
		
		combiw = (markw[p] != 1) ? NaN : combiw[p]
	endfor	
End


Function AppendMarksToHeightPlot(wlist)
	String wlist		// list of wave names to append
	
	
	String colorlist = "0;0;0;"  // black
	colorlist += "0;0;65280;"		// blue
	colorlist += "0;52224;0;"		// green
	
	Variable numitems = ItemsInList(wlist)
	Variable coloritems = ItemsInList(colorlist)
	
	Variable oldtracenum = ItemsInList(TraceNameList("", ";", 1))
	
	Variable ret = MapToForeGround()
	if (ret < 0)
		return -1
	endif
	
	Variable i
	String wname
	Variable r, g, b
	Variable currtrace
	for (i=0; i < numitems; i += 1)
		currtrace = oldtracenum + i
		wname = StringFromList(i, wlist)
		r = str2num(StringFromList(mod(i*3, coloritems), colorlist))
		g = str2num(StringFromList(mod(i*3+1, coloritems), colorlist))
		b = str2num(StringFromList(mod(i*3+2, coloritems), colorlist))
		AppendToGraph/T/L/C=(r,g,b) $wname
		ModifyGraph muloffset[currtrace]={0,(i+1)*10}
		ModifyGraph mode[currtrace]=3, marker[currtrace]=18, msize[currtrace]=2
	endfor
	
End


// Averages waves from 2D wave given by wname.
// Only averages marked waves, i.e. where marker wave has value 1
// (Use e.g. MarkCurvesAroundAvg to generate marker waves)
Function AverageMarkedCurves(wname, avgname, marker, [from, to])
	String wname		// name of 2D wave with original curves
	String avgname	// name of new average wave (1D)
	String marker	// name of marker wave; must be same length as wname columns
	Variable from, to	// optional variables to define the range of curves ("pixels")
							// 		which to average
	
	from = ParamIsDefault(from) ? 0 : from
	to = ParamIsDefault(to) ? 0 : to
	
	KillDataFolder/Z temp_averagemarkedcurves	// clear previous temp data
	NewDataFolder/O temp_averagemarkedcurves
	
	WAVE markw = $marker
	NVAR numfc = :internalvars:numCurves
	NVAR numpts = :internalvars:FCNumPoints
	WAVE/T fcmeta
	
	String tempname
	Variable i
	Variable lastfc
	if (to == 0)
		to = numfc-1
	endif
	for (i=from; i <= to; i += 1)
		if (markw[i] != 1)
			continue
		endif
		
		tempname = ":temp_averagemarkedcurves:fc" + num2str(i)
		
		MakeTempCurve(tempname, wname, i)
		SetScale/I x, 0, NumberByKey("rampsizeUsed", fcmeta[i]), $tempname
		lastfc = i
	endfor
	
	SetDataFolder temp_averagemarkedcurves
	fWaveAverage(WaveList("*", ";", ""), "", 0, 0, avgname, "")
	Duplicate/O $avgname, $("::" + avgname)
	KillWaves $avgname
	SetDataFolder ::
	
	WAVE avgw = $avgname
	Redimension/N=(numpts) avgw
	Variable avgrampsize = AvgAllRampSizeUsed()
	SetScale/I x, 0, avgrampsize, avgw
	
	//KillDataFolder temp_averagemarkedcurves
	
	
	Variable springConst = NumberByKey("springConst", fcmeta[lastfc])
	// pN -> nm
	avgw /= springConst
	avgw /= 1000
	
	STRUCT CreateTSDReturn ret
	CreateTSDWave(avgw, $"", ret)
	
	Duplicate/O ret.tsd, $(avgname + "_xtsd")
	avgw *= springConst * 1000	
End



