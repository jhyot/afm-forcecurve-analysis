#pragma rtGlobals=3		// Use modern global access method.


Function Analysis()

	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
		
	NVAR/Z analysisDone = :internalvars:analysisDone
	NVAR/Z nodialogsnvar = :internalvars:noDialogs
	Variable nodialogs = 0
	if (NVAR_Exists(nodialogsnvar))
		nodialogs = nodialogsnvar
	endif
	if (nodialogs == 0 && NVAR_Exists(analysisDone) && analysisDone == 1)
		String alert = ""
		alert = "Analysis has been run already on this data folder.\r"
		alert += "Re-running can lead to wrong results. Continue anyway?"
		DoAlert 1, alert
		
		if (V_flag != 1)
			print "Analysis canceled by user"
			return -1
		endif
	endif

	NVAR numcurves = :internalvars:numCurves
	Variable result=-1
	
	Variable i, t0=ticks
	
	SVAR selectionwave = :internalvars:selectionwave
	
	WAVE retractfeature

	WAVE sel=$selectionwave

	WAVE/T fcmeta
	WAVE fc, rfc
	String header
	
	// Save analysis parameters, or compare if already saved
	SVAR/Z params = :internalvars:analysisparameters
	NVAR rowsize = :internalvars:FVRowSize
	NVAR fcpoints = :internalvars:FCNumPoints
	
	Variable conflict = 0
	String conflictStr = ""
	
	if (SVAR_Exists(params))
		if (fcpoints != NumberByKey("FCNumPoints", params))
			conflict = 1
			conflictstr += "FCNumPoints"
			conflictstr += "\r"
		endif
		if (rowsize != NumberByKey("FVRowSize", params))
			conflict = 1
			conflictstr += "FVRowSize"
			conflictstr += "\r"
		endif
		if (ksBaselineFitLength != NumberByKey("ksBaselineFitLength", params))
			conflict = 1
			conflictstr += "ksBaselineFitLength"
			conflictstr += "\r"
		endif
		if (ksBrushCutoff != NumberByKey("ksBrushCutoff", params))
			conflict = 1
			conflictstr += "ksBrushCutoff"
			conflictstr += "\r"
		endif
		if (ksBrushOverNoise != NumberByKey("ksBrushOverNoise", params))
			conflict = 1
			conflictstr += "ksBrushOverNoise"
			conflictstr += "\r"
		endif
		if (ksDeflSens_ContactLen != NumberByKey("ksDeflSens_ContactLen", params))
			conflict = 1
			conflictstr += "ksDeflSens_ContactLen"
			conflictstr += "\r"
		endif
		if (ksDeflSens_EdgeFraction != NumberByKey("ksDeflSens_EdgeFraction", params))
			conflict = 1
			conflictstr += "ksDeflSens_EdgeFraction"
			conflictstr += "\r"
		endif
		if (ksFixDefl != NumberByKey("ksFixDefl", params))
			conflict = 1
			conflictstr += "ksFixDefl"
			conflictstr += "\r"
		endif
		if (ksXDataZSens != NumberByKey("ksXDataZSens", params))
			conflict = 1
			conflictstr += "ksXDataZSens"
			conflictstr += "\r"
		endif
		if (ksMaxGoodPt != NumberByKey("ksMaxGoodPt", params))
			conflict = 1
			conflictstr += "ksMaxGoodPt"
			conflictstr += "\r"
		endif
	else
		String/G :internalvars:analysisparameters = ""
		SVAR params = :internalvars:analysisparameters
	endif
	
	if (conflict)
		alert = "Some analysis parameters do not match previously used ones for this data set.\r"
		alert += "Continuing can lead to inconsistent results. Old parameters will be lost. Continue anyway?\r\r"
		alert += conflictstr
		DoAlert 1, alert
		
		if (V_flag != 1)
			print "Analysis canceled by user"
			return -1
		endif
	endif
	
	params = ReplaceNumberByKey("FCNumPoints", params, fcpoints)
	params = ReplaceNumberByKey("FVRowSize", params, rowsize)
	params = ReplaceNumberByKey("ksBaselineFitLength", params, ksBaselineFitLength)
	params = ReplaceNumberByKey("ksBrushCutoff", params, ksBrushCutoff)
	params = ReplaceNumberByKey("ksBrushOverNoise", params, ksBrushOverNoise)
	params = ReplaceNumberByKey("ksDeflSens_ContactLen", params, ksDeflSens_ContactLen)
	params = ReplaceNumberByKey("ksDeflSens_EdgeFraction", params, ksDeflSens_EdgeFraction)
	params = ReplaceNumberByKey("ksFixDefl", params, ksFixDefl)
	params = ReplaceNumberByKey("ksXDataZSens", params, ksXDataZSens)
	params = ReplaceNumberByKey("ksMaxGoodPt", params, ksMaxGoodPt)
	
	
	// Create 2d waves for Analysis
	Make/N=(fcpoints/8, numcurves)/O fc_sensfit = NaN
	Make/N=(fcpoints, numcurves)/O fc_x_tsd = NaN
	Make/N=(fcpoints, numcurves)/O fc_expfit = NaN
	Make/N=(fcpoints, numcurves)/O fc_smth = NaN
	Make/N=(fcpoints, numcurves)/O fc_smth_xtsd = NaN
	
	Make/N=(fcpoints, numcurves)/O rfc_x_tsd = NaN
	
	
	// brushheights: 1D wave to hold analysed brush heights and NaN if not analysed
	// heightsmap: 2D (redimension later) with -100 instead of NaN
	// deflsensused: 1D wave to hold used deflection sensitivities
	// blnoise: 1D wave to hold calculated baseline noise
	WAVE brushheights
	Make/N=(numcurves)/O heightsmap = NaN
	Make/N=(numcurves)/O deflsensfit = NaN
	Make/N=(numcurves)/O deflsensused = NaN
	Make/N=(numcurves)/O deflsenserror_used = NaN
	Make/N=(numcurves)/O deflsenserror_orig = NaN
	Make/N=(numcurves)/O blnoise = NaN
	Make/N=(numcurves)/O hardwallforce = NaN
	
	// Running analysis changes the "raw" data (rescales it in-place)
	// Set flag immediately before analysis starts to warn the user if he re-runs the analysis
	// Now corrected in code, so re-running analysis doesn't corrupt data. But keep warning anyway.
	Variable/G :internalvars:analysisDone = 1
	
	NVAR loadfric = :internalvars:loadFriction
	NVAR zsensloaded = :internalvars:isZsensLoaded
	
	Variable messageonce = 1
	
	SVAR/Z yUnits = :internalvars:yUnits
	if (!SVAR_Exists(yUnits))
		String/G :internalvars:yUnits = "LSB"
	endif
	
	for (i=0; i < numcurves; i+=1)
	
		if(sel[i])
		
			// *** Call analysis function here***
			if (ksXDataZSens == 2 && !zsensloaded)
				print "ERROR: Forced use of Z sensor data, but data not loaded/available."
				return -1
			else
				result = AnalyseBrushHeight4(i, brushheights)
			endif
			
			
			if(result < 0)
				//could not determine brush height
				heightsmap[i] = -100
			else
				heightsmap[i] = brushheights[i]
			endif
			
			// Re-read metadata; has been changed/expanded by analysis code above
			header = fcmeta[i]
			deflsensfit[i] = NumberByKey("deflSensFit", header)
			deflsensused[i] = NumberByKey("deflSensUsed", header)
			deflsenserror_used[i] = deflsensfit[i] - deflsensused[i]
			deflsenserror_orig[i] = deflsensfit[i] - NumberByKey("deflSens", header)
			blnoise[i] = NumberByKey("blNoiseRaw", header)
			Variable hwpt = NumberByKey("hardwallPt", header)
			if (numtype(hwpt) == 0 && hwpt >= 0 && hwpt < fcpoints)
				hardwallforce[i] = fc[NumberByKey("hardwallPt", header)][i]
			else
				hardwallforce[i] = NaN
			endif
			
			// Process retract curve
			RetractTSD3(i)
			
			// Process friction curve
			if (loadfric)
				FricBaseline(i)
			endif
		endif
		
		Prog("Analysis",i,numcurves)
		
	endfor
	
	
	Variable rampSize = NumberByKey("rampSizeUsed", header)		// header has still data from last analyzed curve
			
	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (rampSize), "nm", fc
	SetScale/I x 0, (rampSize/8), "nm", fc_sensfit
	SetScale/I x 0, (rampSize), "nm", fc_expfit
	SetScale/I x 0, (rampSize), "nm", rfc
	
	if (loadfric)
		WAVE fc_fric, rfc_fric
		SetScale/I x, 0, (rampSize), "nm", fc_fric
		SetScale/I x, 0, (rampSize), "nm", rfc_fric
	endif
	
	String/G :internalvars:yUnits = "pN"

	printf "Elapsed time: %g seconds\r", round(10*(ticks-t0)/60)/10
	
	print TidyDFName(GetDataFolder(1))
	print "brushheights:"
	WaveStats brushheights
	
	NVAR singlefc = :internalvars:singleFCs
		
	if (singlefc && (rowsize == 0))
		// single curves and not a grid
		
		// check whether result graph already exists. If no, create new
		SVAR/Z resultg = :internalvars:resultgraph
		
		if (SVAR_Exists(resultg))
			MapToForeGround()
		else
			PlotXsectFC()
		endif
	else
		Redimension/N=(rowsize,rowsize) heightsmap
		
		String/G :internalvars:resultwave = "heightsmap"
		
		// check whether result graph already exists. If no, create new
		SVAR/Z resultg = :internalvars:resultgraph
		
		if (SVAR_Exists(resultg))
			MapToForeGround()
		else
			ShowResultMap()
		endif
		
		SVAR imagegraph = :internalvars:imagegraph
		SetWindow $imagegraph,hook(imageinspect)=inspector
	endif
	
	return 0
