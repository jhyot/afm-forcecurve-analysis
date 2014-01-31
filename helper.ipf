#pragma rtGlobals=3		// Use modern global access method.


Function absrelheights(img, bheights, added, nobrushrel, nobrushabs)
	String img, bheights, added, nobrushrel, nobrushabs

	// Create "absolute brush heights" wave
	WAVE imgw = $img
	WAVE bheightsw = $bheights
	Duplicate/O imgw, $added
	WAVE addedw = $added
	addedw += bheightsw
	
	// Display "absolute brush heights" image graph
	String name = MakeGraphName("heightsabs")
	Display/N=$name
	Appendimage addedw
	ModifyImage $added ctab={*,*,Gold,0}
	ModifyGraph width=300,height=300, margin(right)=90
	ColorScale/C/N=scale/F=0/A=RC/X=-28 image=$added, "absolute brush height (nm)"
	PutDFNameOnGraph()
	DoUpdate
	
	scatterplots(img, bheights, added, nobrushrel, nobrushabs)
End


Function scatterplots(img, bheights, added, nobrushrel, nobrushabs)
	String img, bheights, added, nobrushrel, nobrushabs
	
	Variable doabs = 0
	if (cmpstr(added, "") == 0)
		// skip absolute brush height
		doabs = 0
	endif
	
	WAVE imgw = $img
	WAVE bheightsw = $bheights
	
	if (doabs)
		WAVE addedw = $added
	endif
	
	String graphname = ""
	
	// Create relative "zero brush height" line (y = -x)
	Make/N=10/O $nobrushrel
	WAVE nobrushrelw = $nobrushrel
	WaveStats/Q imgw
	SetScale/I x, V_min, V_max, nobrushrelw
	nobrushrelw = -x
	
	// Display scatterplot relative brush heights
	graphname = "scatter_rel"
	Display/N=$graphname bheightsw vs imgw
	ModifyGraph marker=19,msize=1.5,rgb=(0,0,0),mode=3
	AppendToGraph nobrushrelw
	SetAxis/A
	SetAxis/A/E=1 left
	ModifyGraph standoff(bottom)=0,zero(left)=1
	Label left "brush height (nm)"
	Label bottom "feature depth (nm)"
	Tag/C/N=surface/AO=1/X=0/Y=-5/B=1/G=(65280,0,0)/F=0/L=0 $nobrushrel, ((V_min+V_max)/2), "gold surface"
	PutDFNameOnGraph()
	DoUpdate
	
	if (doabs)
		// Create absolute "zero brush height" line (y=x)
		Make/N=10/O $nobrushabs
		WAVE nobrushabsw = $nobrushabs
		SetScale/I x, V_min, V_max, nobrushabsw
		nobrushabsw = x
		
		// Display scatterplot absolute brush heights
		graphname = "scatter_abs"
		Display/N=$graphname addedw vs imgw
		ModifyGraph marker=19,msize=1.5,rgb=(0,0,0),mode=3
		AppendToGraph nobrushabsw
		SetAxis/A
		ModifyGraph standoff(bottom)=0
		Label left "absolute brush height (nm)\r(feature depth + brush height)"
		Label bottom "feature depth (nm)"
		ModifyGraph lblMargin(left)=10
		ModifyGraph zero=1
		Tag/C/N=hardwall/AO=1/X=0/Y=-5/B=1/G=(65280,0,0)/F=0/L=0 $nobrushabs, ((V_min+V_max)/2), "hardwall"
		Tag/C/N=surface/O=0/X=7/Y=.5/B=1/G=(0,0,0)/F=0/L=0 left, 0, "gold surface"
		PutDFNameOnGraph()
		DoUpdate
	endif
End

Function plot_color(hole, edge, top, textpos)
	Variable hole, edge, top		// X coords where the region ends (upper edge)
	Variable textpos					// Where region text gets placed vertically (y-axis value)
	
	// Draw colors on background
	SetDrawLayer/K UserBack
	SetDrawEnv save, xcoord=bottom, ycoord=prel, linethick=0, fillpat=1
	
	GetAxis/Q bottom
	Variable brange = V_max - V_min
	
	// hole region, light blue color
	SetDrawEnv fillfgc=(48896,52992,65280)
	DrawRect V_min, 0, hole, 1
	
	// edge region, light orange color
	SetDrawEnv fillfgc=(65280,59904,48896)
	DrawRect hole, 0, edge, 1
	
	// top region, light green color
	SetDrawEnv fillfgc=(57344,65280,48896)
	DrawRect edge, 0, top, 1
	
	// Put text above regions
	SetDrawEnv save, fstyle=1, ycoord=left, xcoord=bottom
	SetDrawEnv textrgb=(0,0,65280)
	DrawText ((V_min+hole)/2)-0.035*brange, textpos, "hole"
	SetDrawEnv textrgb=(52224,34816,0)
	DrawText ((hole+edge)/2)-0.03*brange, textpos, "edge"
	SetDrawEnv textrgb=(0,26112,13056)
	DrawText ((edge+top)/2)-0.05*brange, textpos, "surface"
