#pragma rtGlobals=3		// Use modern global access method.


Function Analysis()

	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
		
	NVAR/Z analysisDone = :internalvars:analysisDone
	if (NVAR_Exists(analysisDone) && analysisDone == 1)
		String alert = ""
		alert = "Analysis has been run already on this data.\r"
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
	WAVE fc
	String header
	Variable num = 0
	
	// Save analysis parameters, or compare if already saved
	SVAR/Z params = :internalvars:analysisparameters
	NVAR rowsize = :internalvars:FVRowSize
	Variable conflict = 0
	if (SVAR_Exists(params))
		if (ksFCPoints != NumberByKey("ksFCPoints", params))
			conflict = 1
		elseif (rowsize != NumberByKey("FVRowSize", params))
			conflict = 1
		elseif (ksBaselineFitLength != NumberByKey("ksBaselineFitLength", params))
			conflict = 1
		elseif (ksBrushCutoff != NumberByKey("ksBrushCutoff", params))
			conflict = 1
		elseif (ksBrushOverNoise != NumberByKey("ksBrushOverNoise", params))
			conflict = 1
		elseif (ksHardwallFitFraction != NumberByKey("ksHardwallFitFraction", params))
			conflict = 1
		endif
	else
		String/G :internalvars:analysisparameters = ""
		SVAR params = :internalvars:analysisparameters
	endif
	
	if (conflict)
		alert = "Some analysis parameters do not match previously used ones for this data set.\r"
		alert += "Continuing can lead to inconsistent results. Old parameters will be lost. Continue anyway?"
		DoAlert 1, alert
		
		if (V_flag != 1)
			print "Analysis canceled by user"
			return -1
		endif
	endif
	
	params = ReplaceNumberByKey("ksFCPoints", params, ksFCPoints)
	params = ReplaceNumberByKey("FVRowSize", params, rowsize)
	params = ReplaceNumberByKey("ksBaselineFitLength", params, ksBaselineFitLength)
	params = ReplaceNumberByKey("ksBrushCutoff", params, ksBrushCutoff)
	params = ReplaceNumberByKey("ksBrushOverNoise", params, ksBrushOverNoise)
	params = ReplaceNumberByKey("ksHardwallFitFraction", params, ksHardwallFitFraction)
	
	// Create 2d waves for Analysis
	Make/N=(ksFCPoints, numcurves)/O fc_blfit = NaN
	Make/N=(ksFCPoints/8, numcurves)/O fc_sensfit = NaN
	Make/N=(ksFCPoints, numcurves)/O fc_x_tsd = NaN
	Make/N=(ksFCPoints, numcurves)/O fc_expfit = NaN
	Make/N=(ksFCPoints, numcurves)/O fc_smth = NaN
	Make/N=(ksFCPoints, numcurves)/O fc_smth_xtsd = NaN
	
	Make/N=(ksFCPoints, numcurves)/O rfc_x_tsd = NaN
	
	
	// brushheights: 1D wave to hold analysed brush heights and NaN if not analysed
	// heightsmap: 2D (redimension later) with -100 instead of NaN
	// deflsensfitted: 1D wave to hold fitted deflection sensitivities
	// blnoise: 1D wave to hold calculated baseline noise
	WAVE brushheights
	Make/N=(numcurves)/O heightsmap = NaN
	Make/N=(numcurves)/O deflsensfitted = NaN
	Make/N=(numcurves)/O blnoise = NaN
	
	// Running analysis changes the "raw" data (rescales it inplace)
	// Set flag immediately before analysis starts to warn the user if he re-runs the analysis
	Variable/G :internalvars:analysisDone = 1
	
	NVAR loadfric = :internalvars:loadFriction
	
	for (i=0; i < numcurves; i+=1)
	
		if(sel[i])
		
			header = fcmeta[i]
		
			Variable rampSize = NumberByKey("rampSize", header)
			
			// Set Z piezo ramp size (x axis)
			SetScale/I x 0, (rampSize), "nm", fc
			SetScale/I x 0, (rampSize), "nm", fc_blfit
			SetScale/I x 0, (rampSize/8), "nm", fc_sensfit
			SetScale/I x 0, (rampSize), "nm", fc_expfit
			
			if (loadfric)
				WAVE fc_fric, rfc_fric
				fc_fric[][i] *= NumberByKey("FricVPerLSB", fcmeta[i])
				rfc_fric[][i] *= NumberByKey("FricVPerLSB", fcmeta[i])
				SetScale/I x, 0, (rampSize), "nm", fc_fric
				SetScale/I x, 0, (rampSize), "nm", rfc_fric
			endif
		
			result = AnalyseBrushHeight3(i, brushheights)
			if(result < 0)
				//could not determine brush height
				heightsmap[i] = -100
			else
				heightsmap[i] = brushheights[i]
			endif
			
			// Re-read metadata; has been changed/expanded by analysis code above
			header = fcmeta[i]
			deflsensfitted[i] = NumberByKey("deflSensFit", header)
			blnoise[i] = NumberByKey("blNoiseRaw", header)
			
			// Process retract curve
			RetractTSD(i)
			
			// Disabled until retractfeature fixed for 2D FC arrays
			// retractfeature[i]=retractedforcecurvebaselinefit(i, rampSize, VPerLSB, springConst)	//baselinefit for the retracted curves.
		
			num += 1
		endif
		
		Prog("Analysis",i,numcurves)
		
	endfor

	printf "Elapsed time: %g seconds\r", round(10*(ticks-t0)/60)/10
	
	print TidyDFName(GetDataFolder(1))
	print "brushheights:"
	WaveStats brushheights
	
	
	String/G :internalvars:resultwave = "heightsmap"
	
	ShowResultMap()
	
	SVAR resultgraph = :internalvars:resultgraph
	SVAR imagegraph = :internalvars:imagegraph
		
	SetWindow $resultgraph,hook(resultinspect)=inspector
	SetWindow $imagegraph,hook(imageinspect)=inspector

	return 0

		Redimension/N=(rowsize,rowsize) heightsmap
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
	
	WAVE fc
	WAVE fc_blfit, fc_sensfit, fc_x_tsd, fc_expfit
	Make/FREE/N=(ksFCPoints) w, blfit, xTSD, expfit
	Make/FREE/N=(ksFCPoints/8) sensfit
	
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
	header += "deflSensFit:" + num2str(deflSens) + ";"
	fcmeta[index] = header
	// Change y scale on all curves to nm
	w *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/ksFCPoints * p
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
	
	WAVE fc
	WAVE fc_blfit, fc_sensfit, fc_x_tsd, fc_expfit
	Make/FREE/N=(ksFCPoints) w, blfit, xTSD, expfit
	Make/FREE/N=(ksFCPoints/8) sensfit
	
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
	if ((lastGoodPt+1) < ksFCPoints)
		w[lastGoodPt+1,] = 0
	endif
	
	// Fit deflection sensitivity and change y scale
	Make/FREE/N=(ksFCPoints) w1, w2, w3
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
	header += "deflSensFit:" + num2str(deflSens) + ";"
	fcmeta[index] = header

	// Change y scale on all curves to nm
	w *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/ksFCPoints * p
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


