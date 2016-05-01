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
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc

Function LoadAndAnalyseAllFV()
	Variable result
	
	result = LoadForceMap()

	if (result<0)
		print "Aborted loading force map"
		return -1
	endif
	
	String/G :internalvars:selectionwave = "selectedcurves"
	Variable/G :internalvars:singleFCs = 0
	
	SVAR selectionwave = :internalvars:selectionwave
	NVAR numcurves = :internalvars:numCurves
	NVAR fcpoints = :internalvars:FCNumPoints

	Make/O/N=(numcurves) $selectionwave = NaN

	SVAR fvmeta
	Wave sel=$selectionwave
	Variable i
	for(i=0;i<(numcurves);i+=1)
		sel[i] = NumberByKey("dataOffset", fvmeta) + fcpoints*2*2*i
	endfor

	SVAR totalpath = :internalvars:totalpath


	ReadFCsInFile(totalpath)


	Analysis()

End


// Displays dialog to select force map file and
// calls the function to load header and FV image.
// Saves filename to global string variable.
//
// Returns 0 if map loaded correctly, -1 otherwise.
// Also sets global variable isDataLoaded to 1.
Function LoadForceMap()

 	if (SetSettings(0) < 0)
 		print "Loading aborted."
 		return -1
 	endif
	
	Variable/G :internalvars:isDataLoaded = 0
	NVAR isDataLoaded = :internalvars:isDataLoaded

	Variable result = 0
	Variable fileref = 0
	
	if (WaveExists($"fc"))
		DoAlert 1, "Another force map detected in current data folder\rContinuing will overwrite old waves, OK?"
		if (V_flag == 2)
			return -1
		endif
	endif
	
	Open/D/R/M="Open Force Volume Experiment File"/F="All Files:.*;" fileref
	
	if (cmpstr(S_fileName, "") == 0)
		print "No file selected"
		return -1
	endif
	
	Variable/G :internalvars:FVRowSize = ksFVRowSize
	Variable/G :internalvars:numCurves = ksFVRowSize*ksFVRowSize
	
	String/G :internalvars:totalpath = S_fileName
	SVAR totalpath = :internalvars:totalpath
	
	result = ReadMap(totalpath)
	
	if (result < 0)
		print "Error reading FV map"
		return -1
	endif
	
	print "Loaded file '" + totalpath + "' into " + TidyDFName(GetDataFolder(1))	
	isDataLoaded = 1
	return 0
	
End



Function LoadImage()
	
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	// Get filename
	Open/D/R/M="Open Image File"/F="All Files:.*;" fileref
	
	if (cmpstr(S_fileName, "") == 0)
		print "No file selected"
		return -1
	endif
	
	String filename = S_fileName
		
	// Get image metadata
	// Offsets(a), lengths(b), bytes(c), scaling(d) in header: "a0,b0,c0,d0;a1,b1,c1,d1;..."
	String header = ""
	Variable result = ParseImageHeader(filename, "imageheader", "imagetitles", header)
	
	if (result <= 0)
		print "Error parsing image header(s)"
		return -1
	endif
	
	Variable num = ItemsInList(header)
	
	Variable index = -1
	
	// Ask index of image to load. If only one image present, use that
	if (result > 1)
		String numlist = ""
		Variable i
		for (i = 0; i < num; i+=1)
			// Include in list if header parsed correctly
			if (cmpstr(StringFromList(i, header), "-") != 0)
				numlist += num2str(i) + ";"
			endif
		endfor
		
		String indexstr
		Prompt indexstr, "Image number to load", popup numlist
		DoPrompt "Load image", indexstr
		index = str2num(indexstr)
	else
		// Find the first (and only) entry which is not "-"
		for (i = 0; i < num; i+=1)
			if (cmpstr(StringFromList(i, header), "-") != 0)
				index = i
				print "Using automatically image " + num2str(index) + " in file"
				break
			endif
		endfor
	endif
	
	if (index < 0)
		print "Error selecting image index"
		return -1
	endif
	
	result = LoadImageFromFile(filename, index, header)
	
	if (result < 0)
		print "Error loading image"
		return -1
	endif
	
	ShowImage()
	
	SVAR imagegraph = :internalvars:imagegraph
	SetWindow $imagegraph,hook(imageinspect)=inspector

	return 0
		
End