End


// Automatically selects regions to color
// Find lower bound of surface ("edge") by fitting gaussian to normalized histogram
// and defining the surface where the density drops below .05
// Upper bound of surface ("top") is max depth value
// Upper bound of hole ("hole") is 60% from min depth value to "edge"
Function plot_color_auto(textpos)
	Variable textpos			// Where region text gets placed vertically (y-axis value)
	
	Variable fracHole = .6
	Variable densityLimit = .05
	Variable binSize = .5
	Variable histLimitForFit = .1
	Variable histLimitFitted = .05
	
	WAVE/Z depths = WaveRefIndexed("", 0, 2)
	
	if (WaveExists(depths) == 0)
		print "Error: No X wave found in top graph"
		return -1
	endif
	
	WaveStats/Q depths
	
	// ceil to next 0.5 step
	Variable top = ceil(V_max*2)/2
	
	Variable depthmin = V_min
	
	Variable bins = ceil((V_max - V_min)/binSize + 5)	
	Make/FREE/N=(bins) hist
	Histogram/P/C/B={V_min - 1, binSize, bins} depths, hist
	
	WaveStats/Q hist
	FindLevel/EDGE=1/P/R=[V_maxRowLoc,0]/Q hist, histLimitForFit
	if (V_flag != 0)
		print "Error: Histogram could not be fit"
		return -1
	endif
	
	CurveFit/Q gauss, hist[ceil(V_LevelX),]
	WAVE W_coef
	Variable f_y0 = W_coef[0]
	Variable f_A = W_coef[1]
	Variable f_x0 = W_coef[2]
	Variable f_s = W_coef[3]
	Variable f_y = histLimitFitted
	
	// Invert gauss function to get x value for given y
	Variable f_x = f_x0 - f_s * sqrt(ln(f_A/(f_y - f_y0)))
	
	// round to closest 0.5
	Variable edge = round(f_x*2) / 2
	
	Variable hole = depthmin + (edge - depthmin) * fracHole
	hole = round(hole*2) / 2
	
	printf "hole: %g,  edge: %g,  top: %g\r", hole, edge, top
	
	plot_color(hole, edge, top, textpos)
	
End


// Lists are in format: "new_combined_wave;old_wave1;old_wave2;..."
Function absrelheights_combine(imglist, bheightlist, absheightlist, nobrushrel, nobrushabs)
	String imglist, bheightlist, absheightlist, nobrushrel, nobrushabs
	
	Variable numimg = ItemsInList(imglist)
	Variable numbheight = ItemsInList(bheightlist)
	Variable numabsheight = ItemsInList(absheightlist)
	
	if ((numimg != numbheight) || (numimg != numabsheight))
		print "ERROR: non-matching list lenghts"
		return -1
	endif
	
	String newimg = StringFromList(0, imglist)
	imglist = RemoveListItem(0, imglist)
	
	String newbheight = StringFromList(0, bheightlist)
	bheightlist = RemoveListItem(0, bheightlist)
	
	String newabsheight = StringFromList(0, absheightlist)
	absheightlist = RemoveListItem(0, absheightlist)
	
	
	// Concatenate old to new waves
	Concatenate/O imglist, $newimg
	Redimension/N=(numpnts($newimg)) $newimg
	
	Concatenate/O/NP bheightlist, $newbheight
	
	Concatenate/O absheightlist, $newabsheight
	Redimension/N=(numpnts($newabsheight)) $newabsheight
	
	
	scatterplots(newimg, newbheight, newabsheight, nobrushrel, nobrushabs)
End


Function filterbydepth(from, to, depth, input, output)
	Variable from, to		// Depth values to include in filtered output (inclusive)
	String depth				// Input depth wave name
	String input				// Input height wave name
	String output			// Output height wave name (will be created/overwritten, same size as input wave	
								// with NaN for excluded points
	
	WAVE d = $depth
	WAVE i = $input
	
	Duplicate/O i, $output
	WAVE o  = $output
	o = NaN
	
	Variable j
	for (j=0; j < numpnts(i); j+=1)
		if ((d[j] >= from) && (d[j] <= to))
			o[j] = i[j]
		endif
	endfor	