// Test of different brush height algorithm
// Changes from original AnalyseBrushHeight2:
// * Brush height from filtered curve directly instead of expfit
Function AnalyseBrushHeight3(index, wHeights)
	Variable index
	WAVE wHeights
	
	Variable V_fitOptions = 4		// suppress CurveFit progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	WAVE fc
	WAVE fc_blfit, fc_sensfit, fc_x_tsd, fc_expfit, fc_smth, fc_smth_xtsd
	Make/FREE/N=(ksFCPoints) w, blfit, xTSD, expfit, smth, smthXTSD
	Make/FREE/N=(ksFCPoints/8) sensfit
	
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
	
	// Fit baseline and subtract from curve
	Variable noiseRange = round(0.1 * lastGoodPt)
	Variable calcStep = round(0.2 * noiseRange)
	Variable currentPt = lastGoodPt - noiseRange
	WaveStats/Q/R=[currentPt - noiseRange, currentPt + noiseRange] w
	Variable baselineNoise = V_sdev
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
	
	Variable blFitStart = currentPt
	header += "blFitStart:" + num2str(blFitStart) + ";"
	
	CurveFit/NTHR=1/Q line w[blFitStart, blFitStart + round(ksBaselineFitLength * lastGoodPt)]
	WAVE W_coef
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", blfit

	blfit = W_coef[0] + W_coef[1]*x
	// Subtr. baseline
	w -= (W_coef[0] + W_coef[1]*x)
	// remove not real data (smallest LSB)
	if ((lastGoodPt+1) < ksFCPoints)
		w[lastGoodPt+1,] = 0
	endif
	
	// Fit deflection sensitivity and change y scale
	Make/FREE/N=(ksFCPoints) w1, w2, w3
	Duplicate/O w, w1
	Smooth/E=3/B 501, w1
	Differentiate w1/D=w2
	Duplicate/O w2, w3
	Smooth/M=0 501, w3
	WaveStats/Q w3
	EdgeStats/Q/A=30/P/R=[V_minRowLoc, blFitStart]/F=(ksHardwallFitFraction) w3
	
	Variable hardwallPt = round(V_EdgeLoc1)
	header += "hardwallPt:" + num2str(hardwallPt) + ";"
	
	CurveFit/NTHR=1/Q line  w[10,hardwallPt]

	SetScale/I x 0, (NumberByKey("rampSize", header)/8), "nm", sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	Variable deflSens = -1/W_coef[1]
	// Add fitted sens. to header data
	header += "deflSensFit:" + num2str(deflSens) + ";"

	// Change y scale on all curves to nm
	w *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	// Binomially smoothed curve for contact point determination
	Duplicate/O w, smth
	Smooth/E=3 201, smth
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/ksFCPoints * p
	Duplicate/O xTSD, smthXTSD
	// Subtract deflection to get tip-sample-distance
	xTSD += w
	smthXTSD += smth
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000
	blfit *= springConst * 1000
	sensfit *= springConst * 1000
	smth *= springConst * 1000
	SetScale d 0,0,"pN", w, blfit, sensfit, smth
	
	// Shift hard wall contact point to 0 in xTSD
	WaveStats/R=[10,hardwallPt]/Q xTSD
	xTSD -= V_avg
	
	WaveStats/R=[10,hardwallPt]/Q smthXTSD
	smthXTSD -= V_avg
	
	// write back curves to 2d wave
	fc[][index] = w[p]
	fc_blfit[][index] = blfit[p]
	fc_sensfit[][index] = sensfit[p]
	fc_x_tsd[][index] = xTSD[p]
	fc_smth[][index] = smth[p]
	fc_smth_xtsd[][index] = smthXTSD[p]
		
	
	// Extract contact point as point above noise.
	// Noise = StDev from first part of baseline (as found above)
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] w
	header += "blNoiseRaw:" + num2str(V_sdev) + ";"
	WaveStats/Q/R=[blFitStart, blFitStart + round(lastGoodPt*ksBaselineFitLength)] smth
	header += "blNoise:" + num2str(V_sdev) + ";"
	
	// Brush height as first point above noise multiplied by a factor
	FindLevel/Q/EDGE=2/P smth, ksBrushOverNoise * V_sdev
	if (V_flag != 0)
		fcmeta[index] = header
		Print wname + ": Brush contact point not found"
		return -1
	endif
	Variable height = smthXTSD[ceil(V_LevelX)]
	
	header += "brushContactPt:" + num2str(ceil(V_LevelX)) + ";"
	fcmeta[index] = header
	wHeights[index] = height

	return 0
