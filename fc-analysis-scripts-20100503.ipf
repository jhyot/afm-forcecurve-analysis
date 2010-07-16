#pragma rtGlobals=1		// Use modern global access method.
#include <FilterDialog> menus=0
#include <SaveGraph>

// Change constants to adjust procedure behaviour
// Begin constant declarations
static StrConstant ksFilter = ".spm"		// Filter for reading FC files in folder
static StrConstant ksVersionReq = "0x07300000" // Required version of FC file; for now, only works with one specific version (NOTE: only tested with 0x07300000)
static Constant ksDataLength = 4096 // Points per FC; for now only works with same for all curves
static StrConstant ksFileType = "FOL"	// FC file type as written in header
static StrConstant ksHeaderEnd = "\\*File list end\r"  // String to be matched (full match, case insensitive) at header end
// End constant declarations

// Analyse all force curves (FC) in a folder
Function AnalyseAllFCInFolder(path)
	String path			// Symbolic path name
	
	Variable totalWaves
	Variable result

	totalWaves = ReadFCFilesIntoWaves(path)
	Print num2str(totalWaves) + " curves read into waves."
	if (totalWaves <= 0)
		return -1
	endif
	
	// Create 2 waves
	// One holds file and wave names, the other the corresponding brush heights
	// Values will be filled in in AnalyseBrushHeight
	// Old waves will be overwritten
	if (WaveExists(brushheight_names))
		KillWaves brushheight_names
	endif
	if (WaveExists(brushheights))
		KillWaves brushheights
	endif
	Make/T/O/N=(totalWaves, 2) brushheight_names
	Make/O/N=(totalWaves) brushheights
	
	Variable i
	for (i=0; i < totalWaves; i+=1)
		result = AnalyseBrushHeight(i, brushheight_names, brushheights)
	endfor
	
	ReviewCurves("brushheight_names", "brushheights")
	
	return 0
End

// Loop through all files in path with file filter ksFilter and read the data into individual waves
// Returns number of files that were read successfully
Function ReadFCFilesIntoWaves(path)
	String path			// Symbolic path name
	
	if (strlen(path)==0)				// If no path specified, create one
		NewPath/O temporaryPath			// This will put up a dialog
		if (V_flag != 0)
			return -1						// User cancelled
		endif
		path = "temporaryPath"
	endif
	
	
	String fileName
	Variable result
	Variable index=0
	Variable success=0
	String headerData
	
	// IMPORTANT: will delete all previous waves in the current data folder starting with "fc"
	// Make sure that the waves are not in use anymore (i.e. close graphs etc.)
	KillPreviousWaves()

	
	// Loop through each file in folder
	do											
		fileName = IndexedFile($path, index, ksFilter)
		if (strlen(fileName) == 0)					
			break			// No more files
		endif
		// Read and parse FC file header
		result = ParseFCHeader(path, fileName, headerData)
		if (result == 0)	
			// Load actual data into new wave
			// Waves are called fc0, fc1, etc.
			GBLoadWave/A=fc/B=1/P=$path/S=(NumberByKey("dataOffset", headerData))/T={16,4}/U=(ksDataLength)/W=1 fileName
			if (V_flag == 1)
				// Increment number of successfully read files
				headerData += "fileName:" + fileName + ";"
				Note/K $(StringFromList(0, S_waveNames)), headerData
				success += 1
			else
				Print fileName + ": less or more than 1 curve read from file"
			endif
		endif
		index += 1
	while (1)

	if (Exists("temporaryPath"))				// Kill temp path if it exists
		KillPath temporaryPath
	endif

	return success							// Return number of successfully read FC files
End


// Kills all waves in the current data folder starting with fc
Function KillPreviousWaves()
	Variable i = 0
	String wList
	String w
	
	wList = WaveList("fc*", ";", "")
	
	do
		w = StringFromList(i, wList, ";")
		if ((strlen(w) == 0) || (WaveExists($w) == 0))
			return 0
		endif
		
		KillWaves $w
		i += 1
	while(1)
End