End

// Create histogram of brush heights
Function BrushHisto(binsize)
	Variable binsize  // nm
	Variable binmin = -5		// nm
	
	WAVE brushheights
	Variable binmax = GetUpperPercentile(brushheights, 99)
	// Round to upper decade
	binmax = 10*ceil(binmax/10)
	
	Variable bins = ceil((binmax - binmin)/binsize)
	Make/O/N=(bins) brushheights_histo = 0
	WAVE brushheights_histo
	Histogram/P/B={binmin, binsize, bins} brushheights, brushheights_histo
	
	Display brushheights_histo
	String name = MakeGraphName("bhisto")
	DoWindow/C $name
	ModifyGraph mode=5, hbFill=2, useBarStrokeRGB=1
	PutDFNameOnGraph()
End


// waves: StringList of wave names (";" as separator)
// from, to: average wave range [from, to] (both inclusive)
// wavg, wsd: waves for averaged values and standard deviations
Function AvgWaves(waves, from, to, wavg, wsd)
	String waves
	Variable from, to
	WAVE wavg, wsd
	
	if ((numpnts(wavg) < (to-from+1)) || (numpnts(wsd) < (to-from+1)))
		Print "Target wave is not big enough"
		return -1
	endif
	
	Variable i = 0
	String wname
	Make/O/WAVE/FREE wlist
	
	do
		wname = StringFromList(i, waves, ";")
		if (strlen(wname) == 0)
			break
		endif
		if (WaveExists($wname) == 0)
			break
		endif
		
		wlist[i] = $wname
		i += 1
		
	while (1)
	
	Variable wnum = i
	
	Print num2str(wnum) + " input waves"
	
	Variable j
	Variable k = 0
	Make/N=(wnum)/FREE wrow
	
	for (i=from; i <= to; i+=1)
		wrow = 0
		for (j=0; j < wnum; j+=1)
			WAVE w = wlist[j]
			wrow[j] = w[i]
		endfor
		WaveStats/Q wrow
		wavg[k] = V_avg
		wsd[k] = V_sdev
		k += 1
	endfor
	
	return 0
End


Function PrintInfo()
	String ig = StrVarOrDefault(":internalvars:imagegraph", "")
	String iw = StrVarOrDefault(":internalvars:imagewave", "")
	String rg = StrVarOrDefault(":internalvars:resultgraph", "")
	String rw = StrVarOrDefault(":internalvars:resultwave", "")
	String sel = StrVarOrDefault(":internalvars:selectionwave", "")
	String path = StrVarOrDefault(":internalvars:totalpath", "")
	String params = StrVarOrDefault(":internalvars:analysisparameters", "")
	print "IMAGE graph: " + ig + ",  wave: " + iw
	print "BRUSHHEIGHTS graph: " + rg + ",  wave: " + rw
	print "selectionwave: " + sel + ",  totalpath: " + path
	print "analysis parameters: " + params
End

Function PrintInfoDF(df)
	String df		// data folder (without 'root:' part) to print info from
	String fullDF = "root:" + df
	DFREF prevDF = GetDataFolderDFR()
	SetDataFolder fulldf
	PrintInfo()
	SetDataFolder prevDF
End


Function SubtractBaseline()
	
	if (cmpstr(CsrInfo(A), "") == 0)
		String dataname = "fc_z"
		Prompt dataname, "Data wave name"
		DoPrompt "", dataname
		WAVE/Z data = $dataname
		if (!WaveExists(data))
			print "Abort: No wave: " + dataname
			return -1
		endif
	else
		WAVE data = CsrWaveRef(A)
	endif
	
	SaveBackupWave(NameOfWave(data), "baselinesubtr")
	
	Make/FREE/N=(numpnts(data)) mask = 1
	
	
	// Check all cursors (A to J, ASCII 65-74)
	// And exclude data between pairs of cursors
	String cname1 = "", cname2 = ""
	Variable pairs = 0
	
	Variable i = 0
	for (i=65; i<=73; i+=2)
		cname1 = num2char(i)
		cname2 = num2char(i+1)
		if (cmpstr(CsrInfo($cname1), "") != 0 && cmpstr(CsrInfo($cname2), "") != 0)
			if (WaveRefsEqual(CsrWaveRef($cname1), data) && WaveRefsEqual(CsrWaveRef($cname2), data))
				// Cursor pair exists and is on data wave
				mask[pcsr($cname1), pcsr($cname2)] = 0
				pairs += 1
			endif
		else
			break
		endif
	endfor
	
	print "Baseline fitting, excluding " + num2str(pairs) + " regions."
	CurveFit/Q line, data /M=mask
	WAVE W_coef
	data -= W_coef[0] + W_coef[1]*x
	
	return 0