End


// Analyse brush height, performing all the necessary data processing steps.
// Works in the current data folder with the wave named fc<i> with <i> being the index parameter.
// Returns 0 if all is successful, -1 otherwise.
//
// NOTE: A lot of parameters/assumptions are hardcoded here for brush extend FC curves with 4096 points
// (todo: change this in future)
Function AnalyseBrushHeight1(index, wHeights)
	Variable index
	WAVE wHeights
	
	Variable V_fitOptions = 4		// suppress CurveFit progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	WAVE fc
	WAVE fc_blfit, fc_sensfit, fc_x_tsd, fc_expfit
	Make/FREE/N=(fcpoints) w, blfit, xTSD, expfit
	Make/FREE/N=(fcpoints/8) sensfit
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	w[] = fc[p][index]

	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", w
	
	String wname = "fc" + num2str(index)
	
	// Convert y axis to V
	w *= NumberByKey("VPerLSB", header)
	
	// Fit baseline and subtract from curve
	CurveFit/NTHR=1/Q line  w[2600,3600]
	WAVE W_coef
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", blfit

	blfit = W_coef[0] + W_coef[1]*x
	// Subtr. baseline
	w -= (W_coef[0] + W_coef[1]*x)
	
	// Sometimes last points of curve are at smallest LSB value
	// Set those to 0 (i.e. if value < -3 V)
	w[3600,] = (w[p] > -3) * w[p]
	
	// Fit deflection sensitivity and change y scale
	CurveFit/NTHR=1/Q line  w[10,100]
	SetScale/I x 0, (NumberByKey("rampSize", header)/8), "nm", sensfit

	sensfit = W_coef[0] + W_coef[1]*x
	Variable deflSens = -1/W_coef[1]
	// Add fitted sens. to header data
	header += "deflSensUsed:" + num2str(deflSens) + ";"
	fcmeta[index] = header
	// Change y scale on all curves to nm
	w *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/fcpoints * p
	// Subtract deflection to get tip-sample-distance
	xTSD += w
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000
	blfit *= springConst * 1000
	sensfit *= springConst * 1000
	SetScale d 0,0,"pN", w, blfit, sensfit
	
	// Shift hard wall contact point to 0 in xTSD
	WaveStats/R=[10,100]/Q xTSD
	xTSD -= V_avg
	
	// write back curves to 2d wave
	fc[][index] = w[p]
	fc_blfit[][index] = blfit[p]
	fc_sensfit[][index] = sensfit[p]
	fc_x_tsd[][index] = xTSD[p]
	
	// Find start point for exponential fit:
	// Sliding box average (31 pts) crosses 1 nm
	FindLevel/B=31/EDGE=1/P/Q xTSD, 1
	if (V_flag != 0)
		Print wname + ": Starting point for exp fit not found"
		return -1
	endif
	Variable expFitStart = floor(V_levelX)
	// If expFitStart at very low force, add some additional points to fit range,
	// otherwise Curvefit will have difficulties to fit an exponential
	if (w[expFitStart] < 25)
		expFitStart -= 50
	endif
	
	// Write start point to header note
	header += "expFitStartPt:" + num2str(expFitStart) + ";"
	fcmeta[index] = header
	
	// Find end point for exp fit the same way
	FindLevel/B=31/EDGE=2/P/Q w, 1
	if (V_flag != 0)
		Print wname + ": End point for exp fit not found"
		return -1
	endif
	Variable expFitEnd = floor(V_levelX)
	// Add some additional points to range end
	// If calculated end point very near 0, add a bit less to make a better fit
	if (xTSD[expFitEnd] < 3)
		expFitEnd += 200
	else
		expFitEnd += 500
	endif
	// Write end point to header note
	header += "expFitEndPt:" + num2str(expFitEnd) + ";"
	fcmeta[index] = header
	
	// Fit exponential curve to force-vs-tsd
	Variable V_fitError = 0		// prevent abort on error
	CurveFit/NTHR=1/Q exp_XOffset w[expFitStart,expFitEnd]/X=xTSD
	if (V_fitError)
		Print wname + ": Error doing CurveFit"
		return -1
	endif
	
	// Write some values to header note
	header += "expFitChiSq:" + num2str(V_chisq) + ";"
	header += "expFitTau:" + num2str(W_coef[2]) + ";"
	header += "expFitBL:" + num2str(W_coef[0]) + ";"
	fcmeta[index] = header
	
	WAVE W_fitConstants
	// Set scale to match the tsd x scale
	SetScale/I x 0, (NumberByKey("rampsize", header)), "nm", expfit
	SetScale d 0, 0, "pN", expfit
	expfit = W_coef[0]+W_coef[1]*exp(-(x-W_fitConstants[0])/W_coef[2])
	
	// write back curves to 2d wave
	fc_expfit[][index] = expfit[p]
	
	// Point in FC where force is given amount higher than expfit baseline
	// equals brush start (defined arbitrarily)
	Variable heightP = BinarySearch(expfit, W_coef[0] + ksBrushCutoff)
	if (heightP < 0)
		Print wname + ": Brush start point not found"
		return -1
	endif
	Variable height = pnt2x(expfit, heightP+1)
	
	//Print wname + ": Brush height = " + num2str(height)
	wHeights[index] = height

	return 0
End