// Loads external image from a file (e.g. FV, image(s) only)
// and replaces quasi-height topo of the original FV file.
//
// Returns 0 on success, < 0 for error
Function LoadImageFromFile(filename, index, header)
	String filename		// full path of file to read
	Variable index		// 0-based number of image in file to load
	String header		// header with data for all images, format see below
	
	NVAR numcurves = :internalvars:numCurves
	NVAR rowsize = :internalvars:FVRowSize
	
	//Offsets(a), lengths(b), bytes(c), scale(d) in header: "a0,b0,c0,d0;a1,b1,c1,d1;..."
	Variable offset = str2num(StringFromList(0, StringFromList(index,header), ","))
	Variable length = str2num(StringFromList(1, StringFromList(index,header), ","))
	Variable bpp = str2num(StringFromList(2, StringFromList(index,header), ","))
	Variable zscale = str2num(StringFromList(3, StringFromList(index,header), ","))
	
	if (length/bpp != numcurves)
		print filename + ": Size does not match FV data for image " + num2str(index)
		return -1
	endif
	
	GBLoadWave/Q/B/A=image/T={bpp*8,4}/S=(offset)/W=1/U=(length/bpp) filename
	
	if (V_flag < 1)
		print filename + ": Could not load image " + num2str(index)
		return -1
	endif

	String/G :internalvars:imagewave = StringFromList(0,S_waveNames)
	SVAR imagewave = :internalvars:imagewave
	
	WAVE w = $imagewave
	w *= zscale
	redimension/N=(rowSize,rowSize) $imagewave
	
	WAVE/T imageheader, imagetitles
	Variable scansize = Header_GetScanSize(imageheader, imagetitles)
	
	String n = "filename:" + filename + ";offset:" + num2str(offset) + ";length:" + num2str(length)
	n += ";bpp:" + num2str(bpp) + ";scaleNmPerLSB:" + num2str(zscale) + ";scansize:" + num2str(scansize) + ";"
	Note/K $imagewave, n
	
	return 0
End


// Reads header from FV file and stores it in a global variable.
// Reads and displays image (quasi-topography) from FV file.
// Overwrites previous force volume related files in current data folder.
//
// Returns 0 if no errors, -1 otherwise
Function ReadMap(fileName)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	
	NVAR numcurves = :internalvars:numCurves
	
	Variable result
	String headerData
	
	result = ParseFVHeader(fileName, "fullHeader", "subGroupTitles", headerData)
	
	if (result < 0)
		print "Could not parse force volume header correctly"
		return -1
	endif
	
	String/G fvmeta=headerData
	
	String imagemeta = ""
	result = ParseImageHeader(fileName, "imageheader", "imagetitles", imagemeta)
	
	if (result <= 0)
		print "Could not parse height image header correctly"
		return -1
	endif
	
	// Load by default first image in force volume file.
	// Assuming this is always the quasi-height image.
	result = LoadImageFromFile(filename, 0, imagemeta)
	if (result != 0)
		print "Could not load FV image data"
		return -1
	endif

	Variable fcpoints = NumberByKey("FCNumPoints", fvmeta)
	if ((ksFixPointNum == 1) && (fcpoints != ksFCPoints))
		print "[ERROR] Wrong number of points per curve in FV"
		return -1
	endif
	Variable/G :internalvars:FCNumPoints = fcpoints

	// Create waves for holding the curves (2d array, 1 column per curve)
	// and for metadata about each curve (1 row per curve)
	Make/O/N=(fcpoints, numcurves) fc=NaN, rfc=NaN
	Make/T/O/N=(numcurves) fcmeta=""

	ShowImage()

End


Function LoadAndAnalyseAllFC(path)
	String path
	
	Variable result
	result = LoadSingleFCFolder(path)

	if (result<0)
		print "Aborted loading force curves"
		return -1
	endif
	
	Variable i
	WAVE/T fcmeta
	String/G :internalvars:selectionwave = "selectedcurves"
	SVAR selectionwave = :internalvars:selectionwave
	NVAR numcurves = :internalvars:numCurves

	Make/O/N=(numcurves) $selectionwave = NaN


	Wave sel=$selectionwave

	for(i=0;i<(numcurves);i+=1)
		sel[i] = NumberByKey("dataOffset", fcmeta[i])
	endfor

	SVAR totalpath = :internalvars:totalpath


	ReadFCsInFolder()
	
	NVAR singlefc = :internalvars:singleFCs
	NVAR rowsize = :internalvars:FVRowSize

	Analysis()