End


Function SaveBackupWave(orig, suffix)
	String orig		// original wave to be backed up (in current folder)
	String suffix	// name for backed up wave with <orig>_<suffix> (automatically in backups subfolder)
	
	WAVE w = $orig
	
	NewDataFolder/O backups
	String backname = NameOfWave(w) + "_" + suffix
	Duplicate/O w, :backups:$backname
End


Function RestoreBackupWave(orig, suffix)
	String orig		// orig wave name, will be restored into
	String suffix	// suffix in backup folder
	
	String backupname = orig + "_" + suffix
	
	WAVE/Z backupw = :backups:$backupname
	
	if (!WaveExists(backupw))
		print "Backup wave not found: " + backupname
		return -1
	endif
	
	Duplicate/O backupw, $orig
End

Function MakeTempCurve(name, orig, idx)
	String name		// name of duplicated temp wave
	String orig		// original wave (2D)
	Variable idx		// curve index to duplicate; -1 if taken from graph
	
	if (idx < 0)
		GetWindow kwTopWin, userdata
		idx = NumberByKey("index", S_Value)
	endif
	
	
	WAVE fc = $orig
	
	WAVE/T fcmeta
	
	Duplicate/O/R=[][idx] fc, $name
	WAVE dup = $name
	Redimension/N=(numpnts(dup)) dup
	Note dup, "orig:" + num2str(idx)
End


// Takes section between markers A and B and does linear baseline
// subtraction, and afterwards FFT on it.
Function MakeCurveFFT(wname)
	String wname		// name of wave from which to make FFT
						// FFT is saved in wname_fft
						// and the baseline subtracted wave in wname_tempfft.
						// if empty, use first trace of top graph.
	
	if (strlen(wname) == 0)
		WAVE wtemp1 = WaveRefIndexed("", 0, 1)
		wname = WaveName("", 0, 1)
		WAVE wtemp2 = $wname
		if (!WaveRefsEqual(wtemp1, wtemp2))
			print "Couldn't select wave (correct datafolder?)"
			return -1
		endif
	endif
	
	
	
	WAVE w = $wname
	Duplicate/O w, $(wname + "_linsub")
	WAVE wtemp = $(wname + "_linsub")
	
	Redimension/N=(floor(pcsr(B)/2)*2 - floor(pcsr(A)/2)*2) wtemp
	wtemp[] = w[p+floor(pcsr(A)/2)*2]
	CurveFit/Q line, wtemp
	WAVE W_coef
	wtemp -= W_coef[0] + W_coef[1]*x
	
	FFT/MAGS/DEST=$(wname + "_fft") wtemp
End


// Measure oscillation frequency between two markers (A,B)
Function oscfreq(reswave, curve, rrate)
	String reswave		// results wave in root folder
	String curve			// curve wave (2D wave)
	Variable rrate			// ramp rate in Hz
	
	Variable makenew = 0
	WAVE/Z freqs = $("root:" + reswave)
	
	if (WaveExists(freqs))
		if (DimSize(freqs, 1) != 3)
			DoAlert 1, "Result wave has incorrect form, overwrite?"
			if (V_flag == 1)
				makenew = 1
			else
				Abort
			endif
		endif
	else
		makenew = 1
	endif
	
	if (makenew)
		Make/N=(100,3)/O $("root:" + reswave) = NaN
		WAVE freqs =  $("root:" + reswave)
	endif
	
	Wavestats/Q/M=1/R=[0,DimSize(freqs,0)-1] freqs
	Variable nextpt = V_npnts
	if (nextpt >= DimSize(freqs,0))
		// extend result wave because its full
		Redimension/N=(DimSize(freqs,0)+50) freqs
	endif
	
	
	MakeTempCurve("fctemp", curve, -1)
	
	MakeCurveFFT("fctemp")
	
	GetWindow kwTopWin, userdata
	Variable i = NumberByKey("index", S_Value)
	
	WAVE fctemp, fctemp_linsub, fctemp_fft
	WAVE/T fcmeta
	
	Wavestats/Q/M=1 fctemp_fft
	Variable osclength = 1/V_maxloc
	
	// osc. length in nm
	freqs[nextpt][0] = osclength
	// curve number
	freqs[nextpt][1] = i
	// osc freq in Hz
	freqs[nextpt][2] = 2.0 * rrate * NumberByKey("rampsize", fcmeta[i]) / osclength
	
	// display fft and curve, and results table
	DoWindow/F oscfftgra
	if (V_flag == 0)
		Display/L/B fctemp_fft
		AppendToGraph/T/R fctemp_linsub
		DoWindow/C oscfftgra
		
		ModifyGraph lsize(fctemp_fft)=1.5, rgb(fctemp_fft)=(0,0,0)
		SetAxis bottom 0,0.7
	else
		ReplaceWave/W=oscfftgra allinCDF
	endif
	
	DoWindow/F oscffttab
	if (V_flag == 0)
		Edit freqs
		DoWindow/C oscffttab
	endif