// Test of different brush height algorithm
// Changes from original AnalyseBrushHeight:
// * exactly find last good point (sometimes at the end data set to smallest LSB value)
// * Baseline fit for last third part of curve (up to last good point)
// * get start of hardwall part
// * new defl sens fitting in hardwall part
// * start point for exp fit from hardwall end
// * use constant ksBrushCutoff to get brush height
Function AnalyseBrushHeight2(index, wHeights)
	Variable index
	WAVE wHeights
	
	Variable V_fitOptions = 4		// suppress CurveFit progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	WAVE fc
	WAVE fc_blfit, fc_sensfit, fc_x_tsd, fc_expfit
	Make/FREE/N=(fcpoints) w, blfit, xTSD, expfit
	Make/FREE/N=(fcpoints/8) sensfit
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	w[] = fc[p][index]

	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", w
	
	String wname = "fc" + num2str(index)
	
	// Sometimes last points of curve are at smallest LSB value
	// Set those to 0 (after baseline substraction)
	Variable lastGoodPt = numpnts(w) - 1
	FindLevel/Q/P w, (-1*2^15 + 1)
	if (V_flag == 0)
		lastGoodPt = floor(V_LevelX) - 1
	endif
	
	header += "lastGoodPt:" + num2str(lastGoodPt) + ";"
	
	// Convert y axis to V
	w *= NumberByKey("VPerLSB", header)
	
	// Fit baseline and subtract from curve (last third of curve)
	CurveFit/NTHR=1/Q line  w[round(lastGoodPt*0.67),lastGoodPt]
	WAVE W_coef
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", blfit

	blfit = W_coef[0] + W_coef[1]*x
	// Subtr. baseline
	w -= (W_coef[0] + W_coef[1]*x)
	// remove not real data (smallest LSB)
	if ((lastGoodPt+1) < fcpoints)
		w[lastGoodPt+1,] = 0
	endif
	
	// Fit deflection sensitivity and change y scale
	Make/FREE/N=(fcpoints) w1, w2, w3
	Duplicate/O w, w1
	Smooth/E=3/B 501, w1
	Differentiate w1/D=w2
	Duplicate/O w2, w3
	Smooth/M=0 501, w3
	WaveStats/Q w3
	EdgeStats/Q/A=30/P/R=[V_minRowLoc, lastGoodPt]/F=0.05 w3
	
	Variable hardwallPt = round(V_EdgeLoc1)
	header += "hardwallPt:" + num2str(hardwallPt) + ";"
	
	CurveFit/NTHR=1/Q line  w[10,hardwallPt]

	SetScale/I x 0, (NumberByKey("rampSize", header)/8), "nm", sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	Variable deflSens = -1/W_coef[1]
	// Add fitted sens. to header data
	header += "deflSensUsed:" + num2str(deflSens) + ";"
	fcmeta[index] = header

	// Change y scale on all curves to nm
	w *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/fcpoints * p
	// Subtract deflection to get tip-sample-distance
	xTSD += w
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000
	blfit *= springConst * 1000
	sensfit *= springConst * 1000
	SetScale d 0,0,"pN", w, blfit, sensfit
	
	// Shift hard wall contact point to 0 in xTSD
	WaveStats/R=[10,hardwallPt]/Q xTSD
	xTSD -= V_avg
	
	// write back curves to 2d wave
	fc[][index] = w[p]
	fc_blfit[][index] = blfit[p]
	fc_sensfit[][index] = sensfit[p]
	fc_x_tsd[][index] = xTSD[p]
	
	// Find end point for exp fit:
	// Sliding box average (31 pts) crosses 1 nm
	FindLevel/B=31/EDGE=2/P/Q w, 1
	if (V_flag != 0)
		Print wname + ": End point for exp fit not found"
		return -1
	endif
	Variable expFitEnd = floor(V_levelX)
	// Add some additional points to range end
	// If calculated end point very near 0, add a bit less to make a better fit
	if (xTSD[expFitEnd] < 3)
		expFitEnd += 200
	else
		expFitEnd += 500
	endif
	// Write end point to header note
	header += "expFitEndPt:" + num2str(expFitEnd) + ";"
	fcmeta[index] = header
	
	// Fit exponential curve to force-vs-tsd
	Variable V_fitError = 0		// prevent abort on error
	CurveFit/NTHR=1/Q exp_XOffset w[hardwallPt,expFitEnd]/X=xTSD
	if (V_fitError)
		Print wname + ": Error doing CurveFit"
		return -1
	endif
	
	// Write some values to header note
	header += "expFitChiSq:" + num2str(V_chisq) + ";"
	header += "expFitTau:" + num2str(W_coef[2]) + ";"
	header += "expFitBL:" + num2str(W_coef[0]) + ";"
	fcmeta[index] = header
	
	WAVE W_fitConstants
	// Set scale to match the tsd x scale
	SetScale/I x 0, (NumberByKey("rampsize", header)), "nm", expfit
	SetScale d 0, 0, "pN", expfit
	expfit = W_coef[0]+W_coef[1]*exp(-(x-W_fitConstants[0])/W_coef[2])
	
	// write back curves to 2d wave
	fc_expfit[][index] = expfit[p]
	
	// Point in FC where force is 1 pN higher than expfit baseline
	// equals brush start (defined arbitrarily)
	Variable heightP = BinarySearch(expfit, W_coef[0] + ksBrushCutoff)
	if (heightP < 0)
		Print wname + ": Brush start point not found"
		return -1
	endif
	Variable height = pnt2x(expfit, heightP+1)

	wHeights[index] = height

	return 0
End


// Convert raw "LSB" force data to voltage
// returns the last good point in curve
Function ConvertRawToV(w, header)
	WAVE w
	String header		// pass by reference
		
	// Sometimes last points of curve are at smallest LSB value
	// Set those to 0 (after baseline substraction)
	Variable lastGoodPt = numpnts(w) - 1
	FindLevel/Q/P w, (-1*2^15 + 1)
	if (V_flag == 0)
		lastGoodPt = floor(V_LevelX) - 1
	endif
	
	// User defined forcing of last good pt
	if (ksMaxGoodPt >= 0)
		lastGoodPt = min(lastGoodPt, ksMaxGoodPt)
	endif
	
	// Convert y axis to V
	w *= NumberByKey("VPerLSB", header)
	
	SetScale d 0,0,"V", w
	
	return lastGoodPt
End


// Convert y data from force units (pN) back to V (for rerunning analysis)
Function ConvertForceToV(w, header)
	WAVE w
	String header		// pass by ref
	
	Variable springConst = NumberByKey("springConst", header)
	w /= springConst * 1000
	
	Variable deflSens = NumberByKey("deflSensUsed", header)
	w /= deflSens
	
	SetScale d 0,0,"V", w
End