End


Function LoadSingleFCFolder(path)
	String path				// Path string to folder with FCs
	
	if (SetSettings(SETTINGS_LOADFRIC + SETTINGS_LOADZSENS) < 0)
		print "Loading aborted."
		return -1
	endif
	
	
	if (WaveExists($"fcmeta"))
		DoAlert 1, "Other force data detected in current data folder\rContinuing will overwrite old waves, OK?"
		if (V_flag == 2)
			return -1
		endif
	endif
	
	if (strlen(path)==0)				// If no path specified, create one
		NewPath/O/Q tempFCpath			// This will put up a dialog
		if (V_flag != 0)
			return -1						// User cancelled
		endif
	else
		NewPath/O/Q tempFCpath, path
	endif
	
	Variable/G :internalvars:isDataLoaded = 0
	NVAR isDataLoaded = :internalvars:isDataLoaded
	Variable/G :internalvars:isZsensLoaded = 0
	NVAR isZsensLoaded = :internalvars:isZsensLoaded
	
	PathInfo tempFCpath
	String/G :internalvars:totalpath = S_path
	SVAR pathstr = :internalvars:totalpath
	
	String datatypelst = "line;box;random"
	String datatype = "line"
	
	NVAR/Z nodialogs = :internalvars:noDialogs
	if (!NVAR_Exists(nodialogs) || nodialogs == 0)
		Prompt datatype, "Type", popup, datatypelst
		DoPrompt "How were the curves recorded?", datatype
	
		if (V_flag == 1)
			// user cancelled
			print "User cancelled loading."
			return -1
		endif
	endif
	
	
	Variable t0 = ticks
	
	String filename = ""
	Make/T/FREE/N=0 filenames = ""
	//WAVE/T filenames
	Variable n = 0
	Variable i = 0
	// Loop through each file in folder
	do											
		filename = IndexedFile(tempFCpath, i, "????")
		if (strlen(fileName) == 0)					
			break			// No more files
		endif
		
		n = numpnts(filenames)
		Redimension/N=(n+1) filenames
		filenames[i] = filename
		
		i += 1	
	while (1)
	
	// Sort filenames explicitly, because the order returned by
	// the operating system might be arbitrary.
	Sort filenames, filenames
	
	Variable result = -1
	n = numpnts(filenames)
	
	Make/O/T/N=0 fcmeta = ""
	WAVE/T fcmeta
	
	Make/O/N=0 fc_z = NaN 
	WAVE fc_z
	
	Variable numread = 0
	
	String fullFilename = ""
	String headerData = ""
	
	Variable firstgood = 1
	for (i=0; i < n; i+=1)
		Prog("ReadSingleFCs", i+1, n)
		
		fullFilename = pathstr + filenames[i]
		headerData = ""
		result = ParseFCHeader(fullFilename, "fullheader", "subGroupTitles", headerData)
		
		if (result < 0)
			print fullFilename + ": not included"
			continue
		endif
		
		headerData += "filename:" + fullFilename + ";"
		
		Redimension/N=(numread+1) fcmeta
		fcmeta[numread] = headerData
		
		if (firstgood)
			firstgood = 0
			Variable fcpoints = NumberByKey("FCNumPoints", headerData)
			if ((ksFixPointNum == 1) && (ksFCPoints != fcpoints))
				print "[ERROR] Incorrect number of points per curve"
				return -1
			endif
			Variable/G :internalvars:FCNumPoints = fcpoints
			
			NVAR loadzsens = :internalvars:loadZSens
			if (loadzsens)
				Make/O/N=(fcpoints, 0) fc_zsens=NaN, rfc_zsens=NaN
			endif
		endif
		
		if (loadzsens)
			Redimension/N=(numread+1) fc_z
			Redimension/N=(-1, numread+1) fc_zsens, rfc_zsens
			fc_z[numread] = GetZPos(numread)
			if (numtype(fc_z[numread]) == 2)
				print fullFilename + ": couldn't extract Z position"
			else
				// at least one Z sensor curve loaded correctly, assume that Z sensor data is ok
				isZsensLoaded = 1
			endif
		endif
		
		numread += 1		
	endfor
	
	Variable/G :internalvars:numCurves = numread
	Variable/G :internalvars:FVRowsize = 0
	
	print pathstr + " "  + num2str(numread) + " files loaded into " + TidyDFName(GetDataFolder(1))
	printf "Elapsed time: %g seconds\r",round(10*(ticks-t0)/60)/10
	
	// maybe height data not yet correctly read out and "calibrated"
	// for now just transform it so that the overall topography looks ok
	if (isZsensLoaded)
		WaveStats/Q fc_z
		fc_z -= V_max
		fc_z *= -1
	endif
	
	strswitch (datatype)
		case "line":
			result = CreateLineSingleFCs()
			isDataLoaded = 1
			break
		case "box":
			result = CreateMapSingleFCs()
			ShowImage()
			isDataLoaded = 1
			break
		case "random":
			// Do nothing further
			isDataLoaded = 1
			break
		default:
			break
	endswitch
	
	Variable/G :internalvars:singleFCs = 1
	
	Make/O/N=(fcpoints, numread) fc=NaN, rfc=NaN
	
	NVAR loadfric = :internalvars:loadFriction
	if (loadfric)
		Make/O/N=(fcpoints, numread) fc_fric=NaN, rfc_fric=NaN
	endif
	
	if (Exists("tempFCpath"))
		KillPath tempFCpath
	endif
