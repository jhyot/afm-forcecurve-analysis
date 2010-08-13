#pragma rtGlobals=1		// Use modern global access method.

#define DEBUG

// **** USER CONFIGURABLE CONSTANTS ****
//
// Change constants to adjust procedure behaviour

// Filter for reading force curve files in folder
static StrConstant ksFilter = ".spm"

// Required version of FC file
// for now, only tested with 0x07300000)
static StrConstant ksVersionReq = "0x07300000" 

// Points per FC
// for now only works with 4096
static Constant ksDataLength = 4096

// FC file type as written in header
static StrConstant ksFileType = "FOL"

// String to be matched (full match, case insensitive) at header end
static StrConstant ksHeaderEnd = "\\*File list end\r"

//
// **** END USER CONFIGURABLE CONSTANTS ****
//



// Start FC analysis with empty path
Function AnalyseFC()
	AnalyseAllFCInFolder("")
End Function



// Analyse all force curves (FC) in a folder
// Returns 0 on success, -1 on error
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
// Returns 0 on success, -1 on error
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
		
		try
			KillWaves $w; AbortOnRTE
		catch
			Print "Error in KillWaves. fc* waves in use? Errcode " + num2str(GetRTError(1))
			return -1
		endtry
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
	
	PathInfo path
	String pathString = S_path
	result = readFileIntoWave(S_path + filename, "fullHeader", ksHeaderEnd)
	if (result <= 0)
		Print fileName + ": Couldn't read header\r"
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

// Reads a file from String fileName (full path).
// Add all lines into a new text wave (String wname)
// String headerEnd indicates up to which part of the file to read
// (if empty, read full file)
// Return number of lines read if successful
// -1 otherwise.
Function readFileIntoWave(filename, wname, headerEnd)
	String filename, wname, headerEnd
	
	if ((strlen(filename) == 0) || (strlen(wname) == 0))
		return -1
	endif	
	
	
	// Read line by line until header end or file end reached
	
	Variable refNum
	Open/R refNum as fileName		
	if (refNum == 0)	
		return -1						// Error
	endif

	Make/T/O/N=0 $wname		// Make new text wave, overwrite old if needed
	WAVE/T w = $wname
	
	Variable len
	String buffer
	Variable line = 0
	
	do
		FReadLine refNum, buffer
		
		len = strlen(buffer)
		if (len == 0)
			if (strlen(headerEnd) > 0)
				// Header end was specified but not found, return error
				line = -1
				break
			else
				// Correctly reached file end
				break
			endif
		endif
		
		Redimension/N=(line+1) w		// Add one more row to wave
		// If line terminator (always \r, see FReadLine help) at end of line, remove it
		if (cmpstr(buffer[len-1], "\r") == 0)
			len -= 1
		endif
		w[line] = buffer[0,len-1]

		line += 1
		
		if (strlen(headerEnd) > 0)
			if (cmpstr(buffer, headerEnd) == 0)
				break							// End of header reached
			endif
		endif
	while (1)

	Close refNum
	return line
End