// Test of different brush height algorithm
// Changes from original AnalyseBrushHeight2:
// * Brush height from filtered curve directly instead of expfit
// returns:	 0 if fully successful;
//				-1 if analysis not successful;
Function AnalyseBrushHeight3(index, wHeights)
	Variable index
	WAVE wHeights
	
	Variable V_fitOptions = 4		// suppress CurveFit progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	WAVE fc
	WAVE fc_sensfit, fc_x_tsd, fc_expfit, fc_smth, fc_smth_xtsd
	Make/FREE/N=(fcpoints) w, xTSD, expfit, smth, smthXTSD
	Make/FREE/N=(fcpoints/8) sensfit
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	w[] = fc[p][index]

	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", w
	
	String wname = "fc" + num2str(index)
	
	SVAR yUnits = :internalvars:yUnits
	Variable lastGoodPt = NaN
	strswitch (yUnits)
		case "LSB":
			lastGoodPt = ConvertRawToV(w, header)
			break
			
		case "pN":
			lastGoodPt = NumberByKey("lastGoodPt", header)
			ConvertForceToV(w, header)
			break
	endswitch
	
	header = ReplaceNumberByKey("lastGoodPt", header, lastGoodPt)
	
	// ignore curve end in certain operations;
	// the curve might look bad there (e.g. in Z closed loop mode, or with very fast ramping)
	Variable lastGoodPtMargin = round(0.8 * lastGoodPt)
	
	// Fit baseline and subtract from curve
	Variable noiseRange = round(fcpoints / NumberByKey("rampSize", header) * ksDeflSens_ContactLen*2)
	//Variable noiseRange = round(0.1 * lastGoodPt)
	Variable calcStep = round(0.2 * noiseRange)
	Variable currentPt = lastGoodPtMargin - noiseRange
	WaveStats/Q/R=[currentPt - noiseRange, currentPt + noiseRange] w
	Variable baselineNoise = V_sdev
	
	if (calcStep < 1)
		// something went wrong
		fcmeta[index] = header
		print wname + ": Could not find approx. point of interaction start"
		return -1
	endif
	
	currentPt -= calcStep
	do
		WaveStats/Q/R=[currentPt - noiseRange, currentPt + noiseRange] w
		if (V_sdev > (3*baselineNoise))
			// currentPt is ca. start of interaction
			break
		endif
		currentPt -= calcStep
	while (currentPt > noiseRange)
	
	if (currentPt <= noiseRange)
		fcmeta[index] = header
		print wname + ": Could not find approx. point of interaction start"
		return -1
	endif
	
	// go back a bit;
	// bl fit start doesn't need to be accurate, just should not be already in interaction regime
	Variable blFitStart = currentPt + calcStep
	header = ReplaceNumberByKey("blFitStart", header, blFitStart)
	
	CurveFit/NTHR=1/Q line w[blFitStart, blFitStart + round(ksBaselineFitLength * lastGoodPt)]
	WAVE W_coef
	
	header = ReplaceNumberByKey("blFitInterceptV", header, W_coef[0])
	header = ReplaceNumberByKey("blFitSlopeV", header, W_coef[1])
	
	// Subtr. baseline
	w -= (W_coef[0] + W_coef[1]*x)
	// remove not real data (smallest LSB)
	if ((lastGoodPt+1) < fcpoints)
		w[lastGoodPt+1,] = 0
	endif
	
	
	// Fit deflection sensitivity
	
	Variable SmoothCurvePt = fcpoints / NumberByKey("rampSize", header) * ksDeflSens_ContactLen
	// needs odd number; "round" to next odd
	SmoothCurvePt = RoundToOdd(SmoothCurvePt)
	
	Variable SmoothDerivPt = fcpoints / NumberByKey("rampSize", header) * ksDeflSens_ContactLen/2
	SmoothDerivPt = RoundToOdd(SmoothDerivPt)
	
	Duplicate/O/R=[0,lastGoodPtMargin] w, w1
	Smooth/E=3/B SmoothCurvePt, w1
	Duplicate/O/R=[0,lastGoodPtMargin] w, w2
	Differentiate w1/D=w2
	Duplicate/O/R=[0,lastGoodPtMargin] w2, w3
	Smooth/M=0 SmoothDerivPt, w3
	WaveStats/Q w3
	Variable AvgBox = round(fcpoints / NumberByKey("rampSize", header) * ksDeflSens_ContactLen/10)
	AvgBox = max(AvgBox, 1)
	EdgeStats/Q/A=(AvgBox)/P/R=[V_minRowLoc, blFitStart]/F=(ksDeflSens_EdgeFraction) w3
	
	Variable hardwallPt = round(V_EdgeLoc1)
	header = ReplaceNumberByKey("hardwallPt", header, hardwallPt)
	
	CurveFit/NTHR=1/Q line  w[3,hardwallPt]

	SetScale/I x 0, (NumberByKey("rampSize", header)/8), "nm", sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	
	// use fitted sens by default, can be modified below
	Variable deflSens = -1/W_coef[1]
	
	header = ReplaceNumberByKey("deflSensFit", header, deflSens)
	
	if (ksFixDefl == 1)
		// use saved defl sens from header.
		// if we have already set a used deflsens, use that
		
		// DO WE NEED TO INCORPORATE BASELINE SUBTRACTION TO DEFLSENS?
		// Formula (I think...): s' = 1 / ( 1/s + B )  ;  s' new deflsens, s old deflsens, B baseline slope
		
		deflSens = NumberByKey("deflSensUsed", header)
		if (numtype(deflSens) != 0)
			// use the original one from header
			deflSens = NumberByKey("deflSens", header)
		endif
	endif
	
	// Add used sens. to header data
	header = ReplaceNumberByKey("deflSensUsed", header, deflSens)

	// Change y scale on all curves to nm
	w *= deflSens
	sensfit *= deflSens
	
	// Binomially smoothed curve for contact point determination
	Duplicate/O w, smth
	Smooth/E=3 201, smth
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/fcpoints * p
	Duplicate/O xTSD, smthXTSD
	// Subtract deflection to get tip-sample-distance
	xTSD += w
	smthXTSD += smth
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000
	sensfit *= springConst * 1000
	smth *= springConst * 1000

	SetScale d 0,0,"pN", w, sensfit, smth
	
	Variable zeroRange = round(fcpoints / NumberByKey("rampSize", header) * ksDeflSens_ContactLen)
	//Variable zeroRange = 0.025 * fcpoints
	// Shift hard wall contact point to 0 in xTSD
	WaveStats/R=[3,zeroRange]/Q xTSD
	xTSD -= V_avg
	
	WaveStats/R=[3,zeroRange]/Q smthXTSD
	smthXTSD -= V_avg
	
	// write back curves to 2d wave
	fc[][index] = w[p]
	fc_sensfit[][index] = sensfit[p]
	fc_x_tsd[][index] = xTSD[p]
	fc_smth[][index] = smth[p]
	fc_smth_xtsd[][index] = smthXTSD[p]
		
	// function not finished
	//Variable height = CalcBrushHeight(w, header)
	
	// Extract contact point as point above noise.
	// Noise = StDev from first part of baseline (as found above)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] w
	header = ReplaceNumberByKey("blNoiseRaw", header, V_sdev)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] smth
	header = ReplaceNumberByKey("blNoise", header, V_sdev)
	
	// Brush height as first point above noise multiplied by a factor
	FindLevel/Q/EDGE=2/P smth, ksBrushOverNoise * V_sdev
	if (V_flag != 0)
		fcmeta[index] = header
		Print wname + ": Brush contact point not found"
		return -1
	endif
	Variable height = smthXTSD[ceil(V_LevelX)]
	
	header = ReplaceNumberByKey("brushContactPt", header, ceil(V_LevelX))
	fcmeta[index] = header
	wHeights[index] = height

	return 0
End