End


// Reads height sensor (Zsensor) data from file according to metadata
// And takes highest value of retract curve as Z height of the pixel
Function GetZPos(index)
	Variable index
	
	WAVE/T fcmeta
	WAVE fc_zsens, rfc_zsens
	
	String meta = fcmeta[index]
	
	String filename = StringByKey("filename", meta)
	Variable offs = NumberByKey("ZdataOffset", meta)
	Variable VperLSB = NumberByKey("ZVPerLSB", meta)
	Variable zsens = NumberByKey("ZSens", meta)
	
	Variable rampsize = NumberByKey("rampSize", meta)
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	Variable p0 = 0
	Variable zval = NaN
	
	GBLoadWave/N=fczload/B/Q/S=(offs)/T={16,4}/U=(fcpoints)/W=2 filename

	if (V_flag == 2)
		String fczname = StringFromList(0, S_waveNames)
		String rfczname = StringFromList(1, S_waveNames)
		WAVE fcz = $fczname
		WAVE rfcz = $rfczname
		
		fcz *= VperLSB
		fcz *= zsens
		rfcz *= VperLSB
		rfcz *= zsens
		
		// algo 1
		//WaveStats/Q/M=1 rfcz
		//zval = V_min
		
		// algo 2
		//WaveStats/Q/M=1 rfcz
		//zval = V_max - rampsize
		
		// algo 3
		zval = fcz[0]
		
		// save into waves, mirroring on x-axis and setting first point to 0
		// (to match normal ramp data)
		fcz *= -1
		rfcz *= -1
		p0 = fcz[0]
		fcz -= p0
		p0 = rfcz[0]
		rfcz -= p0
		fc_zsens[][index] = fcz[p]
		rfc_zsens[][index] = rfcz[p]
		
		
	else
		print filename + ": Couldn't find 2 force curves in Zsensor binary data (index " + num2str(index) + ")"
	endif
	
	KillWaves/Z $fczname, $rfczname
	
	return zval
End


Function CreateLineSingleFCs()
	
	WAVE/T fcmeta
	
	NVAR num = :internalvars:numCurves
	Variable/G :internalvars:FVRowsize = 0
	
	Make/N=(num)/O fc_x = NaN, fc_y = NaN
	WAVE fc_x, fc_y, fc_z
	
	Variable i = 0	
	for (i=0; i < num; i+=1)
		fc_x[i] = NumberByKey("xpos", fcmeta[i])
		fc_y[i] = NumberByKey("ypos", fcmeta[i])
	endfor
	
	Make/N=(num)/O fc_zx = 0
	Variable xdist = 0, ydist = 0
	for (i=1; i < num; i+=1)
		xdist = fc_x[i] - fc_x[i-1]
		ydist = fc_y[i] - fc_y[i-1]
		fc_zx[i] = fc_zx[i-1] + sqrt(xdist*xdist + ydist*ydist)
	endfor
	
	return 0
End