// Opens JPK force volume file and reads all curves
// into waves. Also extracts appropriate headers
//
// Parameters:
// String filename: full path to FV file
// 
// Return:
// 0 if no errors, -1 otherwise
Function readFVIntoWaves_JPK(filename)
	String filename			// full path + filename of JPK FV file	
	
	Variable result
	Variable index=0
	Variable success=0
	String fcHeaderData, fvHeaderData
	
	#ifdef DEBUG
		Variable timer0 = ticks
	#endif
	
	// IMPORTANT: will delete all previous waves in the current data folder starting with "fc"
	// Make sure that the waves are not in use anymore (i.e. close graphs etc.)
	result = KillPreviousWaves()
	if (result != 0)
		Print "Error killing previous waves"
		return -1
	endif

	// Get temp path from OS
	String tempPath = SpecialDirPath("Temporary", 0, 0, 0)
	
	// Create subfolder in temp path
	String unzipPath = tempPath+"jpkunzip"
	NewPath/Q/O/C tempPathSym, unzipPath
	
	Print "Unzipping FV file..."
	
	#ifdef DEBUG
		Variable timer1 = ticks
	#endif
		
	// Unzip file to temporary location
	// Needs ZIP XOP for this
	ZIPfile/O/X unzipPath, filename
	
	Print "Unzipping done."
	
	#ifdef DEBUG
		Print "DEBUG: ZIPfile time " + num2str((ticks - timer1)/60) + " s"
	#endif
	
	
	result = parseFVHeader_JPK(unzipPath, fvHeaderData)
	if (result != 0)
		Print "Error parsing FV header(s)"
		return -1
	endif
	
	// For all FCs, parse header and read data into waves
	Variable nMin = str2num(StringByKey("nMin", fvHeaderData))
	Variable nMax = str2num(StringByKey("nMax", fvHeaderData))
	String channelPath
	Variable i
	Variable rampSize
	for (i = nMin; i <= nMax; i += 1)
		// Parse FC header
		result = parseFCHeader_JPK(unzipPath, i, fcHeaderData)
		if (result != 0)
			Print "Error parsing FC header " + num2str(i) + " from " + unzipPath
			return -1
		endif
		
		// Read height data, save as wave, and use to calculate ramp size
		channelPath = unzipPath + ":index:" + num2str(i) + ":segments:0:channels:"
		GBLoadWave/N=wtemp/Q/T={2,4} (channelPath + "height.dat")
		if (V_flag != 1)
			Print "Error reading height data index " + num2str(i) + " from " + channelPath
			return -1
		endif
		
		WAVE wtemp0
		
		// convert raw data to nm
		wtemp0 *= str2num(StringByKey("rampSizeConv", fcHeaderData))

		WaveStats/Q wtemp0
		rampSize = V_max - V_min
		fcHeaderData += "rampSize:" + num2str(rampSize) + ";"
		
		// Final wave name fc<i>_x
		Duplicate/O wtemp0, $("fc" + num2str(i) + "_x")
		
		
		// Read vertical deflection data into wave
		GBLoadWave/N=wtemp/Q/T={2,4} (channelPath + "vDeflection.dat")
		if (V_flag != 1)
			Print "Error reading height data index " + num2str(i) + " from " + channelPath
			return -1
		endif
		
		// check if height wave and vdeflection wave have same number of points
		if (numpnts(wtemp0) != numpnts($("fc" + num2str(i) + "_x")))
			Print "Error: height and vDeflection data waves have different number of points"
			Print "in index " + num2str(i) + " of " + channelPath
			return -1
		endif
		
		Duplicate/O wtemp0, $("fc" + num2str(i))
		Note/K $("fc" + num2str(i)), fvHeaderData + fcHeaderData
		
	endfor
	
	KillPath tempPathSym
	
	#ifdef DEBUG
		Print "DEBUG: readFVIntoWaves_JPK time " + num2str((ticks - timer0)/60) + " s"
	#endif
	
	return 0

End