// Enhancement of AnalyseBrushHeight3: use Z sensor data where available and useful (if parameter set)
// returns:	 0 if fully successful;
//				-1 if analysis not successful;
Function AnalyseBrushHeight4(index, wHeights)
	Variable index
	WAVE wHeights
	
	Variable V_fitOptions = 4		// suppress CurveFit progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	NVAR fcpoints = :internalvars:FCNumPoints
	NVAR zsensloaded = :internalvars:isZsensLoaded
	
	WAVE fc
	WAVE fc_sensfit, fc_x_tsd, fc_expfit, fc_smth, fc_smth_xtsd
	Make/FREE/N=(fcpoints) w, xTSD, expfit, smth, smthXTSD
	Make/FREE/N=(fcpoints/8) sensfit
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	w[] = fc[p][index]
	
	String wname = "fc" + num2str(index)
	
	SVAR yUnits = :internalvars:yUnits
	Variable lastGoodPt = NaN
	strswitch (yUnits)
		case "LSB":
			lastGoodPt = ConvertRawToV(w, header)
			break
			
		case "pN":
			lastGoodPt = NumberByKey("lastGoodPt", header)
			ConvertForceToV(w, header)
			break
	endswitch
	
	header = ReplaceNumberByKey("lastGoodPt", header, lastGoodPt)
	
	// ignore curve end in certain operations;
	// the curve might look bad there (e.g. in Z closed loop mode, or with very fast ramping)
	Variable lastGoodPtMargin = round(0.8 * lastGoodPt)
	
	
	// Get ramp size; from Z sensor if available, otherwise from header
	Variable rampsize = 0
	if (zsensloaded && ksXDataZSens > 0)
		WAVE fc_zsens
		Make/FREE/N=(fcpoints) wzsens
		wzsens[] = fc_zsens[p][index]
		
		Wavestats/Q/M=1/R=[,lastGoodPtMargin] wzsens
		rampsize = V_max/lastGoodPtMargin*fcpoints
	else
		rampsize = NumberByKey("rampSize", header)
	endif
	header = ReplaceNumberByKey("rampSizeUsed", header, rampsize)
	
	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (rampsize), "nm", w
	
	
	
	// Fit baseline and subtract from curve
	Variable noiseRange = round(fcpoints / rampsize * ksDeflSens_ContactLen*2)
	//Variable noiseRange = round(0.1 * lastGoodPt)
	Variable calcStep = round(0.2 * noiseRange)
	Variable currentPt = lastGoodPtMargin - noiseRange
	WaveStats/Q/R=[currentPt - noiseRange, currentPt + noiseRange] w
	Variable baselineNoise = V_sdev
	
	if (calcStep < 1)
		// something went wrong
		fcmeta[index] = header
		print wname + ": Could not find approx. point of interaction start"
		return -1
	endif
	
	currentPt -= calcStep
	do
		WaveStats/Q/R=[currentPt - noiseRange, currentPt + noiseRange] w
		if (V_sdev > (3*baselineNoise))
			// currentPt is ca. start of interaction
			break
		endif
		currentPt -= calcStep
	while (currentPt > noiseRange)
	
	if (currentPt <= noiseRange)
		fcmeta[index] = header
		print wname + ": Could not find approx. point of interaction start"
		return -1
	endif
	
	// go back a bit;
	// bl fit start doesn't need to be accurate, just should not be already in interaction regime
	Variable blFitStart = currentPt + calcStep
	header = ReplaceNumberByKey("blFitStart", header, blFitStart)
	
	CurveFit/NTHR=1/Q line w[blFitStart, blFitStart + round(ksBaselineFitLength * lastGoodPt)]
	WAVE W_coef
	
	header = ReplaceNumberByKey("blFitInterceptV", header, W_coef[0])
	header = ReplaceNumberByKey("blFitSlopeV", header, W_coef[1])
	
	// Subtr. baseline
	w -= (W_coef[0] + W_coef[1]*x)
	// remove not real data (smallest LSB)
	if ((lastGoodPt+1) < fcpoints)
		w[lastGoodPt+1,] = 0
	endif
	
	
	// Fit deflection sensitivity
	
	Variable SmoothCurvePt = fcpoints / rampsize * ksDeflSens_ContactLen
	// needs odd number; "round" to next odd
	SmoothCurvePt = RoundToOdd(SmoothCurvePt)
	
	Variable SmoothDerivPt = fcpoints / rampsize * ksDeflSens_ContactLen/2
	SmoothDerivPt = RoundToOdd(SmoothDerivPt)
	
	Duplicate/O/R=[0,lastGoodPtMargin] w, w1
	Smooth/E=3/B SmoothCurvePt, w1
	Duplicate/O/R=[0,lastGoodPtMargin] w, w2
	Differentiate w1/D=w2
	Duplicate/O/R=[0,lastGoodPtMargin] w2, w3
	Smooth/M=0 SmoothDerivPt, w3
	WaveStats/Q w3
	Variable AvgBox = round(fcpoints / rampsize * ksDeflSens_ContactLen/10)
	AvgBox = max(AvgBox, 1)
	EdgeStats/Q/A=(AvgBox)/P/R=[V_minRowLoc, blFitStart]/F=(ksDeflSens_EdgeFraction) w3
	
	Variable hardwallPt = round(V_EdgeLoc1)
	header = ReplaceNumberByKey("hardwallPt", header, hardwallPt)
	
	if (zsensloaded && ksXDataZSens > 0)
		CurveFit/NTHR=1/Q line  w[3,hardwallPt]/X=wzsens
	else
		CurveFit/NTHR=1/Q line  w[3,hardwallPt]
	endif

	SetScale/I x 0, (rampsize/8), "nm", sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	
	// use fitted sens by default, can be modified below
	Variable deflSens = -1/W_coef[1]
	
	header = ReplaceNumberByKey("deflSensFit", header, deflSens)
	
	if (ksFixDefl == 1)
		// use saved defl sens from header.
		// if we have already set a used deflsens, use that
		
		// DO WE NEED TO INCORPORATE BASELINE SUBTRACTION TO DEFLSENS?
		// Formula (I think...): s' = 1 / ( 1/s + B )  ;  s' new deflsens, s old deflsens, B baseline slope
		
		deflSens = NumberByKey("deflSensUsed", header)
		if (numtype(deflSens) != 0)
			// use the original one from header
			deflSens = NumberByKey("deflSens", header)
		endif
	endif
	
	// Add used sens. to header data
	header = ReplaceNumberByKey("deflSensUsed", header, deflSens)

	// Change y scale on all curves to nm
	w *= deflSens
	sensfit *= deflSens
	
	// Binomially smoothed curve for contact point determination
	Duplicate/O w, smth
	Smooth/E=3 SmoothCurvePt, smth
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	if (zsensloaded && ksXDataZSens > 0)
		xTSD[] = wzsens[p]
	else
		xTSD = rampsize/fcpoints * p
	endif
	
	Duplicate/O xTSD, smthXTSD
	// Subtract deflection to get tip-sample-distance
	xTSD += w
	smthXTSD += smth
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000
	sensfit *= springConst * 1000
	smth *= springConst * 1000

	SetScale d 0,0,"pN", w, sensfit, smth
	
	Variable zeroRange = round(fcpoints / rampsize * ksDeflSens_ContactLen/2)
	//Variable zeroRange = 0.025 * fcpoints
	// Shift hard wall contact point to 0 in xTSD
	WaveStats/R=[3,zeroRange]/Q xTSD
	xTSD -= V_avg
	header = ReplaceNumberByKey("horizShifted", header, V_avg)
	
	WaveStats/R=[3,zeroRange]/Q smthXTSD
	smthXTSD -= V_avg
	
	// write back curves to 2d wave
	fc[][index] = w[p]
	fc_sensfit[][index] = sensfit[p]
	fc_x_tsd[][index] = xTSD[p]
	fc_smth[][index] = smth[p]
	fc_smth_xtsd[][index] = smthXTSD[p]
		
	// function not finished
	//Variable height = CalcBrushHeight(w, header)
	
	// Extract contact point as point above noise.
	// Noise = StDev from first part of baseline (as found above)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] w
	header = ReplaceNumberByKey("blNoiseRaw", header, V_sdev)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] smth
	header = ReplaceNumberByKey("blNoise", header, V_sdev)
	
	// Brush height as first point above noise multiplied by a factor
	FindLevel/Q/EDGE=2/P smth, ksBrushOverNoise * V_sdev
	if (V_flag != 0)
		fcmeta[index] = header
		Print wname + ": Brush contact point not found"
		return -1
	endif
	Variable height = smthXTSD[ceil(V_LevelX)]
	
	header = ReplaceNumberByKey("brushContactPt", header, ceil(V_LevelX))
	fcmeta[index] = header
	wHeights[index] = height

	return 0
End