Function CreateMapSingleFCs()
	
	WAVE/T fcmeta
	NVAR num = :internalvars:numCurves
	Variable/G :internalvars:FVRowsize = ceil(sqrt(num))
	NVAR dimnum = :internalvars:FVRowsize
	NVAR fcpoints = :internalvars:FCNumPoints
	
	Make/N=(num)/O fc_x = NaN, fc_y = NaN
	WAVE fc_x, fc_y, fc_z
	
	Variable i = 0	
	for (i=0; i < num; i+=1)
		fc_x[i] = NumberByKey("xpos", fcmeta[i])
		fc_y[i] = NumberByKey("ypos", fcmeta[i])
	endfor
	
	Duplicate/O/FREE fc_x, fc_xround
	Duplicate/O/FREE fc_y, fc_yround

	WaveStats/Q fc_x
	Variable dimdeltax = (V_max - V_min) / (dimnum-1)
	fc_xround -= V_min
	
	WaveStats/Q fc_y
	Variable dimdeltay = (V_max - V_min) / (dimnum-1)
	fc_yround -= V_min
	
	Make/N=(dimnum, dimnum)/O imagefc = 0, imagefccount = 0
	Make/N=(dimnum, dimnum)/O/FREE imagepxtonum = 0
	Duplicate/O/FREE fc_z, fc_znum
	fc_znum = p
	
	// Work with integers ("pixel numbers") for image creation, otherwise rounding errors may cause unexpected behaviour
	// (incorrectly assigned pixels)
	fc_xround = round(fc_xround[p] / dimdeltax)
	fc_yround = round(fc_yround[p] / dimdeltay)
	SetScale/P x, 0, 1, "", imagefc, imagepxtonum
	SetScale/P y, 0, 1, "", imagefc, imagepxtonum
	
	ImageFromXYZ {fc_xround, fc_yround, fc_znum}, imagepxtonum, imagefccount
	Redimension/N=(numpnts(imagepxtonum)) imagepxtonum
	Sort imagepxtonum, fcmeta, fc_x, fc_y, fc_z, fc_xround, fc_yround
	
	imagefccount = 0
	ImageFromXYZ {fc_xround, fc_yround, fc_z}, imagefc, imagefccount
	
	WaveStats/Q imagefccount
	if (V_min != 1 || V_max != 1 || V_sum != num)
		print "WARNING: data not evenly assigned to pixels in image"
	endif
	
	Make/O/N=(fcpoints, num) fc=NaN, rfc=NaN	
	String/G :internalvars:imagewave = "imagefc"
	
	return 0
End


Function ReadForceCurves()

	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	NVAR/Z singlefc = :internalvars:singleFCs
	if (!NVAR_Exists(singlefc))
		Variable/G :internalvars:singleFCs = 0
	endif
	
	SVAR totalpath = :internalvars:totalpath
	String/G :internalvars:selectionwave = "selectedcurves"
	SVAR selectionwave = :internalvars:selectionwave
	
	NVAR numcurves = :internalvars:numCurves
	NVAR rowsize = :internalvars:FVRowSize
	
	Variable i = 0
	
	if (singlefc && (rowsize == 0))
		// If single FC data source, and no row size defined (i.e. not a box), load all curves
		Make/O/N=(numcurves) $selectionwave = NaN
		WAVE selsingle=$selectionwave
		WAVE/T fcmeta
		for(i=0; i < numcurves; i+=1)
			selsingle[i] = NumberByKey("dataOffset", fcmeta[i])
		endfor
		ReadFCsInFolder()
		return 0
	endif
	
	Variable del = 1
	WAVE/Z sel = $selectionwave
	if (WaveExists(sel) && (numpnts(sel) == numcurves))
		WaveStats/Q sel
		if (V_npnts > 0)
			// Some pixels were previously already selected. Keep?
			DoAlert 1, "Keep previous selection?"
			if (V_flag == 1)
				del = 0
			endif
		endif
	endif
	
	
	// Delete old markers from image graph if exists
	SVAR imagegraph = :internalvars:imagegraph
	DoWindow $imagegraph
	if (V_flag > 0)
		DrawAction/W=$imagegraph delete
	endif
	
	if (del == 1)
		Make/N=(numcurves)/O $selectionwave = NaN
	else
		// Redraw markers on graph if exists
		if (V_flag > 0)
			for (i=0; i < numcurves; i+=1)
				if (sel[i] > 0)
					// was previously selected
					Variable pixelX = mod(i,rowsize)
					Variable pixelY = floor(i/rowsize)
					DrawPointMarker(imagegraph, pixelX, pixelY, 0)
				endif
			endfor
		endif
	endif
			
	ChooseCurvesOnMap()