// Read and parse JPK FV headers given by path.
//
// Parameters:
// String path: path to force volume data root
// String &fvHeaderData: String to store header data in (pass by ref)
// 
// Return:
// 0 if no errors, -1 otherwise
//
// fvHeaderData is in "key1:value1;key2:value2;" format
// keys:
// nMin				First FC index
// nMax				Last FC index
// iLength			Grid size in i direction
// jLength			Grid size in j direction
Function parseFVHeader_JPK(path, fvHeaderData)
	String path
	String &fvHeaderData
	
	Variable result
	fvHeaderData = ""
	
	if (stringmatch(path, "*:") == 0)
		path += ":"
	endif

	
	// ===============================
	// Extract relevant FV header data
	// ===============================
	
	// Read force volume header lines into a wave
	result = readFileIntoWave(path + "header.properties", "fvHeader", "")
	if (result <= 0)
		Print "Could not read FV header"
		return -1
	endif


	WAVE/T fvHeader
	
	
	// Check if correct filetype and version
	String fvFileTypeReq = "spm-force-scan-map-file"
	String fvVersionReq = "0.6"
	String s
	
	FindValue/TEXT="jpk-data-file=" fvHeader
	if (V_value < 0)
		Print "Filetype not found"
		return -1
	endif
	SplitString/E="^jpk-data-file=(.+?)\\s*$" fvHeader[V_value], s
	if (cmpstr(s, fvFileTypeReq) != 0)
		Print "Wrong filetype (non-FV file)"
		return -1
	endif
	
	FindValue/TEXT="file-format-version=" fvHeader
	if (V_value < 0)
		Print "File version not found"
		return -1
	endif
	SplitString/E="^file-format-version=(.+?)\\s*$" fvHeader[V_value], s
	if (cmpstr(s, fvVersionReq) != 0)
		Print "Wrong FV file version"
		return -1
	endif
	

	// Get number of force curves
	Variable nMin, nMax
	FindValue/TEXT="force-scan-map.indexes.min=" fvHeader
	if (V_value < 0)
		Print "force-scan-map.indexes.min not found"
		return -1
	endif
	SplitString/E="^force-scan-map.indexes.min=(\\d+?)\\s*$" fvHeader[V_value], s
	if (strlen(s) <= 0)
		Print "force-scan-map.indexes.min invalid: " + fvHeader[V_value]
		return -1
	else
		fvHeaderData += "nMin:" + s + ";"
		nMin = str2num(s)
	endif
	
	FindValue/TEXT="force-scan-map.indexes.max=" fvHeader
	if (V_value < 0)
		Print "force-scan-map.indexes.max not found"
		return -1
	endif
	SplitString/E="^force-scan-map.indexes.max=(\\d+?)\\s*$" fvHeader[V_value], s
	if (strlen(s) <= 0)
		Print "force-scan-map.indexes.max invalid: " + fvHeader[V_value]
		return -1
	else
		fvHeaderData += "nMax:" + s + ";"
		nMax = str2num(s)
	endif
	
	if (nMax - nMin + 1 <= 0)
		Print "Error: Less than 1 force curve according to header"
		return -1
	endif
	
	
	// Get grid side lenghts
	FindValue/TEXT="force-scan-map.position-pattern.grid.ilength=" fvHeader
	if (V_value < 0)
		Print "force-scan-map.position-pattern.grid.ilength not found"
		return -1
	endif
	SplitString/E="^force-scan-map.position-pattern.grid.ilength=(\\d+?)\\s*$" fvHeader[V_value], s
	if (strlen(s) <= 0)
		Print "force-scan-map.position-pattern.grid.ilength invalid: " + fvHeader[V_value]
		return -1
	else
		fvHeaderData += "iLength:" + s + ";"
	endif
	
	FindValue/TEXT="force-scan-map.position-pattern.grid.jlength=" fvHeader
	if (V_value < 0)
		Print "force-scan-map.position-pattern.grid.jlength not found"
		return -1
	endif
	SplitString/E="^force-scan-map.position-pattern.grid.jlength=(\\d+?)\\s*$" fvHeader[V_value], s
	if (strlen(s) <= 0)
		Print "force-scan-map.position-pattern.grid.jlength invalid: " + fvHeader[V_value]
		return -1
	else
		fvHeaderData += "jLength:" + s + ";"
	endif
	
	return 0	
End