End


Function FilterOsc(rate)
	Variable rate		// ramp rate in Hz
	
	NVAR fcpoints = :internalvars:FCNumPoints
	NVAR numcurves = :internalvars:numCurves
	
	Variable samprate = rate * 2.0 * fcpoints
	
	Variable fir_center = 250	// Hz
	Variable fir_width = 300		// Hz
	Variable fir_eps = 1e-14
	Variable fir_nmult = 2
	
	Variable fir_center_frac = fir_center / samprate
	Variable fir_width_frac = fir_width / samprate
	
	WAVE fc, rfc, fc_x_tsd, rfc_x_tsd
	WAVE/T fcmeta
	Duplicate/O fc, fc_orig
	Duplicate/O rfc, rfc_orig
	Duplicate/O fc_x_tsd, fc_x_tsd_orig
	Duplicate/O rfc_x_tsd, rfc_x_tsd_orig
	
	Variable i
	Variable springc = 0
	for (i=0; i < numcurves; i+=1)
		Duplicate/FREE/O/R=[][i] fc, fctemp
		FilterFIR/NMF={fir_center_frac, fir_width_frac, fir_eps, fir_nmult} fctemp
		fc[][i] = fctemp[p]
		// recalc tip-sample dist
		Duplicate/FREE/O/R=[][i] fc, fctemp_xtsd
		springc = NumberByKey("springConst", fcmeta[i])
		fctemp /= springc * 1000
		fctemp_xtsd = NumberByKey("rampSize", fcmeta[i])/fcpoints * p
		fctemp_xtsd += fctemp
		fc_x_tsd[][i] = fctemp_xtsd[p]
		
		// retraction curve same thing
		Duplicate/FREE/O/R=[][i] rfc, fctemp
		FilterFIR/NMF={fir_center_frac, fir_width_frac, fir_eps, fir_nmult} fctemp
		rfc[][i] = fctemp[p]
		Duplicate/FREE/O/R=[][i] rfc, fctemp_xtsd
		fctemp /= springc * 1000
		fctemp_xtsd = NumberByKey("rampSize", fcmeta[i])/fcpoints * p
		fctemp_xtsd += fctemp
		rfc_x_tsd[][i] = fctemp_xtsd[p]
		
		
		Prog("Filtering", i, numcurves)
	endfor
	
End


// Shows parameters from different possible sources:
// analysis params, fc metadata
Function PrintParams(params, idx)
	String params		// semicolon-separated list of parameters
	Variable idx
	
	SVAR/Z aparams = :internalvars:analysisparameters
	if (!SVAR_Exists(aparams))
		aparams = ""
	endif
	
	WAVE/Z/T fcmeta
	
	Variable i
	String currparam = ""
	String currres = ""
	String out = ""
	for (i=0; i < ItemsInList(params); i+=1)
		out += "\r"
		currparam = StringFromList(i, params)
		currres = StringByKey(currparam, aparams)
		
		if (strlen(currres) > 0)
			out += currparam + "[analysis]: " + currres
			continue
		endif
		
		if (WAVEExists(fcmeta) && idx >= 0)
			currres = StringByKey(currparam, fcmeta[idx])
		endif
		
		if (strlen(currres) > 0)
			out += currparam + "[" + num2str(idx) + "]: " + currres
			continue
		endif	
	endfor
	
	print out
	
//	String res = ""
//	
//	SVAR/Z aparams = :internalvars:analysisparameters
//	if (SVAR_Exists(aparams))
//		res = StringByKey(param, aparams)
//	endif
//	
//	if (strlen(res) > 0)
//		print param + ": " + res
//	endif
//	
//	WAVE/Z/T fcmeta
//	res = ""
//	if (WAVEExists(fcmeta) && idx >= 0)
//		res = StringByKey(param, fcmeta[idx])
//	endif
//	
//	if (strlen(res) > 0)
//		print param + "[" + num2str(idx) + "]: " + res
//	endif
	
End