// Function not done, not yet in use
Function CalcBrushHeight(w, wsmth, wsmth_xtsd, header)
	WAVE w, wsmth, wsmth_xtsd
	String &header		// pass by ref
	
	Variable blFitStart = NumberByKey("blFitStart", header)
	Variable lastGoodPt = NumberByKey("lastGoodPt", header)
	
	// Extract contact point as point above noise.
	// Noise = StDev from first part of baseline (as found above)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] w
	header = ReplaceNumberByKey("blNoiseRaw", header, V_sdev)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] wsmth
	header = ReplaceNumberByKey("blNoise", header, V_sdev)
	
	// Brush height as first point above noise multiplied by a factor
	FindLevel/Q/EDGE=2/P wsmth, ksBrushOverNoise * V_sdev
	if (V_flag != 0)
		return NaN
	endif
	Variable height = wsmth_xtsd[ceil(V_LevelX)]
	
	header = ReplaceNumberByKey("brushContactPt", header, ceil(V_LevelX))
End


// Transform retract curve to tip-sample distance
Function RetractTSD3(index)
	Variable index
	
	NVAR fcpoints = :internalvars:FCNumPoints
	NVAR zsensloaded = :internalvars:isZsensLoaded
	
	WAVE rfc, rfc_x_tsd
	Make/FREE/N=(fcpoints) w, xTSD
	
	WAVE/T fcmeta
	String header = fcmeta[index]
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	w[] = rfc[p][index]

	// Get ramp size; from Z sensor if available, otherwise from header
	Variable rampsize = 0
	if (zsensloaded && ksXDataZSens > 0)
		WAVE rfc_zsens
		Make/FREE/N=(fcpoints) wzsens
		wzsens[] = rfc_zsens[p][index]
		Variable lastGoodPtMargin = 0.8* NumberByKey("lastGoodPt", header)
		
		Wavestats/Q/M=1/R=[,lastGoodPtMargin] wzsens
		rampsize = V_max/lastGoodPtMargin*fcpoints
	else
		rampsize = NumberByKey("rampSize", header)
	endif
	header = ReplaceNumberByKey("rampSizeUsedRetr", header, rampsize)
	

	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (rampsize), "nm", w
	
	SVAR yUnits = :internalvars:yUnits
	strswitch (yUnits)
		case "LSB":
			ConvertRawToV(w, header)
			break
			
		case "pN":
			ConvertForceToV(w, header)
			break
	endswitch
	
	// Subtract baseline as determined in approach curve
	w -= NumberByKey("blFitInterceptV", header) +  NumberByKey("blFitSlopeV", header) * x
	
	// Convert y axis to nm
	w *= NumberByKey("deflSensUsed", header)
	
	
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	if (zsensloaded && ksXDataZSens > 0)
		xTSD[] = wzsens[p]
	else
		xTSD = rampsize/fcpoints * p
	endif
	
	xTSD += w
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000

	SetScale d 0,0,"pN", w
	
	//Variable zeroRange = round(fcpoints / rampsize * ksDeflSens_ContactLen/2)
	// Shift hard wall contact point to 0 in xTSD
	//WaveStats/M=1/Q xTSD
	//xTSD -= V_min
	Variable shift = NumberByKey("horizShifted", header)		// use same shift as in approach curve
	xTSD -= shift
	
	
//	
//	
//	// Create x values wave for tip-sample-distance
//	// Write displacement x values
//	xTSD = NumberByKey("rampSize", header)/fcpoints * p
//	// Subtract deflection to get tip-sample-distance
//	xTSD += w
//	
//	// Change y scale on all curves to pN
//	Variable springConst = NumberByKey("springConst", header)
//	w *= springConst * 1000
//	
//	SetScale d 0,0,"pN", w
//	
//	WaveStats/Q xTSD
//	xTSD -= V_min
	
	// write back curves to 2d wave
	rfc[][index] = w[p]
	rfc_x_tsd[][index] = xTSD[p]
	
	return 0	
End


// Baseline fitting of friction data (horizontal deflection)
// Fit (linear) last part of approach friction curve (up to last good point)
// and correct both approach and retract curves with this fit.
Function FricBaseline(index)
	Variable index
	
	Variable V_fitOptions = 4		// suppress CurveFit progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	WAVE fc_fric, rfc_fric
	Make/FREE/N=(fcpoints) wapp, wret
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	wapp[] = fc_fric[p][index]
	wret[] = rfc_fric[p][index]

	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", wapp
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", wret
	
	// Sometimes last points of curve are at smallest LSB value
	// Set those to 0 (after baseline substraction)
	Variable lastGoodPt = numpnts(wapp) - 1
	FindLevel/Q/P wapp, (-1*2^15 + 1)
	if (V_flag == 0)
		lastGoodPt = floor(V_LevelX) - 1
	endif
	FindLevel/Q/P wret, (-1*2^15 + 1)
	if (V_flag == 0)
		lastGoodPt = min(floor(V_LevelX) - 1, lastGoodPt)
	endif
	
	// User defined forcing of last good pt
	if (ksMaxGoodPt >= 0)
		lastGoodPt = min(lastGoodPt, ksMaxGoodPt)
	endif
	
	header = ReplaceNumberByKey("fricLastGoodPt", header, lastGoodPt)
	
	
	// ignore curve end in certain operations;
	// the curve might look bad there (e.g. in Z closed loop mode, or with very fast ramping)
	Variable lastGoodPtMargin = round(0.8 * lastGoodPt)
	
	// Convert y axis to V
	wapp *= NumberByKey("FricVPerLSB", header)
	wret *= NumberByKey("FricVPerLSB", header)
	
	CurveFit/NTHR=1/Q line wapp[lastGoodPtMargin*(1-ksBaselineFitLength), lastGoodPtMargin]
	WAVE W_coef
	
	header = ReplaceNumberByKey("fricBlFitInterceptV", header, W_coef[0])
	header = ReplaceNumberByKey("fricBlFitSlopeV", header, W_coef[1])
	
	// Subtr. baseline
	wapp -= (W_coef[0] + W_coef[1]*x)
	wret -= (W_coef[0] + W_coef[1]*x)
	// remove not real data (smallest LSB)
	if ((lastGoodPt+1) < fcpoints)
		wapp[lastGoodPt+1,] = 0
		wret[lastGoodPt+1,] = 0
	endif
	
	// write back curves to 2d wave
	fc_fric[][index] = wapp[p]
	rfc_fric[][index] = wret[p]
	
	fcmeta[index] = header
	
	return 0
	
End


Function RecalcDeflSens(dsens, idx)
	Variable dsens		// defl. sens. in nm/V
	Variable idx			// index of curve to set
	
	WAVE/T fcmeta
	
	NVAR/Z analysisdone = :internalvars:analysisDone
	
	if (!NVAR_Exists(analysisdone) || analysisdone < 1)
		// Analysis not run yet. Just update header entry for analysis
		fcmeta[idx] = ReplaceNumberByKey("deflSensUsed", fcmeta[idx], dsens)
		return 0
	endif

	WAVE fc, rfc, fc_x_tsd, rfc_x_tsd
	
	Duplicate/FREE/O/R=[][idx] fc, w
	Duplicate/FREE/O/R=[][idx] rfc, rw
	Duplicate/FREE/O/R=[][idx] fc_x_tsd, wtsd
	Duplicate/FREE/O/R=[][idx] rfc_x_tsd, rwtsd
	
	
	Variable springconst = NumberByKey("springConst", fcmeta[idx])
	Variable olddsens = NumberByKey("deflSensUsed", fcmeta[idx])
	NVAR fcpoints = :internalvars:FCNumPoints
	NVAR zsensloaded = :internalvars:isZsensLoaded
	
	// convert from pN to V
	w /= springconst * 1000 * olddsens
	rw /= springconst * 1000 * olddsens
	
	// V -> nm
	w *= dsens
	rw *= dsens
	
	Variable rampsize = NumberByKey("rampSizeUsed", fcmeta[idx])
	Variable rampsizeretr = NumberByKey("rampSizeUsedRetr", fcmeta[idx])
	
	// Create x values wave for tip-sample-distance
	if (zsensloaded && ksXDataZSens > 0)
		WAVE fc_zsens, rfc_zsens
		wtsd = fc_zsens[p][idx]
		rwtsd = rfc_zsens[p][idx]
	else
		wtsd = rampsize/fcpoints * p
		rwtsd = rampsizeretr/fcpoints * p
	endif
	
	// Subtract deflection to get tip-sample-distance
	wtsd += w
	rwtsd += rw
	
	w *= springconst * 1000
	rw *= springconst * 1000
	
	// Shift hard wall contact point to 0 in TSD
	Variable zeroRange = round(fcpoints / rampsize * ksDeflSens_ContactLen/2)
	WaveStats/M=1/R=[3,zeroRange]/Q wtsd
	wtsd -= V_avg
	WaveStats/Q/M=1 rwtsd
	rwtsd -= V_min
	
	// write back to 2D waves
	fc[][idx] = w[p]
	rfc[][idx] = rw[p]
	fc_x_tsd[][idx] = wtsd[p]
	rfc_x_tsd[][idx] = rwtsd[p]
	
	// Update metadata
	fcmeta[idx] = ReplaceNumberByKey("deflSensUsed", fcmeta[idx], dsens)
	