// Read and parse JPK FC headers given by path and curve index.
// Currently only reads approach curve header (segment 0) .
//
// Parameters:
// String path: path to force volume data root
// Variable index: index of force curve to read
// String &fcHeaderData: String to store header data in (pass by ref)
// 
// Return:
// 0 if no errors, -1 otherwise
//
// fcHeaderData is in "key1:value1;key2:value2;" format
// keys:
// rampSizeConv	Conversion factor from raw to nm in Z height data
// deflSens			Deflection sensitivity in nm/V
// springConst		Spring constant in nN/nm
Function parseFCHeader_JPK(path, index, fcHeaderData)
	String path
	Variable index
	String &fcHeaderData
	
	Variable result
	String s
	fcHeaderData = ""
	
	if (stringmatch(path, "*:") == 0)
		path += ":"
	endif
	
	
	// ===============================
	// Extract relevant FC header data
	// ===============================

	// Read force curve header lines into a wave.
	// Use 0th "segment", i.e. approach curve.
	String fcHeaderFile = path + "index:" + num2str(index)
	fcHeaderFile += ":segments:0:segment-header.properties"
	
	result = readFileIntoWave(fcHeaderFile, "fcHeader", "")
	if (result <= 0)
		Print "Could not read FC header"
		return -1
	endif

	WAVE/T fcHeader
	
	// Get Z piezo ramp size multiplier for converting raw value to nm
	// CHECK IF THIS IS CORRECT.... NOT FULLY CLEAR FROM JPK HEADER FILES
	
	// Get "nominal" ramp size multiplier
	FindValue/TEXT="channel.height.conversion-set.conversion.nominal.scaling.multiplier=" fcHeader
	if (V_value < 0)
		Print "channel.height.conversion-set.conversion.nominal.scaling.multiplier not found"
		return -1
	endif
	SplitString/E="^channel.height.conversion-set.conversion.nominal.scaling.multiplier=(.+?)\\s*$" fcHeader[V_value], s
	Variable rampSizeConv = str2num(s)
	if (cmpstr(num2str(rampSizeConv), "NaN") == 0)
		Print "channel.height.conversion-set.conversion.nominal.scaling.multiplier invalid: " + fcHeader[V_value]
		return -1
	endif
	
	// Get "calibrated" ramp size multiplier
	FindValue/TEXT="channel.height.conversion-set.conversion.calibrated.scaling.multiplier=" fcHeader
	if (V_value < 0)
		Print "channel.height.conversion-set.conversion.calibrated.scaling.multiplier not found"
		return -1
	endif
	SplitString/E="^channel.height.conversion-set.conversion.calibrated.scaling.multiplier=(.+?)\\s*$" fcHeader[V_value], s
	rampSizeConv *= str2num(s)
	rampSizeConv *= 1e9	// conversion m to nm
	if (cmpstr(num2str(rampSizeConv), "NaN") == 0)
		Print "channel.height.conversion-set.conversion.calibrated.scaling.multiplier invalid: " + fcHeader[V_value]
		return -1
	else
		fcHeaderData += "rampSizeConv:" + num2str(rampSizeConv) + ";"
	endif
	
	
	// Get deflection sensitivity in nm/V
	FindValue/TEXT="channel.vDeflection.conversion-set.conversion.distance.scaling.multiplier=" fcHeader
	if (V_value < 0)
		Print "channel.vDeflection.conversion-set.conversion.distance.scaling.multiplier not found"
		return -1
	endif
	SplitString/E="^channel.vDeflection.conversion-set.conversion.distance.scaling.multiplier=(.+?)\\s*$" fcHeader[V_value], s
	Variable deflSens = str2num(s)
	if (cmpstr(num2str(deflSens), "NaN") == 0)
		Print "channel.vDeflection.conversion-set.conversion.distance.scaling.multiplier invalid: " + fcHeader[V_value]
		return -1
	else
		fcHeaderData += "deflSens:" + num2str(deflSens * 1e9) + ";"
	endif

	// Get spring constant in nN/nm
	FindValue/TEXT="channel.vDeflection.conversion-set.conversion.force.scaling.multiplier=" fcHeader
	if (V_value < 0)
		Print "channel.vDeflection.conversion-set.conversion.force.scaling.multiplier not found"
		return -1
	endif
	SplitString/E="^channel.vDeflection.conversion-set.conversion.force.scaling.multiplier=(.+?)\\s*$" fcHeader[V_value], s
	Variable springConst = str2num(s)
	if (cmpstr(num2str(springConst), "NaN") == 0)
		Print "channel.vDeflection.conversion-set.conversion.force.scaling.multiplier invalid: " + fcHeader[V_value]
		return -1
	else
		fcHeaderData += "springConst:" + num2str(springConst) + ";"
	endif
	
	return 0
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