End



Function ChooseCurvesOnMap()
	SVAR imagegraph = :internalvars:imagegraph
	PauseUpdate; Silent 1		// building window...
	NewPanel/N=Dialog/W=(225,105,525,305) as "Dialog"
	AutoPositionWindow/M=0/R=$imagegraph
	Button done,pos={119,150},size={50,20},title="Done"
	Button done,proc=ChooseCurvesOnMap_button
	Button sall, pos={119,100},size={50,20},title="All"
	Button sall,proc=ChooseCurvesOnMap_button
	
	DoWindow/F $imagegraph
	SetWindow kwTopWin,hook(imageinspect)= $""
	SetWindow kwTopWin,hook(choose)=ChooseCurvesOnMap_Hook
End


Function ChooseCurvesOnMap_button(ctrl) : ButtonControl
	String ctrl
	
	NVAR singlefc = :internalvars:singleFCs
	
	strswitch (ctrl)
		case "done":
			// turn off the chooser hook
			SVAR imagegraph = :internalvars:imagegraph
			SetWindow $imagegraph,hook(choose)= $""
			if (singlefc == 1)
				ReadFCsInFolder()
			else
				SVAR totalpath = :internalvars:totalpath
				ReadFCsInFile(totalpath)
			endif
			
			DoWindow/K Dialog
			break
		
		case "sall":
			SVAR selectionwave = :internalvars:selectionwave
			WAVE sel=$selectionwave
			NVAR numcurves = :internalvars:numCurves
			NVAR fcpoints = :internalvars:FCNumPoints
			
			Variable i
			for(i=0;i<(numcurves);i+=1)
				if (singlefc == 1)
					WAVE/T fcmeta
					sel[i] = NumberByKey("dataOffset", fcmeta[i])
				else
					SVAR fvmeta
					sel[i] = NumberByKey("dataOffset", fvmeta)+fcpoints*2*2*i
				endif
			endfor	
			break
	endswitch

	return 0
End


Function ChooseCurvesOnMap_Hook(s)
	STRUCT WMWinHookStruct &s
	Variable rval = 0
	SVAR selectionwave = :internalvars:selectionwave
	SVAR imagegraph = :internalvars:imagegraph
	NVAR singlefc = :internalvars:singleFCs

	// React only on left mousedown
	if ((s.eventCode == 3) && (s.eventMod & 1 != 0))
		Variable mouseY = s.mouseLoc.v
		Variable mouseX = s.mouseLoc.h
		
		NVAR rowsize = :internalvars:FVRowSize
		NVAR fcpoints = :internalvars:FCNumPoints
		
		// Get image pixel and force curve number
		Variable pixelY = round(AxisValFromPixel(imagegraph, "left", mouseY-s.winrect.top))
		Variable pixelX = round(AxisValFromPixel(imagegraph, "bottom", mouseX-s.winrect.left))

		if(pixelX >= 0 && pixelX <= (rowsize-1) && pixelY >= 0 && pixelY <= (rowsize-1))
			DrawPointMarker(imagegraph, pixelX, pixelY, 0)
			// Write selected fc offset to selection wave
			WAVE sel=$selectionwave
			Variable fcnum = pixelX+(pixelY*rowsize)
			if (singlefc == 1)
				WAVE/T fcmeta
				sel[fcnum] = NumberByKey("dataOffset", fcmeta[fcnum])
			else
				SVAR fvmeta
				sel[fcnum] = NumberByKey("dataOffset", fvmeta)+fcpoints*2*fcnum*2
			endif
			print "X: " + num2str(pixelX) + "; Y: " + num2str(pixelY) + "; FC: ", num2str(fcnum)
		endif

		rval = 1
	endif

	return rval

End