End


Function RecalcDeflSensAll(dsens)
	Variable dsens		// defl. sens. in nm/V
	
	NVAR numcurves = :internalvars:numCurves
	
	Variable i
	for (i=0; i<numcurves; i+=1)
		RecalcDeflSens(dsens, i)
		Prog("DeflSens", i, numcurves)
	endfor
End


Function CalcRelStiffness(lower, upper)
	Variable lower, upper	// lower and upper force limits (pN) for
								// linear relative stiffness calculation
	
	WAVE fc, fc_z
	WAVE/T fcmeta
	Variable upperz = 0
	Variable lowerz = 0
	Variable numcurves = numpnts(fc_z)
	Make/O/N=(numcurves) relstiffness = 0, relstiffness_loz = 0, relstiffness_hiz = 0
	
	NVAR fcpoints = :internalvars:FCNumPoints
	Variable rampsize = 0
	Variable AvgBox = 1
	
	Variable i = 0
	for (i=0; i<numcurves; i+=1)
		rampsize = NumberByKey("rampsizeUsed", fcmeta[i])
		AvgBox = round(fcpoints / rampsize * ksDeflSens_ContactLen/10)
		AvgBox = max(AvgBox, 1)
		Duplicate/FREE/O/R=[][i] fc, w
		FindLevel/B=(AvgBox)/EDGE=2/Q w, upper
		upperz = V_LevelX
		FindLevel/B=(AvgBox)/EDGE=2/Q w, lower
		lowerz = V_LevelX
		relstiffness_loz[i] = lowerz
		relstiffness_hiz[i] = upperz
		relstiffness[i] = (upper-lower)/(lowerz-upperz)
		
		fcmeta[i] = ReplaceNumberByKey("RelStiffLoF", fcmeta[i], lower)
		fcmeta[i] = ReplaceNumberByKey("RelStiffHiF", fcmeta[i], upper)
	endfor
End


// Calculates linear stiffness of force vs tip-sample-distance between two defined forces
// (just slope, no fitting)
Function CalcLinStiffness(lower, upper)
	Variable lower, upper	// lower and upper force limits (pN) for
								// linear stiffness calculation
	
	WAVE fc, fc_x_tsd, fc_z
	WAVE/T fcmeta
	Variable upperz = 0
	Variable lowerz = 0
	Variable numcurves = numpnts(fc_z)
	Make/O/N=(numcurves) linstiffness = 0, linstiffness_loz = 0, linstiffness_hiz = 0
	
	NVAR fcpoints = :internalvars:FCNumPoints
	Variable rampsize = 0
	Variable AvgBox = 1
	
	Variable i = 0
	for (i=0; i<numcurves; i+=1)
		rampsize = NumberByKey("rampsizeUsed", fcmeta[i])
		AvgBox = round(fcpoints / rampsize * ksDeflSens_ContactLen/10)
		AvgBox = max(AvgBox, 1)
		Duplicate/FREE/O/R=[][i] fc, w
		FindLevel/B=(AvgBox)/EDGE=2/P/Q w, upper
		upperz = fc_x_tsd[V_LevelX][i]
		FindLevel/B=(AvgBox)/EDGE=2/P/Q w, lower
		lowerz = fc_x_tsd[V_LevelX][i]
		linstiffness_loz[i] = lowerz
		linstiffness_hiz[i] = upperz
		linstiffness[i] = (upper-lower)/(lowerz-upperz)
		
		fcmeta[i] = ReplaceNumberByKey("LinStiffLoF", fcmeta[i], lower)
		fcmeta[i] = ReplaceNumberByKey("LinStiffHiF", fcmeta[i], upper)
	endfor
End


// Calculate relative stiffness for approach friction signal (in V/nm)
// same way as for vertical signal.
// Take force range between the located Z values for vertical signal.
Function CalcRelStiffness_Fric()
	WAVE fc_fric
	WAVE relstiffness_loz, relstiffness_hiz
	Variable lowerz = 0
	Variable upperz = 0
	Variable numcurves = numpnts(relstiffness_loz)
	Make/O/N=(numcurves) relstiffness_fric = 0
	Variable i = 0
	for (i=0; i<numcurves; i+=1)
		lowerz = relstiffness_loz[i]
		upperz = relstiffness_hiz[i]
		if (numtype(lowerz) == 0 && numtype(upperz) == 0)
			Duplicate/FREE/O/R=[][i] fc_fric, w
			Redimension/N=(DimSize(w, 0)) w
			relstiffness_fric[i] = (w(upperz) - w(lowerz)) / (lowerz - upperz)
		else
			relstiffness_fric[i] = NaN
		endif
	endfor
End



// Calculates E-modulus of each curve, based on Hertz contact model
// Splits the curve at <fraction> between the hardwall point and brush contact point,
// and fits individual Hertz model to each region.
Function CalcHertzEMod(fraction)
	Variable fraction		// number between 0 and 1; looking from the hardwall point
								// (0.3 seems to work well)
	
	// ** Hardcoded intial guess coefficients, and constants (poisson number, tip radius)
	Variable nu = 0.3
	Variable R = 40e-9
//	Make/N=5/D/FREE coefs1 = {nu, 0.5e6, R, 20, 0}
//	Make/N=5/D/FREE coefs2 = {nu, 1e6, R, 10, 0}
	Make/N=8/D/FREE coefs = {nu, .2e6, R, 20, 0, 1.5e6, 7, 100}
	Make/T/O/FREE constr = {"K3"}
	
	
	WAVE fc, fc_x_tsd, fc_z
	WAVE/T fcmeta
	Variable numcurves = numpnts(fc_z)
	Make/O/N=(numcurves) emod1=NaN, emod2=NaN, emodh0=NaN, emodsplit=NaN
	
	NVAR fcpoints = :internalvars:FCNumPoints
//	Make/N=(fcpoints/8, numcurves)/O fc_emod1fit = NaN
//	Make/N=(fcpoints/8, numcurves)/O fc_emod2fit = NaN
	Make/N=(fcpoints/4, numcurves)/O fc_emodfit = NaN
	
	
	Variable bcontactpt = 0, bcontactx = 0
	Variable hwpt = 0, hwx = 0
	Variable splitpt = 0, splitx = 0
	
	Variable i = 0
	for (i=0; i<numcurves; i+=1)
		Prog("EMod", i, numcurves)
		
		Duplicate/FREE/O/R=[][i] fc, w
		Duplicate/FREE/O/R=[][i] fc_x_tsd, tsd
		Redimension/N=(numpnts(w)) w
		Redimension/N=(numpnts(tsd)) tsd