// Read and parse FC file given by path and fileName
// Write relevant info about FC into String headerData (pass by ref)
// Return 0 if no errors, -1 otherwise
//
// headerData is in "key1:value1;key2:value2;" format
// keys:
// dataOffset		Byte offset to binary data start
// rampSize			Z piezo ramp size in nm
// VPerLSB			Vertical deflection V/LSB
// deflSens			Deflection sensitivity nm/V
// springConst		Spring constant nN/nm
Function ParseFCHeader(path, fileName, headerData)
	String path, fileName
	String &headerData
	
	Variable result, subGroupOffset
	headerData = ""
	
	
	result = ReadFCHeaderLines(path, fileName)
	if (result != 0)
		Print fileName + ": Did not find header end\r"
		return -1
	endif
	
	if (WaveExists(subGroupTitles))
		KillWaves subGroupTitles
	endif
	Make/T/O/N=0 subGroupTitles		// Will contain the grepped subgroup titles

	WAVE/T fullHeader
	WAVE/T subGroupTitles
	
	// Find indices of header subgroups (e.g. "\*Ciao scan list")
	// in fullHeader (created by ReadFCHeaderLines)
	Grep/INDX/E="^\\\\\\*.+$" fullHeader as subGroupTitles
	WAVE W_Index
	if (V_flag != 0)
		Print fileName + ": Error grepping subgroup titles"
		return -1			// Error
	endif
	
	
	// ============================
	// Extract relevant header data
	// ============================
	
	FindValue/TEXT="\\*Force file list"/TXOP=4 subGroupTitles		// case insensitive full wave element search
	if (V_value < 0)
		Print filename + ": \\*Force file list not found"
		return -1
	endif
	subGroupOffset = W_Index[V_value]
	
	// Check if correct version and filetype
	String s
	FindValue/S=(subGroupOffset)/TEXT="\\Version:" fullHeader
	if (V_value < 0)
		Print filename + ": Version not found"
		return -1
	endif
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	if (cmpstr(s, ksVersionReq, 1) != 0)
		Print filename + ": Wrong version"
		return -1
	endif
	FindValue/S=(subGroupOffset)/TEXT="\\Start context:" fullHeader
	if (V_value < 0)
		Print filename + ": File type not found"
		return -1
	endif
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	if (cmpstr(s, ksFileType, 1) != 0)
		Print filename + ": Wrong file type"
		return -1
	endif
	
	// Get data offset
	FindValue/S=(subGroupOffset)/TEXT="\\Data length:" fullHeader
	if (V_value < 0)
		Print filename + ": Data offset not found"
		return -1
	endif
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	if (str2num(s) <= 0)
		Print filename + ": Data offset <= 0"
		return -1
	endif
	headerData += "dataOffset:" + s + ";"
	
	// Check if correct number of points
	FindValue/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		Print filename + ": \\*Ciao force image list not found"
		return -1
	endif
	subGroupOffset = W_Index[V_value]
	
	FindValue/S=(subGroupOffset)/TEXT="\\Samps/line:" fullHeader
	if (V_value < 0)
		Print filename + ":Data points number not found"
		return -1
	endif
	SplitString/E=":\\s(\\d+)\\s\\d+$" fullHeader[V_value], s
	if (str2num(s) != ksDataLength)
		Print filename + ": Wrong number of data points per curve"
		return -1
	endif
	
	// Get Z piezo ramp size in V
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Ramp size:" fullHeader
	if (V_value < 0)
		Print filename + ": Ramp size not found"
		return -1
	endif
	SplitString/E="\\)\\s(.+)\\sV$" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": Ramp size invalid"
		return -1
	endif
	Variable rampSizeV = str2num(s)
	
	// Get spring constant in nN/nm
	FindValue/S=(subGroupOffset)/TEXT="\\Spring Constant:" fullHeader
	if (V_value < 0)
		Print filename + ": Spring const. not found"
		return -1
	endif
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": Spring const. invalid"
		return -1
	endif
	headerData += "springConst:" + s + ";"
	
	// Get vertical deflection V/LSB
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Z scale: V [Sens. DeflSens]" fullHeader
	if (V_value < 0)
		Print filename + ": Z scale not found"
		return -1
	endif
	SplitString/E="\\((.+)\\sV/LSB\\)" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": V/LSB invalid"
		return -1
	endif
	headerData += "VPerLSB:" + s + ";"

	// Get Z piezo sensitivity in nm/V
	FindValue/TEXT="\\*Scanner list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		Print filename + ": \\*Scanner list not found"
		return -1
	endif
	subGroupOffset = W_Index[V_value]
	
	FindValue/S=(subGroupOffset)/TEXT="\\@Sens. Zsens:" fullHeader
	if (V_value < 0)
		Print filename + ": Z piezo sens. not found"
		return -1
	endif
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": Z piezo sens. invalid"
		return -1
	endif
	// Calculate ramp size in nm
	headerData += "rampSize:" + num2str(str2num(s)*rampSizeV) + ";"
	
	// Get deflection sensitivity in nm/V
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		Print filename + ": \\*Ciao scan list not found"
		return -1
	endif
	subGroupOffset = W_Index[V_value]
	
	FindValue/S=(subGroupOffset)/TEXT="\\@Sens. DeflSens:" fullHeader
	if (V_value < 0)
		Print filename + ": Defl. sens. not found"
		return -1
	endif
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": Defl. sens. invalid"
		return -1
	endif
	headerData += "deflSens:" + s + ";"

	return 0	