End

// Transform retract curve to tip-sample distance
Function RetractTSD(index)
	Variable index
	
	WAVE rfc, rfc_x_tsd
	Make/FREE/N=(ksFCPoints) w, xTSD
	
	WAVE/T fcmeta
	String header = fcmeta[index]
	
	// copy data from 2d array to temporary wave. copy back after all analysis
	w[] = rfc[p][index]

	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", w
	
	// Convert y axis to nm
	w *= NumberByKey("VPerLSB", header)
	w *= NumberByKey("deflSensFit", header)
	
	// Create x values wave for tip-sample-distance
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/ksFCPoints * p
	// Subtract deflection to get tip-sample-distance
	xTSD += w
	
	// Change y scale on all curves to pN
	Variable springConst = NumberByKey("springConst", header)
	w *= springConst * 1000
	
	WaveStats/Q xTSD
	xTSD -= V_min
	
	// write back curves to 2d wave
	rfc[][index] = w[p]
	rfc_x_tsd[][index] = xTSD[p]
	
	return 0	
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
	Make/N=(ksFCPoints) $(wname + "_blfit")
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
	Make/N=(ksFCPoints/8) $(wname + "_sensfit")	// display only 4096/8 points
	WAVE sensfit = $(wname + "_sensfit")
	SetScale/I x 0, (rampSize/8), "nm", sensfit
	// Save fit to fc<i>_sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	Variable deflSens = -1/W_coef[1]
	// Add fitted sens. to header data
	header += "deflSensFit:" + num2str(deflSens) + ";"
	//Note/K w, header
	// Change y scale on all curves to nm
	rw *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	timer3[index]=(ticks-tic3)/60
	
	tic4=ticks
	
	// Create x values wave for tip-sample-distance
	Make/N=(ksFCPoints) $(wname + "_x_tsd")
	WAVE xTSD = $(wname + "_x_tsd")
	
	timer4[index]=(ticks-tic4)/60
	
	// Write displacement x values
	xTSD = rampSize/ksFCPoints * p
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