//		Duplicate/FREE w, fit1
//		Duplicate/FREE w, fit2
//		fit1 = NaN
//		fit2 = NaN
		Duplicate/FREE w, wfit
		wfit = NaN
		
		bcontactpt = NumberByKey("BrushContactPt", fcmeta[i])
		hwpt = NumberByKey("HardwallPt", fcmeta[i])
		if (numtype(hwpt) != 0 || numtype(bcontactpt) != 0)
			print "[ERROR] Didn't find fitting limits at curve " + num2str(i)
			continue
		endif
		bcontactx = tsd[bcontactpt]
		hwx = tsd[hwpt]
		
		// find split point
		splitx = hwx + (bcontactx - hwx) * fraction
		FindLevel/Q/P/R=[hwpt] tsd, splitx
		splitpt = round(V_levelX)
		
		if (V_flag != 0)
			print "[ERROR] Split point not found at curve " + num2str(i)
			continue
		endif
		
		Variable V_fitOptions = 4		// suppress fitting progress window
		
//		// fit region 1 (splitpoint to brush contact)
//		coefs1[3] = bcontactx		// update initial guess for h_0
//		Variable V_FitError = 0		// prevent abort on error
//		FuncFit/Q/N/H="10101"/NTHR=1 hertz, coefs1, w[splitpt,bcontactpt] /X=tsd /D=fit1
//		
//		if (V_FitError != 0)
//			print "[ERROR] Couldn't fit region 1 at curve " + num2str(i)
//			fit1 = NaN
//		else
//			emod1[i] = coefs1[1]
//			//fit1[] = hertz(coefs1, tsd[p])
//		endif
//		
//		
//		// fit region 2 (hardwall to splitpoint)
//		coefs2[3] = (splitx + bcontactx)/2		// update initial guess for h_0
//		V_FitError = 0		// prevent abort on error
//		FuncFit/Q/N/H="10101"/NTHR=1 hertz, coefs2, w[hwpt, splitpt] /X=tsd /D=fit2
//		
//		if (V_FitError != 0)
//			print "[ERROR] Couldn't fit region 2 at curve " + num2str(i)
//			fit2 = NaN
//		else
//			emod2[i] = coefs2[1]
//			//fit2[] = hertz(coefs2, tsd[p])
//		endif

		// fit both regions together
		// update some initial coefs
		coefs[3] = bcontactx
		coefs[6] = splitx
		coefs[7] = w[splitpt]
		constr[0] = "K3 >= " + num2str(bcontactx)
		Variable V_FitError = 0		// prevent abort on error
		FuncFit/Q/N/H="10101000"/NTHR=1 twohertz, coefs, w[hwpt, bcontactpt] /X=tsd/D=wfit/C=constr
		if (V_FitError != 0)
			print "[ERROR] Couldn't do fit at curve " + num2str(i)
			wfit = NaN
		else
			emod1[i] = coefs[1]
			emod2[i] = coefs[5]
			emodh0[i] = coefs[3]
			emodsplit[i] = coefs[6]
		endif
		
//		Redimension/N=(fcpoints/8) fit1
//		Redimension/N=(fcpoints/8) fit2
//		fc_emod1fit[][i] = fit1[p]
//		fc_emod2fit[][i] = fit2[p]
//		fcmeta[i] = ReplaceNumberByKey("EModSplitFraction", fcmeta[i], fraction)

		Redimension/N=(fcpoints/4) wfit
		fc_emodfit[][i] = wfit[p]
	endfor
End


Function retractedforcecurvebaselinefit(index, rampSize, VPerLSB, springConst)
	Variable index, rampSize, VPerLSB, springConst
	
	NVAR numcurves = :internalvars:numCurves

	Variable/G V_fitoptions=4 //no fit window

	String wnametemp = "fc" + num2str(index)		
	WAVE w = $wnametemp
	String header = note(w)

	String wname= "rfc" + num2str(index)
	WAVE rw=$wname

	
	make/N=(numcurves)/O timer1
	Variable tic1
	make/N=(numcurves)/O timer2
	Variable tic2
	make/N=(numcurves)/O timer3
	Variable tic3
	make/N=(numcurves)/O timer4
	Variable tic4
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, rampSize, "nm", rw
	
	tic1=ticks
	// Convert y axis to V
	rw *= VPerLSB
	
	timer1[index]=(ticks-tic1)/60
	
	tic2=ticks
	
	// Fit baseline and subtract from curve
	CurveFit/NTHR=1/Q line  rw[2600,3600]
	WAVE W_coef
	Make/N=(fcpoints) $(wname + "_blfit")
	WAVE blfit = $(wname + "_blfit")
	SetScale/I x 0, rampSize, "nm", blfit
	// Save baseline to fc<i>_blfit
	blfit = W_coef[0] + W_coef[1]*x
	// Subtr. baseline
	rw -= (W_coef[0] + W_coef[1]*x)
	
	// Sometimes last points of curve are at smallest LSB value
	// Set those to 0 (i.e. if value < -3 V)
	rw[3600,] = (rw[p] > -3) * rw[p]
	
	timer2[index]=(ticks-tic2)/60

	tic3=ticks
	// Fit deflection sensitivity and change y scale
	CurveFit/NTHR=1/Q line  rw[10,100]
	Make/N=(fcpoints/8) $(wname + "_sensfit")	// display only 4096/8 points
	WAVE sensfit = $(wname + "_sensfit")
	SetScale/I x 0, (rampSize/8), "nm", sensfit
	// Save fit to fc<i>_sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	Variable deflSens = -1/W_coef[1]
	// Add fitted sens. to header data
	header += "deflSensUsed:" + num2str(deflSens) + ";"
	//Note/K w, header
	// Change y scale on all curves to nm
	rw *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	timer3[index]=(ticks-tic3)/60
	
	tic4=ticks
	
	// Create x values wave for tip-sample-distance
	Make/N=(fcpoints) $(wname + "_x_tsd")
	WAVE xTSD = $(wname + "_x_tsd")
	
	timer4[index]=(ticks-tic4)/60
	
	// Write displacement x values
	xTSD = rampSize/fcpoints * p
	// Subtract deflection to get tip-sample-distance
	xTSD += rw
	
	

	
	// Change y scale on all curves to pN
	Variable sc = springConst
	rw *= sc * 1000
	blfit *= sc * 1000
	sensfit *= sc * 1000
	SetScale d 0,0,"pN", rw, blfit, sensfit
	
	// Shift hard wall contact point to 0 in xTSD
	WaveStats/R=[10,100]/Q xTSD
	xTSD -= V_avg
	

	//retractcurve feature detection 
	
	Variable detectsetpnt=-30	//Set your lower limit of noise (nm). Values smaller than this value are interpreted as a retract feature.
	Variable maxpnt=numpnts(rw)-1,minpnt
	
 
	
	wavestats/Q/R=[0,maxpnt] rw
	
	minpnt = x2pnt(rw,V_minloc)
	
	

	if(V_min<detectsetpnt)
	
		
		//print detectsetpnt, V_min, rw[minpnt], rw[minpnt-1], rw[minpnt+1]

		
		if(rw[minpnt-1]<detectsetpnt && rw[minpnt+1]<detectsetpnt)
			
			return 1
		
		else
		
			do
		
				wavestats/Q/R=[0,minpnt-1] rw
				
				//print "do",minpnt, V_min, V_minloc
		
				minpnt = x2pnt(rw,V_minloc)
			
				if(rw[minpnt-1]<detectsetpnt && rw[minpnt+1]<detectsetpnt)
	
					return 1
			
				endif
		
			while(V_minloc>5)	//when no feature below x=5nm then exit with -1
			
			return -1
	
		endif
	
	
	
	endif
	
	return -1
	
End


// returns "rounded" odd integer
// e.g. 5.9 returns 5; 6.0 returns 7
Function RoundToOdd(a)
	Variable a
	
	a = floor(a)
	a = mod(a, 2) ? a : a+1
	
	return a
End