End

// Read FC file given by path and fileName.
// Add all lines into a new text wave (fullHeader)
// return 0 if end of header found (defined by ksHeaderEnd)
// -1 otherwise.
// Last line of header not included in fullHeader.
// CR (\r) is at end of each line in the wave.
Function ReadFCHeaderLines(path, fileName)
	String path, fileName
	
	Variable result = -1			// Set to 0 if end of header found
	
	if ((strlen(path) == 0) || (strlen(fileName) == 0))
		return -1
	endif
	
	Variable refNum
	Open/R/P=$path refNum as fileName				
	if (refNum == 0)	
		return -1						// Error
	endif

	Make/T/O/N=0 fullHeader		// Make new text wave, overwrite old if needed
	
	Variable len
	String buffer
	Variable line = 0
	
	do
		FReadLine refNum, buffer
		
		len = strlen(buffer)
		if (len == 0)
			break										// No more lines to be read
		endif
		
		if (cmpstr(buffer, ksHeaderEnd) == 0)
			result = 0								// End of header reached
			break
		endif
		
		Redimension/N=(line+1) fullHeader		// Add one more row to wave
		fullHeader[line] = buffer[0,len-2]		// Add line to wave, omit trailing CR char

		line += 1
	while (1)

	Close refNum
	return result
End