Function ReadFCsInFolder()

	Variable result
	Variable success=0
	SVAR selectionwave = :internalvars:selectionwave
	
	NVAR numcurves = :internalvars:numCurves
	NVAR fcpoints = :internalvars:FCNumPoints
	
	variable t0=ticks
	
	WAVE dataOffsets=$selectionwave
	WAVE fc, rfc
	WAVE/T fcmeta
	String fileName = ""
	
	NVAR loadfric = :internalvars:loadFriction
	if (loadfric)
		WAVE fc_fric, rfc_fric
	endif
	
	Variable fricOffs = 0
	
	String/G :internalvars:yUnits = "LSB"
	
	// read selected FCs into 2d wave (1 curve per column, leave empty columns if wave not selected)
	Variable i=0
	for (i=0; i < numcurves; i+=1)						
		Prog("ReadWaves",i,numcurves)
		
		if(dataOffsets[i])
			// Read vertical deflection
			fileName = StringByKey("filename", fcmeta[i])
			GBLoadWave/N=fcload/B/Q/S=(dataOffsets[i])/T={16,4}/U=(fcpoints)/W=2 fileName
			
			if (V_flag == 2)
				WAVE fcloaded = $(StringFromList(0, S_waveNames))
				WAVE rfcloaded = $(StringFromList(1, S_waveNames))
				
				fc[][i] = fcloaded[p]
				rfc[][i] = rfcloaded[p]
				
				// Increment number of successfully read files
				success += 1
			else
				Print "Did not find approach + retract curves at index " + num2str(i)
				continue
			endif
			
			// Read horizontal deflection (friction)
			if (loadfric)
				fricOffs = NumberByKey("FricDataOffset", fcmeta[i])
				GBLoadWave/N=fcfricload/B/Q/S=(fricOffs)/T={16,4}/U=(fcpoints)/W=2 fileName
				
				if (V_flag == 2)
					WAVE fcloaded = $(StringFromList(0, S_waveNames))
					WAVE rfcloaded = $(StringFromList(1, S_waveNames))
					
					fc_fric[][i] = fcloaded[p] 
					rfc_fric[][i] = rfcloaded[p]
					
				else
					Print "Did not find friction approach + retract curves at index " + num2str(i)
				endif
			endif
			
		endif		
	endfor
	
	printf "Elapsed time: %g seconds\r",round(10*(ticks-t0)/60)/10

	// Create wave for the brush heights
	// Value will be filled in AnalyseBrushHeight
	// Old waves will be overwritten
	// (same for retractfeature)
	Make/O/N=(numcurves) brushheights = NaN
	Make/O/N=(numcurves) retractfeature = NaN
	
	KillWaves/Z fcload0, fcload1, fcfricload0, fcfricload1

	return success
End


Function ReadFCsInFile(fileName)
	String fileName			// Igor-style path: e.g. "X:Code:igor-analyse-forcecurves:test-files:pegylated_glass.004"
	
	Variable result
	Variable index=0
	Variable success=0
	SVAR fvmeta
	SVAR selectionwave = :internalvars:selectionwave
	SVAR imagegraph = :internalvars:imagegraph
	NVAR numcurves = :internalvars:numCurves
	NVAR fcpoints = :internalvars:FCNumPoints

	
	DoWindow/F $imagegraph	// Bring graph to front
	if (V_Flag == 0)			// Verify that graph exists
		print "Error: Couldn't display image"
		return -1
	endif
	
	variable t0=ticks
	
	WAVE dataOffsets=$selectionwave
	WAVE fc, rfc
	WAVE/T fcmeta
	
	String/G :internalvars:yUnits = "LSB"
	
	// read selected FCs into 2d wave (1 curve per column, leave empty columns if wave not selected)
	do												
		if(dataOffsets[index])
			
			GBLoadWave/N=fcload/B/Q/S=(dataOffsets[index])/T={16,4}/U=(fcpoints)/W=2 fileName
			
			if (V_flag == 2)
				WAVE fcloaded = $(StringFromList(0, S_waveNames))
				WAVE rfcloaded = $(StringFromList(1, S_waveNames))
				
				fc[][index] = fcloaded[p]
				rfc[][index] = rfcloaded[p]
				
				fcmeta[index] = fvmeta
				// Increment number of successfully read files
				success += 1
			else
				Print "Did not find approach + retract curves at position " + num2str(index)
			endif
		endif

		index += 1
		
		Prog("ReadWaves",index,numcurves)
		
	while (index < numcurves)
	
	printf "Elapsed time: %g seconds\r",round(10*(ticks-t0)/60)/10

	// Create wave for the brush heights
	// Value will be filled in AnalyseBrushHeight
	// Old waves will be overwritten
	// (same for retractfeature)
	Make/O/N=(numcurves) brushheights = NaN
	Make/O/N=(numcurves) retractfeature = NaN
	
	KillWaves/Z fcload0, fcload1

	return success	
End


