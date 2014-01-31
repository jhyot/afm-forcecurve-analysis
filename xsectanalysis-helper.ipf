#pragma rtGlobals=3		// Use modern global access method.

Function findmax()
	Variable i = 0
	WAVE fc
	Variable pt = 4096
	for (i=0; i < 1024; i+=1)
		Duplicate/FREE/O/R=[][i] fc, w
		FindLevel/P/Q w, (w[0] + 1000)
		if (!V_flag)
			pt = min(pt, V_LevelX)
		endif
	endfor
	
	print "max pt: " + num2str(pt)
End


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


Function FitDeflSensAndMakeTSD(w, meta)
	WAVE w
	String meta
	
	NVAR/Z deflfit = $(NameOfWave(w) + "_deflfit")
	if (NVAR_Exists(deflfit))
		meta = ReplaceNumberByKey("deflSensUsed", meta, deflfit)
	else
		Variable/G $(NameOfWave(w) + "_deflfit")
		NVAR deflfit = $(NameOfWave(w) + "_deflfit")
	endif
	
	STRUCT FitDeflReturn ret
	ConvertForceToV(w, meta)
	FitDeflectionSensitivity(w, meta, $"", ret)
	deflfit = ret.deflsensfit
	
	w *= deflfit
	
	print "deflSensFit:", deflfit
	
	STRUCT CreateTSDReturn rettsd
	CreateTSDWave(w, $"", rettsd)
	
	Duplicate/O rettsd.tsd, $(NameOfWave(w) + "_xtsd")
	
	w *= 1000 * NumberByKey("springConst", meta)
	SetScale d 0,0,"pN", w
End


// this is a "hack" function; before running it, make sure it really does
// what you want (hardcoded values etc.)
Function AutoLoadFCFolder()

	String df = GetDataFolder(0)
	String ptno = ""
	SplitString/E="pt(\\d{3})_" df, ptno
	
	PathInfo exppath
	if (!V_flag)
		NewPath/Q exppath
	endif
	
	// find correct folder
	Variable i = -1
	String foldername = ""
	String folderfound = ""
	do
		i += 1
		foldername = IndexedDir(exppath, i, 1)
		
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
	
	
	// execute what you want within this folder
	if (strlen(folderfound) > 0)
		Variable/G :internalvars:noDialogs = 1
		LoadSingleFCFolder(folderfound)
		ReadForceCurves()
		recalcdeflsensall(8.6)
		analysis()
	endif
	
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
		
		MakeHisto("relstiffness_hole", "relstiffness_hist", .2)
		//MakeHisto("emod2_full", "emod2_hist", .15e6)

		if (cmpstr(subdfitem, "r29") == 0)
			Display
			graph1name = MakeGraphName("rlh")
			DoWindow/C $graph1name
//			Display
//			graph2name = MakeGraphName("e2hi")
//			DoWindow/C $graph2name
		endif

		AppendToGraph/W=$graph1name $"relstiffness_hist"
		//AppendToGraph/W=$graph2name $"emod2_hist"

		// end custom code
		
	endfor
	
	// run custom post-loop code (in last subdatafolder)
	
	DoWindow/F $graph1name
	Execute/Q/Z "histocolors()"
	CreateLegendFromFolders(1)
	TextBox/C/N=legend0/A=RT/X=-5/Y=-5
	PutDFNameOnGraph()
	SetAxis/A left
	SetAxis bottom 4,8
	Label bottom "E-modulus region 1 (Pa)"
	
//	DoWindow/F $graph2name
//	Execute/Q/Z "histocolors()"
//	CreateLegendFromFolders(1)
//	TextBox/C/N=legend0/A=LT/X=0/Y=0
//	PutDFNameOnGraph()
//	SetAxis/A left
//	SetAxis bottom 0, 3e6
//	Label bottom "E-modulus region 2 (Pa)"
	
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


Function rengraph()
	WAVE w = fc_z
	String suffix = "xsect"
	String g = StringFromList(0, FindGraphsWithWave(w))
	String name = MakeGraphName(suffix)
	DoWindow/C/W=$g $name
End

Function killwin()
	WAVE w = brushheights_histo
	String g = StringFromList(0, FindGraphsWithWave(w))
	KillWindow $g
End


// Function by Jon Tischler
// TischlerJZ at ornl.gov
// http://www.wavemetrics.com/search/viewmlid.php?mid=23626
Function/S FindGraphsWithWave(w) // find the graph windows which contain the specified wave, returns a list of graph names
	Wave w
	if (!WaveExists(w))
		return ""
	endif
	String name0=GetWavesDataFolder(w,2), out=""
	String win,wlist = WinList("*",";","WIN:1"), clist, cwin
	Variable i,m,Nm=ItemsInList(wlist)
	for (m=0;m<Nm;m+=1)
		win = StringFromList(m,wlist)
		CheckDisplayed/W=$win w
		if (V_flag>0)
			out += win+";"
		else
			clist = ChildWindowList(win)
			for (i=0;i<ItemsInLIst(clist);i+=1)
				cwin = StringFromList(i,clist)
				CheckDisplayed/W=$(win+"#"+cwin) w
				if (V_flag>0)
					out += win+"#"+cwin+";"
					break
				endif
			endfor
		endif
	endfor
	return out
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
End


Function MarkRelStiffness(lo, hi)
	Variable lo, hi	// stiffness to mark between lo and hi
	WAVE rw = relstiffness
	
	Make/N=(numpnts(rw))/O relstiffness_marked = NaN
	WAVE rm = relstiffness_marked
	
	rm[] = (rw[p] >= lo && rw[p] <= hi) ? rw[p] : NaN
End


Function ConvTempRawToV(i)
	Variable i
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	Make/N=(fcpoints)/O wtemp
	
	WAVE fc
	WAVE/T fcmeta
	
	wtemp[] = fc[p][i]
	String h = fcmeta[i]
	
	ConvertRawToV(wtemp, h)

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