// Analyse brush height, performing all the necessary data processing steps.
// Works in the current data folder with the wave named fc<i> with <i> being the index parameter.
// Returns 0 if all is successful, -1 otherwise.
//
// NOTE: A lot of parameters/assumptions are hardcoded here for brush extend FC curves with 4096 points
// (todo: change this in future)
Function AnalyseBrushHeight(index, wNames, wHeights)
	Variable index
	WAVE/T wNames
	WAVE wHeights
	
	String wname = "fc" + num2str(index)
	WAVE w = $wname
	String header = note(w)
	
	wNames[index][0] = wname
	wNames[index][1] = StringByKey("fileName", header)
	
	// Set Z piezo ramp size (x axis)
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", w
	
	// Convert y axis to V
	w *= NumberByKey("VPerLSB", header)
	
	// Fit baseline and subtract from curve
	CurveFit/NTHR=1/Q line  w[2600,3600]
	WAVE W_coef
	Make/N=(ksDataLength) $(wname + "_blfit")
	WAVE blfit = $(wname + "_blfit")
	SetScale/I x 0, (NumberByKey("rampSize", header)), "nm", blfit
	// Save baseline to fc<i>_blfit
	blfit = W_coef[0] + W_coef[1]*x
	// Subtr. baseline
	w -= (W_coef[0] + W_coef[1]*x)
	
	// Sometimes last points of curve are at smallest LSB value
	// Set those to 0 (i.e. if value < -3 V)
	w[3600,] = (w[p] > -3) * w[p]
	
	// Fit deflection sensitivity and change y scale
	CurveFit/NTHR=1/Q line  w[10,100]
	Make/N=(ksDataLength/8) $(wname + "_sensfit")	// display only 4096/8 points
	WAVE sensfit = $(wname + "_sensfit")
	SetScale/I x 0, (NumberByKey("rampSize", header)/8), "nm", sensfit
	// Save fit to fc<i>_sensfit
	sensfit = W_coef[0] + W_coef[1]*x
	Variable deflSens = -1/W_coef[1]
	// Add fitted sens. to header data
	header += "deflSensFit:" + num2str(deflSens) + ";"
	Note/K w, header
	// Change y scale on all curves to nm
	w *= deflSens
	blfit *= deflSens
	sensfit *= deflSens
	
	// Create x values wave for tip-sample-distance
	Make/N=(ksDataLength) $(wname + "_x_tsd")
	WAVE xTSD = $(wname + "_x_tsd")
	// Write displacement x values
	xTSD = NumberByKey("rampSize", header)/ksDataLength * p
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
	Note/K w, header
	
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
	Note/K w, header
	
	// Fit exponential curve to force-vs-tsd
	Variable V_fitError
	CurveFit/NTHR=1/Q exp_XOffset w[expFitStart,expFitEnd]/X=xTSD
	if (V_fitError)
		Print wname + ": Error doing CurveFit"
		return -1
	endif
	
	// Write some values to header note
	header += "expFitChiSq:" + num2str(V_chisq) + ";"
	header += "expFitTau:" + num2str(W_coef[2]) + ";"
	header += "expFitBL:" + num2str(W_coef[0]) + ";"
	Note/K w, header
	
	WAVE W_fitConstants
	// Save fit to fc<i>_expfit
	Make/N=(ksDataLength) $(wname + "_expfit")
	WAVE expfit = $(wname + "_expfit")
	// Set scale to match the tsd x scale
	SetScale/I x 0, (xTSD[numpnts(xTSD)-1]), "nm", expfit
	SetScale d 0, 0, "pN", expfit
	expfit = W_coef[0]+W_coef[1]*exp(-(x-W_fitConstants[0])/W_coef[2])
	
	// Point in FC where force is 1 pN higher than expfit baseline
	// equals brush start (defined arbitrarily)
	Variable heightP = BinarySearch(expfit, W_coef[0]+1)
	if (heightP < 0)
		Print wname + ": Brush start point not found"
		return -1
	endif
	Variable height = pnt2x(expfit, heightP+1)
	
	Print wname + ": Brush height = " + num2str(height)
	wHeights[index] = height

	return 0
End