// Interactive review of force curves and curve fits
// Displays curves one by one and allows the user
// to accept or reject a given curve + fit.
// Rejected curve names and brush heights are
// moved to separate waves
// Expects following parameters:
// String names: name of wave filled with curve names to be reviewed
// String heights: name of wave filled with corresponding brush heights
// Rejected names and heights are moved to waves with same names but "_del" appended
// "names" wave is 2D with names[i][0] being the FC wave name,
// names[i][1] is the original filename of the curve
Function ReviewCurves(names, heights)
	String names, heights
	
	WAVE/T wNames = $names
	WAVE wHeights = $heights

	Variable total = numpnts(wHeights)
	Variable deleted = 0
	
	// Create waves for rejected curves
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
	
	// Create and change to temporary data folder
	// for the duration of the review
	NewDataFolder/O root:tmp_reviewDF
	
	for (i=0; i < totalTmp; i+=1)
		wname = wNames[i][0]
		WAVE w = $wname
		WAVE xTSD = $(wname + "_x_tsd")
		WAVE expfit = $(wname + "_expfit")
		
		header = note(w)
		
		// Display current force vs tip-sample distance and exponential fit
		DoWindow/K tmp_reviewgraph
		Display/N=tmp_reviewgraph w vs xTSD
		AppendToGraph expfit
		ModifyGraph rgb[0]=(0,15872,65280) 
		ShowInfo
		
		Variable/G root:tmp_reviewDF:rejected = 0
		
		// Create and show dialog window
		// with Accept, Zoom and Reject buttons
		// and some header data about current curve
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

		// Wait for user interaction (ends when dialog window is killed)
		PauseForUser tmp_reviewDialog, tmp_reviewgraph

		// Will be set to 1 if user pressed Reject button in review dialog
		NVAR gRej = root:tmp_reviewDF:rejected
		Variable rej = gRej
		
		// If rejected, copy the name and brush height of the curve to _del waves
		// then delete the curve from original wave
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


Function Unziptest()
	//function reads a file from a zip archive into memory
	// and returns it as a string

	Variable ref
	ref = ZIPa_openArchive("C:Users:Janne:Desktop:jpkfv.jpk-force-map")
	
	if (ref <= 0)
		Print "Error opening archive"
		return -1
	endif
		
	// Directory + file list
	String ls = ZIPa_ls(ref)
	
	print "open:"
	print ZIPa_open(ref, "index/0/segments/0/segment-header.properties")			
 
	String buf=""
	// Read 100 bytes from ref to buf
	ZIPa_read ref, buf, 100
	if (V_flag <= 0)
		Print "Error reading file or end of file"
		return -1
	endif
	
	ZIPa_closeArchive(ref)

	Print num2str(V_flag) + " bytes read"
	Print buf
	return 0
End


Function/t test()
	//function reads a file from a zip archive into memory
	// and returns it as a string

	variable id = 0, ii
	id = ZIPa_openArchive("foobar:Users:andrew:Desktop:Archive.zip")
	
	//should be > 0
	print id
		
	//prints "globalfit_test.pxp:otherStuff/:otherStuff/anotherFile.txt:"
	print ZIPa_ls(id)	

	//selects the globalfit_test.pxp file to be read from
	print ZIPa_open(id, "globalfit_test.pxp")			
 
	string buf="", buf2 = ""
	do
		//reads 10 bytes from the globalfit_test.pxp file into memory
		ZIPa_read id, buf, 10
		buf2 += buf
	while (V_Flag > 0)
	ZIPa_closeArchive(id)
	return buf2
end