Function ReviewCurves(names, heights)
	String names, heights
	
	WAVE/T wNames = $names
	WAVE wHeights = $heights

	Variable total = numpnts(wHeights)
	Variable deleted = 0
	
	if (WaveExists($(names + "_del")))
		KillWaves $(names + "_del")
	endif
	if (WaveExists($(heights + "_del")))
		KillWaves $(heights + "_del")
	endif
	Make/T/O/N=(total,2) $(names + "_del")
	Make/O/N=(total) $(heights + "_del")
	
	WAVE/T wNamesDel = $(names + "_del")
	WAVE wHeightsDel = $(heights + "_del")
	
	Variable i
	String wname, header, shortHeader
	Variable totalTmp = total
	
	NewDataFolder/O root:tmp_reviewDF
	
	for (i=0; i < totalTmp; i+=1)
		wname = wNames[i][0]
		WAVE w = $wname
		WAVE xTSD = $(wname + "_x_tsd")
		WAVE expfit = $(wname + "_expfit")
		
		header = note(w)
		
		DoWindow/K tmp_reviewgraph
		Display/N=tmp_reviewgraph w vs xTSD
		AppendToGraph expfit
		ModifyGraph rgb[0]=(0,15872,65280) 
		ShowInfo
		
		Variable/G root:tmp_reviewDF:rejected = 0
		
		NewPanel/K=2 /W=(300,300,600,600) as "Accept or reject curve?"
		DoWindow/C tmp_reviewDialog
		AutoPositionWindow/E/M=0/R=tmp_reviewgraph
		
		shortHeader = "Name: " + wNames[i][1] + " (" + wNames[i][0] + ")\r"
		shortHeader += "FitStart: " + StringByKey("expFitStartPt", header) + "\r"
		shortHeader += "FitEnd: " + StringByKey("expFitEndPt", header) + "\r"
		shortHeader += "FitTau: " + StringByKey("expFitTau", header) + "\r"
		shortHeader += "FitBL: " + StringByKey("expFitBL", header) + "\r"
		shortHeader += "BrushHeight: " + num2str(wHeights[i])
		DrawText 20, 100, shortHeader
		
		Button button0,pos={30,120},size={100,40},title="Accept"
		Button button0,proc=ReviewCurves_Accept
		Button button1,pos={30,165},size={100,40}
		Button button1,proc=ReviewCurves_Zoom,title="Zoom"
		Button button2,pos={30,215},size={100,40},title="Reject"
		Button button2,proc=ReviewCurves_Reject

		PauseForUser tmp_reviewDialog, tmp_reviewgraph

		NVAR gRej = root:tmp_reviewDF:rejected
		Variable rej = gRej
		
		if (rej)
			wNamesDel[deleted][0] = wNames[i][0]
			wNamesDel[deleted][1] = wNames[i][1]
			wHeightsDel[deleted] = wHeights[i]
			DeletePoints i, 1, wNames, wHeights
			deleted += 1
			i -= 1
			totalTmp -= 1
		endif
	endfor
	
	DoWindow/K tmp_reviewgraph
	KillDataFolder root:tmp_reviewDF
	
	Print "Review curves: " + num2str(deleted) + "/" + num2str(total) + " curves rejected."
	
End

Function ReviewCurves_Accept(ctrlName) : ButtonControl
	String ctrlName
	DoWindow/K tmp_reviewDialog			// Kill self
End

Function ReviewCurves_Reject(ctrlName) : ButtonControl
	String ctrlName
	Variable/G root:tmp_reviewDF:rejected = 1
	DoWindow/K tmp_reviewDialog		// Kill self
End

Function ReviewCurves_Zoom(ctrlName) : ButtonControl
	String ctrlName
	
	SetAxis/W=tmp_reviewgraph left, -30, 150
	SetAxis/W=tmp_reviewgraph bottom, -5, 50
End




// Helper functions, can be called from console
Function plot1(idx)
	Variable idx
	
	String wName = "fc" + num2str(idx)
	WAVE w = $wName
	WAVE wx = $(wName + "_x_tsd")
	WAVE wf = $(wName + "_expfit")
	
	Display w vs wx
	AppendToGraph wf
	ModifyGraph rgb[0]=(0,15872,65280) 
	ShowInfo
End

Function plot2(idx)
	Variable idx
	
	String wName = "fc" + num2str(idx)
	WAVE w = $wName
	WAVE wx = $(wName + "_x_tsd")
	WAVE wf = $(wName + "_expfit")
	
	Display w vs wx
	AppendToGraph wf
	ModifyGraph rgb[0]=(0,15872,65280) 

	ModifyGraph nticks(bottom)=10,minor(bottom)=1,sep=10,fSize=12,tickUnit=1
	Label left "\\Z13force (pN)"
	Label bottom "\\Z13tip-sample distance (nm)"
	SetAxis left -25,270
	SetAxis bottom -1,75
	
	ShowInfo
End

// waves: StringList of wave names (";" as separator)
// from, to: average wave range [from, to] (both inclusive)
// wave for averaged values
Function AvgWaves(waves, from, to, wavg, wsd)
	String waves
	Variable from, to
	WAVE wavg, wsd
	
	if (numpnts(wavg) < (to-from+1))
		Print "Target wave is not big enough"
		return -1
	endif
	
	Variable i = 0
	String wname
	Make/O/WAVE wlist
	
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
	Make/N=(wnum) wrow
	
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


// For debugging purposes
// Put debug snippets in this function to be able to run them
// from the console.
Function DebugTest()
	NewPath/O tmpPath1, "C:Users:Janne:Desktop:au-rings-afm:peg57:"
	Variable tmpRet
	String tmpHd
	
	tmpRet = ParseFCHeader("tmpPath1", "peg57-pbs-0.spm", tmpHd)
	Print "ret:" + num2str(tmpRet)
	Print tmpHd
End


Window Graph0() : Graph
	PauseUpdate; Silent 1		// building window...
	String fldrSav0= GetDataFolder(1)
	SetDataFolder root:figures:
	Display /W=(224.25,101,726,410.75) peg_pbs,peg_ar_am,peg_e11
	SetDataFolder fldrSav0
	ModifyGraph mode=3
	ModifyGraph marker(peg_pbs)=5,marker(peg_ar_am)=8,marker(peg_e11)=6
	ModifyGraph rgb(peg_pbs)=(0,0,0),rgb(peg_ar_am)=(21760,21760,21760),rgb(peg_e11)=(0,12800,52224)
	ModifyGraph hideTrace(peg_e11)=1
	ModifyGraph offset(peg_pbs)={5,0},offset(peg_e11)={-5,0}
	ModifyGraph grid(left)=2
	ModifyGraph tick(left)=2
	ModifyGraph nticks(left)=3
	ModifyGraph minor(left)=1
	ModifyGraph sep(left)=10,sep(bottom)=20
	ModifyGraph lblMargin(left)=6,lblMargin(bottom)=56
	ModifyGraph standoff(bottom)=0
	ModifyGraph axOffset(bottom)=3.8125
	ModifyGraph gridRGB(left)=(43520,43520,43520)
	Label left "height / nm"
	SetAxis left 0,70
	SetAxis bottom -15,520
	ErrorBars peg_pbs Y,wave=(:figures:peg_pbs_sd,:figures:peg_pbs_sd)
	ErrorBars peg_ar_am Y,wave=(:figures:peg_ar_am_sd,:figures:peg_ar_am_sd)
	ErrorBars peg_e11 Y,wave=(:figures:peg_e11_sd,:figures:peg_e11_sd)
	ShowInfo
	ShowTools/A
	SetDrawLayer UserFront
	DrawLine 0,0.601423487544484,0.958188153310105,0.601423487544484
	DrawLine 0.141114982578397,0.99288256227758,0.141114982578397,0.306049822064057
	DrawLine 0.898954703832753,0.99288256227758,0.898954703832753,0.359430604982206
	DrawLine 0.435540069686411,1,0.435540069686411,0.562277580071174
	DrawLine 0.566202090592335,0.99644128113879,0.566202090592335,0.569395017793594
EndMacro

Window Graph0_1() : Graph
	PauseUpdate; Silent 1		// building window...
	String fldrSav0= GetDataFolder(1)
	SetDataFolder root:figures:
	Display /W=(348.75,66.5,924.75,411.5) peg_pbs vs fv_x
	AppendToGraph peg_ar_am vs fv_x
	AppendToGraph peg_e11 vs fv_x
	AppendToGraph ::autest5:autest5_avg,peg_ar_am_fake_CS,peg_e11_fake_CS,::autest5:autest5_avg_SS
	SetDataFolder fldrSav0
	ModifyGraph mode(peg_pbs)=3,mode(peg_ar_am)=3,mode(peg_e11)=3
	ModifyGraph marker(peg_pbs)=5,marker(peg_ar_am)=8,marker(peg_e11)=6
	ModifyGraph lSize(autest5_avg)=1.5,lSize(autest5_avg_SS)=1.2
	ModifyGraph rgb(peg_pbs)=(16384,16384,65280),rgb(peg_ar_am)=(21760,21760,21760)
	ModifyGraph rgb(peg_e11)=(0,0,0),rgb(autest5_avg)=(48128,46080,2560),rgb(peg_ar_am_fake_CS)=(21760,21760,21760)
	ModifyGraph rgb(peg_e11_fake_CS)=(0,0,0),rgb(autest5_avg_SS)=(35584,34048,1792)
	ModifyGraph msize(peg_pbs)=4,msize(peg_ar_am)=4,msize(peg_e11)=4
	ModifyGraph useNegPat(autest5_avg)=1
	ModifyGraph hideTrace(autest5_avg)=1
	ModifyGraph offset(peg_pbs)={-245,0},offset(peg_ar_am)={-250,0},offset(peg_e11)={-255,0}
	ModifyGraph offset(autest5_avg)={-250,0},offset(peg_ar_am_fake_CS)={-250,0},offset(peg_e11_fake_CS)={-250,0}
	ModifyGraph offset(autest5_avg_SS)={-250,0}
	ModifyGraph grid(left)=2
	ModifyGraph tick=2
	ModifyGraph mirror=1
	ModifyGraph nticks(left)=3
	ModifyGraph minor=1
	ModifyGraph sep=20
	ModifyGraph lblMargin(left)=10,lblMargin(bottom)=66
	ModifyGraph axOffset(bottom)=3.875
	ModifyGraph gridRGB(left)=(43520,43520,43520)
	ModifyGraph lblLatPos(left)=2,lblLatPos(bottom)=5
	Label left "\\Z11height / nm"
	Label bottom "\\Z11"
	SetAxis left -0.5,66
	SetAxis bottom -262,288
	ErrorBars peg_pbs Y,wave=(:figures:peg_pbs_sd,:figures:peg_pbs_sd)
	ErrorBars peg_ar_am Y,wave=(:figures:peg_ar_am_sd,:figures:peg_ar_am_sd)
	ErrorBars peg_e11 Y,wave=(:figures:peg_e11_sd,:figures:peg_e11_sd)
	Cursor/P A autest5_avg_SS 18
	ShowInfo
	Legend/C/N=text0/J/H=7/T={29,66,108,144,180,216,252,288,324,360}/A=MC/X=-1.36/Y=-65.34
	AppendText "  \\F'Arial'\\s(peg_pbs) PEG + PBS    \\s(peg_ar_am) PEG + unspecific molecules    \\s(peg_e11) PEG + Anti-PEG   "
	ShowTools/A
EndMacro

Window Graph0_2() : Graph
	PauseUpdate; Silent 1		// building window...
	String fldrSav0= GetDataFolder(1)
	SetDataFolder root:figures:
	Display /W=(245.25,83.75,1020,581.75) peg_pbs vs fv_x
	AppendToGraph peg_ar_am vs fv_x
	AppendToGraph peg_e11 vs fv_x
	AppendToGraph ::autest5:autest5_avg,peg_ar_am_fake_CS,peg_e11_fake_CS,::autest5:autest5_avg_SS
	AppendToGraph peg_pbs_fake_CS
	SetDataFolder fldrSav0
	ModifyGraph mode(peg_pbs)=3,mode(peg_ar_am)=3,mode(peg_e11)=3,mode(autest5_avg_SS)=7
	ModifyGraph marker(peg_pbs)=16,marker(peg_ar_am)=19,marker(peg_e11)=17
	ModifyGraph lSize(autest5_avg)=1.5,lSize(autest5_avg_SS)=1.2
	ModifyGraph rgb(peg_pbs)=(0,15872,65280),rgb(peg_ar_am)=(39168,39168,0),rgb(peg_e11)=(0,0,0)
	ModifyGraph rgb(autest5_avg)=(48128,46080,2560),rgb(peg_ar_am_fake_CS)=(39168,39168,0)
	ModifyGraph rgb(peg_e11_fake_CS)=(0,0,0),rgb(autest5_avg_SS)=(35584,34048,1792)
	ModifyGraph rgb(peg_pbs_fake_CS)=(0,15872,65280)
	ModifyGraph msize(peg_pbs)=4,msize(peg_ar_am)=4,msize(peg_e11)=4
	ModifyGraph hbFill(autest5_avg_SS)=2
	ModifyGraph useNegPat(autest5_avg)=1,useNegPat(autest5_avg_SS)=1
	ModifyGraph usePlusRGB(autest5_avg_SS)=1
	ModifyGraph plusRGB(autest5_avg_SS)=(65280,65280,0)
	ModifyGraph hideTrace(autest5_avg)=1
	ModifyGraph offset(peg_pbs)={-255,0},offset(peg_ar_am)={-250,0},offset(peg_e11)={-245,0}
	ModifyGraph offset(autest5_avg)={-250,0},offset(peg_ar_am_fake_CS)={-250,0},offset(peg_e11_fake_CS)={-250,0}
	ModifyGraph offset(autest5_avg_SS)={-250,0},offset(peg_pbs_fake_CS)={-250,0}
	ModifyGraph grid(left)=2
	ModifyGraph tick=2
	ModifyGraph mirror=1
	ModifyGraph nticks(left)=3
	ModifyGraph minor=1
	ModifyGraph sep=20
	ModifyGraph fSize=13
	ModifyGraph lblMargin(left)=10,lblMargin(bottom)=91
	ModifyGraph axOffset(bottom)=5.84211
	ModifyGraph gridRGB(left)=(43520,43520,43520)
	ModifyGraph gridHair(left)=0
	ModifyGraph lblLatPos(left)=2,lblLatPos(bottom)=-1
	ModifyGraph tickUnit(bottom)=1
	Label left "\\Z13height (nm)"
	Label bottom "\\Z13width (nm)"
	SetAxis left -0.5,66
	SetAxis bottom -270,270
	ErrorBars/T=1.5/L=1.5 peg_pbs Y,wave=(:figures:peg_pbs_sd,:figures:peg_pbs_sd)
	ErrorBars/T=1.5/L=1.5 peg_ar_am Y,wave=(:figures:peg_ar_am_sd,:figures:peg_ar_am_sd)
	ErrorBars/T=1.5/L=1.5 peg_e11 Y,wave=(:figures:peg_e11_sd,:figures:peg_e11_sd)
	ShowInfo
	Legend/C/N=text0/J/H=7/T={29,66,108,144,180,216,252,288,324,360}/A=MC/X=-1.39/Y=-90.91
	AppendText "   \\Z12\\F'Arial'\\s(peg_pbs) PEG + PBS    \\s(peg_ar_am) PEG + unspecific molecules    \\s(peg_e11) PEG + Anti-PEG   "
	TextBox/C/N=text1/LS=5/F=0/H=10/B=1/A=MC/X=-32.04/Y=-72.44 "\\Z13\\s(peg_pbs) PEG\r\\s(peg_ar_am) PEG + specific IgG + unspecific IgG + BSA"
	AppendText "\\s(peg_e11) PEG + anti-PEG + BSA"
	ShowTools/A
EndMacro

Window Table0() : Table
	PauseUpdate; Silent 1		// building window...
	String fldrSav0= GetDataFolder(1)
	SetDataFolder root:figures:
	Edit/W=(137.25,176.75,821.25,429.5) fv_x,fv_x_aram_fake,fv_x_e11_fake,fv_x_pbs_fake
	AppendToTable peg_pbs,peg_ar_am,peg_e11
	ModifyTable format(Point)=1
	SetDataFolder fldrSav0
EndMacro

Window Layout0() : Layout
	PauseUpdate; Silent 1		// building window...
	Layout/C=1/W=(69.75,110,627,621.5) Graph2_1(76.5,281.25,472.5,491.25)/O=1/F=0,Graph2_2(76.5,489.75,472.5,699.75)/O=1/F=0
	Append Graph2(76.5,73.5,472.5,283.5)/O=1/F=0
EndMacro
