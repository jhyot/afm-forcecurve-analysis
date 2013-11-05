#pragma rtGlobals=3		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc


#include ":fc-script-config"
#include ":fitting"




// TODO
// enhance retraction curve handling
// Make multiple 2d arrays possible in same datafolder (keep track of wave names etc instead of hardcoding)
// Make button in heightimage and heightmap for inspect mode (i.e. be able to turn off inspect mode)
// indicate flagged curves in review
// Running analysis more than once changes the data (because LSB->V->nm->N transformation happens inline in fc wave)
//
// Print analysis algorithm name and parameters when starting analysis
// rename analysis parameter constants to be absolutely clear from their names
// Single FCs: do appropriate checks in user accessible functions (like in all the other ones)





// Internal constants, do not change
Static Constant SETTINGS_LOADFRIC = 1
Static Constant SETTINGS_LOADZSENS = 2



// Create Igor Menu
Menu "Force Map Analysis"
	"Open FV File...", LoadForceMap()
	"Load and Analyse Whole FV Map...", LoadAndAnalyseAllFV()
	"Open FC Folder...", LoadSingleFCFolder("")
	"Load and Analyse Whole FC Folder...", LoadAndAnalyseAllFC("")
	"-"
	"\\M0Select / Load Curves", ReadForceCurves()
	"Start Analysis", Analysis()
	"-"
	"Load Image...", LoadImage()
	"Show Image", ImageToForeground()
	"Show Height Map", MapToForeground()
	"-"
	Submenu "Review"
		"Flag curves...", FlagCurves()
		"Mark flagged", MarkFlaggedPixels()
		"-"
		"Review Flagged Curves", ReviewCurvesFlagged()
		"Review All Curves", ReviewCurvesAll()
	End
	"-"
	"Settings...", SetSettings()
End


Function LoadAndAnalyseAllFV()
	Variable result
	
	result = LoadForceMap()

	if (result<0)
		print "Aborted loading force map"
		return -1
	endif
	
	Variable i
	String/G fvmeta
	String/G :internalvars:selectionwave = "selectedcurves"
	SVAR selectionwave = :internalvars:selectionwave
	NVAR numcurves = :internalvars:numCurves

	Make/O/N=(numcurves) $selectionwave = NaN


	Wave sel=$selectionwave

	for(i=0;i<(numcurves);i+=1)
		sel[i] = NumberByKey("dataOffset", fvmeta) + ksFCPoints*2*2*i
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
	Variable scale = str2num(StringFromList(3, StringFromList(index,header), ","))
	
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
	w *= scale
	redimension/N=(rowSize,rowSize) $imagewave
	
	String n = "filename:" + filename + ";offset:" + num2str(offset) + ";length:" + num2str(length)
	n += ";bpp:" + num2str(bpp) + ";scaleNmPerLSB:" + num2str(scale) + ";"
	Note/K $imagewave, n
	
	return 0
End


// Kills all waves in the current data folder starting with fc* and rfc*
//
// Returns 0 on success
Function KillPreviousWaves()
	Variable i = 0
	String wList,rwList
	String w, rw
	
	wList = WaveList("fc*", ";", "")
	rwList = WaveList("rfc*", ";", "")
	
	do
		w = StringFromList(i, wList, ";")
		
		
		if ((strlen(w) == 0) || (WaveExists($w) == 0))
			break
		endif
		
		KillWaves $w
		i+=1

	while(1)

	i=0
	do
		rw = StringFromList(i, rwList, ";")
		
		
		if ((strlen(rw) == 0) || (WaveExists($rw) == 0))
			break
		endif
		
		KillWaves $rw
		i+=1
	while(1)

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
	
	// Read and parse FC file header
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

	// Create waves for holding the curves (2d array, 1 column per curve)
	// and for metadata about each curve (1 row per curve)
	Make/O/N=(ksFCPoints, numcurves) fc=NaN, rfc=NaN
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
	
	if (singlefc && (rowsize == 0))
		PlotXsectFC()
	endif

End


Function LoadSingleFCFolder(path)
	String path				// Path string to folder with FCs
	
	if (SetSettings(SETTINGS_LOADFRIC + SETTINGS_LOADZSENS) < 0)
		print "Loading aborted."
		return -1
	endif
	
	Variable/G :internalvars:isDataLoaded = 0
	NVAR isDataLoaded = :internalvars:isDataLoaded
	
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
	
	PathInfo tempFCpath
	String/G :internalvars:totalpath = S_path
	SVAR pathstr = :internalvars:totalpath
	
	String datatypelst = "line;box;random"
	String datatype = "line"
	Prompt datatype, "Type", popup, datatypelst
	DoPrompt "How were the curves recorded?", datatype
	
	if (V_flag == 1)
		// user cancelled
		print "User cancelled loading."
		return -1
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
		
		Redimension/N=(numread+1) fc_z
		fc_z[numread] = GetZPos(numread)
		if (numtype(fc_z[numread]) == 2)
			print fullFilename + ": couldn't extract Z position"
		endif
		
		numread += 1		
	endfor
	
	Variable/G :internalvars:numCurves = numread
	Variable/G :internalvars:FVRowsize = 0
	
	print pathstr + " "  + num2str(numread) + " files loaded into " + TidyDFName(GetDataFolder(1))
	printf "Elapsed time: %g seconds\r",round(10*(ticks-t0)/60)/10
	
	// maybe height data not yet correctly read out and "calibrated"
	// for now just transform it so that the overall topography looks ok
	WaveStats/Q fc_z
	fc_z -= V_max
	fc_z *= -1
	
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
	
	Make/O/N=(ksFCPoints, numread) fc=NaN, rfc=NaN
	
	NVAR loadfric = :internalvars:loadFriction
	if (loadfric)
		Make/O/N=(ksFCPoints, numread) fc_fric=NaN, rfc_fric=NaN
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
	
	String meta = fcmeta[index]
	
	String filename = StringByKey("filename", meta)
	Variable offs = NumberByKey("ZdataOffset", meta)
	Variable VperLSB = NumberByKey("ZVPerLSB", meta)
	Variable zsens = NumberByKey("ZSens", meta)
	
	Variable zval = NaN
	
	GBLoadWave/N=fczload/B/Q/S=(offs)/T={16,4}/U=(ksFCPoints)/W=2 filename

	if (V_flag == 2)
		String fczname = StringFromList(0, S_waveNames)
		String rfczname = StringFromList(1, S_waveNames)
		WAVE fcz = $fczname
		WAVE rfcz = $rfczname
		
		rfcz *= VperLSB
		rfcz *= zsens
		
		WaveStats/Q rfcz
		zval = V_min
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
	
	Make/O/N=(ksFCPoints, num) fc=NaN, rfc=NaN	
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
		// If single FC data source, and now row size defined (i.e. not a box), load all curves
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
			Variable i
			for(i=0;i<(numcurves);i+=1)
				if (singlefc == 1)
					WAVE/T fcmeta
					sel[i] = NumberByKey("dataOffset", fcmeta[i])
				else
					SVAR fvmeta
					sel[i] = NumberByKey("dataOffset", fvmeta)+ksFCPoints*2*2*i
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
				sel[fcnum] = NumberByKey("dataOffset", fvmeta)+ksFCPoints*2*fcnum*2
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
	
	// read selected FCs into 2d wave (1 curve per column, leave empty columns if wave not selected)
	Variable i=0
	for (i=0; i < numcurves; i+=1)						
		Prog("ReadWaves",i,numcurves)
		
		if(dataOffsets[i])
			// Read vertical deflection
			fileName = StringByKey("filename", fcmeta[i])
			GBLoadWave/N=fcload/B/Q/S=(dataOffsets[i])/T={16,4}/U=(ksFCPoints)/W=2 fileName
			
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
				GBLoadWave/N=fcfricload/B/Q/S=(fricOffs)/T={16,4}/U=(ksFCPoints)/W=2 fileName
				
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

	
	DoWindow/F $imagegraph	// Bring graph to front
	if (V_Flag == 0)			// Verify that graph exists
		Abort "UserCursorAdjust: No such graph."
		return -1
	endif
	
	variable t0=ticks
	
	WAVE dataOffsets=$selectionwave
	WAVE fc, rfc
	WAVE/T fcmeta
	
	// read selected FCs into 2d wave (1 curve per column, leave empty columns if wave not selected)
	do												
		if(dataOffsets[index])
			
			GBLoadWave/N=fcload/B/Q/S=(dataOffsets[index])/T={16,4}/U=(ksFCPoints)/W=2 fileName
			
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



Function rinspector(s)			//retractfeature
	STRUCT WMWinHookStruct &s
	Variable rval = 0
	variable mouseloc,xval,yval, xbla,ybla
	SVAR selectionwave = :internalvars:selectionwave
	NVAR rowsize = :internalvars:FVRowSize


	if ((s.eventCode == 3) && (s.eventMod & 1 != 0))
			yval=s.mouseLoc.v
			xval=s.mouseLoc.h


			ybla=round(axisvalfrompixel("retractfeaturesdetection","left",yval-s.winrect.top))
			xbla=round(axisvalfrompixel("retractfeaturesdetection","bottom",xval-s.winrect.left))


			wave sel=$selectionwave


			if(xbla>=0 && xbla<=(rowsize-1) && ybla>=0 && ybla<=(rowsize-1) && sel[xbla+(ybla*rowsize)])

				rplot2(abs(xbla+(ybla*rowsize)))


				print "FCNumber:",xbla+(ybla*rowsize)
				print "X:",xbla,"Y:",ybla
				//print "Brushheight for selection:",brushheights[xbla+(ybla*rowsize)],"nm"

			else

				print "No Data here!"

			endif

	endif

	return rval

End



Function inspector(s)			//heightsmap
	STRUCT WMWinHookStruct &s
	Variable rval = 0
	SVAR/Z selectionwave = :internalvars:selectionwave
	SVAR/Z resultgraph = :internalvars:resultgraph
	SVAR/Z imagegraph = :internalvars:imagegraph
	
	if (!(SVAR_Exists(selectionwave) && SVAR_Exists(resultgraph) && SVAR_Exists(imagegraph)))
		return rval
	endif
	
	WAVE/Z sel = $selectionwave
	if (!WaveExists(sel))
		return rval
	endif
	
	// if event is from a graph that does not correspond to the saved graph names, ignore it
	if ((cmpstr(s.WinName, imagegraph) != 0) && (cmpstr(s.WinName, resultgraph) !=0))
		return rval
	endif
	
	NVAR rowsize = :internalvars:FVRowSize
	
	Variable mouseX = s.mouseLoc.h
	Variable mouseY = s.mouseLoc.v
	Variable pixelX = round(AxisValFromPixel("", "bottom", mouseX - s.winrect.left))
	Variable pixelY = round(AxisValFromPixel("", "left", mouseY - s.winrect.top))
	Variable fcnum = abs(pixelX+(pixelY*rowsize))
	
	switch (s.eventCode)
	
		// mousemoved
		case 4:
			if(pixelX >= 0 && pixelX <= (rowsize-1) && pixelY >= 0 && pixelY <= (rowsize-1) && sel[fcnum])
				WAVE brushheights
				Variable h = round(brushheights[fcnum]*10)/10
				TextBox/W=$s.WinName/C/F=0/B=3/N=hovertext/A=LB/X=(pixelX/rowsize*100+10)/Y=(pixelY/rowsize*100) " " + num2str(h) + " "
			else
				TextBox/W=$s.WinName/C/N=hovertext ""
			endif
			
			rval = 0
			break
			
		// mousedown
		case 3:
			// only on left mouseclick
			if (s.eventMod & 1 != 0)

				if(pixelX >= 0 && pixelX <= (rowsize-1) && pixelY >= 0 && pixelY <= (rowsize-1) && sel[fcnum])
					// Put marker on selected pixel on image and result graphs
					DrawPointMarker(imagegraph, pixelX, pixelY, 1)
					DrawPointMarker(resultgraph, pixelX, pixelY, 1)
					
					// Show new graph with curve
					PlotFC(fcnum)
	
					WAVE brushheights
					WAVE/T fcmeta
					
					print "FCNumber: " + num2str(fcnum) + "; X: " + num2str(pixelX) + "; Y: " + num2str(pixelY) + "; Brush height:", brushheights[fcnum], "nm"
					print fcmeta[fcnum]
					
					rval = 1
				endif
			endif
			break
	endswitch

	return rval
End


// Extracts section titles (e.g. "\*Ciao scan list") from the header
// and saves them into new text wave (titleswave).
// Also creates wave W_Index with the positions of the section titles within full header
//
// Returns 0 if success, < 0 if error.
Function GetHeaderSectionTitles(headerwave, titleswave)
	String headerwave		// Name of the text wave with the header lines (must exist and be populated)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	
	Make/T/O/N=0 $titleswave = ""

	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	
	// Find indices of header subgroups (e.g. "\*Ciao scan list")
	// in fullHeader (created by ReadFCHeaderLines)
	Grep/INDX/E="^\\\\\\*.+$" fullHeader as subGroupTitles
	if (V_flag != 0)
		return -1			// Error
	endif
	
	WAVE W_Index
	Redimension/N=(numpnts(subGroupTitles), 2) subGroupTitles
	subGroupTitles[][1] = num2str(W_Index[p])
	
	return 0	
End


Function/S Header_GetVersion(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Force file list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return ""
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Version:" fullheader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return ""
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	
	return s
End


Function/S Header_GetFiletype(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Force file list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return ""
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Start context:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return ""
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s

	return s
End


Function Header_GetNumPoints(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return -1
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Samps/line:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\s(\\d+)\\s\\d+$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetXPos(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return NaN
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\X Offset:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return NaN
	endif
	String s
	SplitString/E=":\\s((-|\\+)?\\d+\\.?\\d*)\\s+nm$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetYPos(fullheader, subGroupTitles)
	WAVE/T fullheader, subGroupTitles
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return NaN
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\Y Offset:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return NaN
	endif
	String s
	SplitString/E=":\\s((-|\\+)?\\d+\\.?\\d*)\\s+nm$" fullHeader[V_value], s

	return str2num(s)
End


// Returns the data set number where the given data type is found
// (-1 if no match)
Function Header_FindDataType(fullheader, subGroupTitles, type)
	WAVE/T fullheader, subGroupTitles
	String type
	
	Variable start = -1
	Variable groupOffs = -1
	Variable i = -1
	Variable found = 0
	String s = ""
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
		groupOffs = str2num(subGroupTitles[start][1])
			
		FindValue/S=(groupOffs)/TEXT="\\@4:Image Data:" fullHeader
		if ((V_value < 0) || ((start < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[start+1][1]))))
			return -1
		endif

		SplitString/E=":.*\\[(.+)\\]" fullHeader[V_value], s
		
		if (cmpstr(s, type) == 0)
			found = 1
			break
		endif
	While (1)
	
	if (found)
		return i
	else
		return -1
	endif
End


Function Header_GetDataOffset(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\Data offset:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s

	return str2num(s)
End


// Returns ramp size in nm
Function Header_GetRampSize(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Ramp size:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E="\\)\\s(.+)\\sV$" fullHeader[V_value], s
	Variable rampSizeV = str2num(s)	
	
	// Z piezo sensitivity
	FindValue/TEXT="\\*Scanner list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return -1
	endif
	subGroup = V_value
	subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	FindValue/S=(subGroupOffset)/TEXT="\\@Sens. Zsens:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s

	return rampSizeV * str2num(s)
End


Function Header_GetSpringConst(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\Spring Constant:" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetLSBScale(fullheader, subGroupTitles, index)
	WAVE/T fullheader, subGroupTitles
	Variable index		// index'th data set in file (0-based)
	
	Variable start = -1
	Variable i = -1
	
	Do
		FindValue/S=(start+1)/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			break
		endif
		
		i += 1
		start = V_value
	While (i < index)
	
	// Didn't find enough subgroups to get to the index'th one
	if (i != index)
		return -1
	endif
	
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
		
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Z scale: V" fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E="\\]\\s\\((.+)\\sV/LSB\\)" fullHeader[V_value], s

	return str2num(s)
End


Function Header_GetSens(fullheader, subGroupTitles, type)
	WAVE/T fullheader, subGroupTitles
	String type
	
	FindValue/TEXT="\\*Ciao scan list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		return -1
	endif
	Variable subGroup = V_value
	Variable subGroupOffset = str2num(subGroupTitles[subGroup][1])
	
	String searchtext = "\\@Sens. " + type + ":"
	
	FindValue/S=(subGroupOffset)/TEXT=(searchtext) fullHeader
	if ((V_value < 0) || ((subGroup < DimSize(subGroupTitles,0)-1) && (V_value >= str2num(subGroupTitles[subGroup+1][1]))))
		return -1
	endif
	String s
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s

	return str2num(s)
End


Function ParseFCHeader(filename, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result, subGroupOffset
	headerData = ""
	
	
	result = ReadHeaderLines(fileName, headerwave)
	if (result != 0)
		Print fileName + ": Did not find header end"
		return -1
	endif
	
	result = GetHeaderSectionTitles(headerwave, titleswave)
	if (result != 0)
		print fileName + ": Could not extract sections from header"
		return -1
	endif
	
	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	WAVE W_Index
	
	String s = ""
	
	
	// ============================
	// Extract relevant header data
	// ============================
	
	String version = Header_GetVersion(fullheader, subGroupTitles)
	
	if (cmpstr(version, "") == 0)
		Print filename + ": Version info not found"
		return -1
	endif
	if (WhichListItem(version, ksVersionReq, ",") < 0)
		Print filename + ": File version not supported"
		return -1
	endif
		
	String filetype = Header_GetFiletype(fullheader, subGroupTitles)
	if (cmpstr(filetype, ksFileTypeFC) != 0)
		Print filename + ": Wrong file type"
		return -1
	endif
	
	Variable fcpoints = Header_GetNumPoints(fullheader, subGroupTitles)
	if (fcpoints != ksFCPoints)
		Print filename + ": Wrong number of data points per curve"
		return -1
	endif
	
	// returns NaN if didn't find x/y pos
	Variable xpos = Header_GetXPos(fullheader, subGroupTitles)
	Variable ypos = Header_GetYPos(fullheader, subGroupTitles)
	if (numtype(xpos) == 2 || numtype(ypos) == 2)
		Print filename + ": Didn't find X or Y position"
		return -1
	endif
	headerData += "xpos:" + num2str(xpos) + ";ypos:" + num2str(ypos) + ";"
	
	
	// Deflection Error data
	Variable index = Header_FindDataType(fullheader, subGroupTitles, "DeflectionError")
	if (index < 0)
		Print filename + ": Didn't find Deflection Error data"
		return -1
	endif
	
	Variable offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
	if (offs <= 0)
		Print filename + ": Deflection Error: Data offset invalid"
		return -1
	endif
	headerData += "dataOffset:" + num2str(offs) + ";"
	
	Variable rampSize = Header_GetRampSize(fullheader, subGroupTitles, index)
	if (rampSize <= 0)
		Print filename + ": Deflection Error: Ramp Size invalid"
		return -1
	endif
	headerData += "rampSize:" + num2str(rampSize) + ";"
	
	Variable springConst = Header_GetSpringConst(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: Spring Constant invalid"
		return -1
	endif
	headerData += "springConst:" + num2str(springConst) + ";"
	
	Variable VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: V/LSB scale invalid"
		return -1
	endif
	headerData += "VPerLSB:" + num2str(VPerLSB) + ";"
	
	Variable sens = Header_GetSens(fullheader, subGroupTitles, "DeflSens")
	if (sens <= 0)
		Print filename + ": Deflection Error: Deflection sensitivity invalid"
		return -1
	endif
	headerData += "deflSens:" + num2str(sens) + ";"
	
	
	NVAR loadzsens = :internalvars:loadZSens	
	if (loadzsens)
		// Z sensor channel
		index = Header_FindDataType(fullheader, subGroupTitles, "ZSensor")
		if (index < 0)
			Print filename + ": Didn't find ZSensor data"
			return -1
		endif
		
		offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
		if (offs <= 0)
			Print filename + ": ZSensor: Data offset invalid"
			return -1
		endif
		headerData += "ZdataOffset:" + num2str(offs) + ";"
		
		VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
		if (springConst <= 0)
			Print filename + ": ZSensor: V/LSB scale invalid"
			return -1
		endif
		headerData += "ZVPerLSB:" + num2str(VPerLSB) + ";"
		
		sens = Header_GetSens(fullheader, subGroupTitles, "ZsensSens")
		if (sens <= 0)
			Print filename + ": ZSensor: Deflection sensitivity invalid"
			return -1
		endif
		headerData += "ZSens:" + num2str(sens) + ";"
	endif
	
	
	NVAR loadfric = :internalvars:loadFriction	
	if (loadfric)
		// Friction channel
		index = Header_FindDataType(fullheader, subGroupTitles, "Lateral")
		if (index < 0)
			Print filename + ": Didn't find Friction data"
			return -1
		endif
		
		offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
		if (offs <= 0)
			Print filename + ": Friction: Data offset invalid"
			return -1
		endif
		headerData += "FricDataOffset:" + num2str(offs) + ";"
		
		VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
		if (springConst <= 0)
			Print filename + ": Friction: V/LSB scale invalid"
			return -1
		endif
		headerData += "FricVPerLSB:" + num2str(VPerLSB) + ";"
		
		// don't read friction sensitivity, because usually is not calibrated
	endif
	
		
	return 0
End


// Read and parse FC file given by fileName
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
Function ParseFVHeader(fileName, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result, subGroupOffset
	headerData = ""
	
	
	result = ReadHeaderLines(fileName, headerwave)
	if (result != 0)
		Print fileName + ": Did not find header end"
		return -1
	endif
	
	result = GetHeaderSectionTitles(headerwave, titleswave)
	if (result != 0)
		print fileName + ": Could not extract sections from header"
		return -1
	endif
	
	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	WAVE W_Index
	
	// ============================
	// Extract relevant header data
	// ============================
	
	String version = Header_GetVersion(fullheader, subGroupTitles)
	
	if (cmpstr(version, "") == 0)
		Print filename + ": Version info not found"
		return -1
	endif
	if (WhichListItem(version, ksVersionReq, ",") < 0)
		Print filename + ": File version not supported"
		return -1
	endif
	
	String filetype = Header_GetFiletype(fullheader, subGroupTitles)
	if (cmpstr(filetype, ksFileTypeFV) != 0)
		Print filename + ": Wrong file type"
		return -1
	endif
	
	Variable fcpoints = Header_GetNumPoints(fullheader, subGroupTitles)
	if (fcpoints != ksFCPoints)
		Print filename + ": Wrong number of data points per curve"
		return -1
	endif
	
	// Deflection Error channel
	Variable index = Header_FindDataType(fullheader, subGroupTitles, "DeflectionError")
	if (index < 0)
		Print filename + ": Didn't find Deflection Error data"
		return -1
	endif
	
	Variable offs = Header_GetDataOffset(fullheader, subGroupTitles, index)
	if (offs <= 0)
		Print filename + ": Deflection Error: Data offset invalid"
		return -1
	endif
	headerData += "dataOffset:" + num2str(offs) + ";"
	
	Variable rampSize = Header_GetRampSize(fullheader, subGroupTitles, index)
	if (rampSize <= 0)
		Print filename + ": Deflection Error: Ramp size invalid"
		return -1
	endif
	headerData += "rampSize:" + num2str(rampSize) + ";"
	
	Variable springConst = Header_GetSpringConst(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: Spring constant invalid"
		return -1
	endif
	headerData += "springConst:" + num2str(springConst) + ";"
	
	Variable VPerLSB = Header_GetLSBScale(fullheader, subGroupTitles, index)
	if (springConst <= 0)
		Print filename + ": Deflection Error: V/LSB scale invalid"
		return -1
	endif
	headerData += "VPerLSB:" + num2str(VPerLSB) + ";"
	
	Variable sens = Header_GetSens(fullheader, subGroupTitles, "DeflSens")
	if (sens <= 0)
		Print filename + ": Deflection Error: Deflection sensitivity invalid"
		return -1
	endif
	headerData += "deflSens:" + num2str(sens) + ";"
	
	return 0
End


// Parses image header and stores values in headerData string (pass by ref)
// headerData content:
// offset1,length1,bytes1,scale1;offset2,length2,bytes2,scale2;...
// offset: start of image in bytes
// length: length of image data in bytes
// bytes: bytes per pixel
// scale: nm/LSB (least significant bit), height scale of image
//
// If one image could not be parsed, headerData will just have "-" in it's place
//
// Returns number of successfully parsed images within the file
Function ParseImageHeader(fileName, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result
	headerData = ""

	Variable success = 0
	
	result = ReadHeaderLines(fileName, headerwave)
	if (result != 0)
		Print fileName + ": Did not find header end"
		return success
	endif
	
	result = GetHeaderSectionTitles(headerwave, titleswave)
	if (result != 0)
		print fileName + ": Could not extract sections from header"
		return success
	endif
	
	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	WAVE W_Index
	
	Variable subGroupOffset
	String s
	
	// Get Z piezo sensitivity (only 1 value per file)
	FindValue/TEXT="\\*Scanner list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		Print filename + ": \\*Scanner list not found"
		return success
	endif
	subGroupOffset = W_Index[V_value]
	
	FindValue/S=(subGroupOffset)/TEXT="\\@Sens. Zsens:" fullHeader
	if (V_value < 0)
		Print filename + ": Z piezo sens. not found"
		return success
	endif
	SplitString/E=":\\sV\\s(.+)\\snm/V$" fullHeader[V_value], s
	if (strlen(s) == 0)
		Print filename + ": Z piezo sens. invalid"
		return success
	endif
	
	Variable zsens = str2num(s)

	Variable start = 0
	Variable num = 0

	String currentHeader
	Variable bpp
	
	// Loop over image sections in file
	do
		if (start >= numpnts(subGroupTitles))
			// Reached end of header
			break
		endif
		
		// Find image section
		FindValue/S=(start)/TEXT="\\*Ciao image list"/TXOP=4 subGroupTitles
		if (V_value < 0)
			// No more images in this file
			break
		endif
	
		start = V_value + 1
		subGroupOffset = W_Index[V_value]
		
		// Get data offset
		FindValue/S=(subGroupOffset)/TEXT="\\Data offset:" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Data offset not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E=":\\s(.+)$" fullHeader[V_value], s
		if (str2num(s) <= 0)
			Print filename + ": Data offset <= 0 for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		currentHeader = s + ","
		
		
		// Get data length
		FindValue/S=(subGroupOffset)/TEXT="\\Data length:" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Data length not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E=":\\s(.+)$" fullHeader[V_value], s
		if (str2num(s) <= 0)
			Print filename + ": Data length <= 0 for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		currentHeader += s + ","
		
		
		// Get bytes per pixel
		FindValue/S=(subGroupOffset)/TEXT="\\Bytes/pixel:" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Bytes/pixel not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E=":\\s(.+)$" fullHeader[V_value], s
		if (str2num(s) <= 0)
			Print filename + ": Bytes/pixel <= 0 for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		bpp = str2num(s)
		currentHeader += s + ","
		
		
		// Get height scale
		FindValue/S=(subGroupOffset)/TEXT="\\@2:Z scale: V [Sens. Zsens]" fullHeader
		if ((V_value < 0) || ((start < numpnts(W_Index)) && (V_value >= W_Index[start])))
			Print filename + ": Z scale not found for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		SplitString/E="\\)\\s(.+)\\sV$" fullHeader[V_value], s
		//SplitString/E="\\((.+)\\sV/LSB\\)" fullHeader[V_value], s
		if (strlen(s) == 0)
			Print filename + ": Z scale invalid for image " + num2str(num)
			headerData += "-;"
			continue
		endif
		currentHeader += num2str(zsens*str2num(s)/(2^(bpp*8)))
		
		headerData += currentHeader + ";"
		success += 1
		
		num += 1
		
	while (1)
	
	return success

End

// Read file given by fileName.
// Add all lines into a new text wave
// return 0 if end of header found (defined by ksHeaderEnd)
// -1 otherwise.
// Last line of header not included in header wave.
Function ReadHeaderLines(filename, headerwave)
	String filename			// Full Igor-style path to filename ("folder:to:file.ext")
	String headerwave		// Name of the text wave for header data (will be overwritten)
	
	Variable maxlength = 100000		// max length of file to read in bytes
	
	Variable result = -1			// Set to 0 if end of header found
	
	if (strlen(fileName) == 0)
		return -1
	endif
	
	Variable refNum
	Open/R refNum as fileName				
	if (refNum == 0)	
		return -1						// Error
	endif

	Make/T/O/N=0 $headerwave		// Make new text wave, overwrite old if needed
	WAVE/T fullheader=$headerwave
	
	Variable len = 0
	String buffer = ""
	Variable line = 0
	Variable totlength = 0
	
	do
		FReadLine/N=1000 refNum, buffer
		
		len = strlen(buffer)
		if (len == 0)
			break										// No more lines to be read
		endif
		
		if (cmpstr(buffer[0,len-2], ksHeaderEnd) == 0)
			result = 0								// End of header reached
			break
		endif
		
		totlength += len
		if (totlength > maxlength)
			break
		endif
		
		Redimension/N=(line+1) fullheader		// Add one more row to wave
		fullheader[line] = buffer[0,len-2]		// Add line to wave, omit trailing CR char

		line += 1
	while (1)

	Close refNum
	return result
End


Function FlagCurves()
	
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	NVAR numcurves = :internalvars:numCurves
	// Create wave for flagged pixels; 0 or NaN = not flagged; 1 = flagged
	Make/O/N=(numcurves) flaggedcurves=0
	
	// Ask for flagging criteria (to be implemented)
	Variable deflsenspct = 5
	Variable negbheight = 1
	Variable bheightoutlier = 3
	Prompt deflsenspct, "Difference between calculated and saved deflection sensitivity (in %) [0 = off]"
	Prompt negbheight, "Negative brush height [1 = on, 0 = off]"
	Prompt bheightoutlier, "Outliers in brush height (in standard deviations) [0 = off]"
	DoPrompt "Flag curves", deflsenspct, negbheight, bheightoutlier
	
	if (V_flag == 1)
		// Cancel clicked
		return -1
	endif
	
	Variable flagged_deflsenspct = 0
	Variable flagged_negbheight = 0
	Variable flagged_bheightoutlier = 0
	if (deflsenspct > 0)
		flagged_deflsenspct = FlagCurves_deflsenspct("flaggedcurves", deflsenspct)
	endif
	if (negbheight == 1)
		flagged_negbheight = FlagCurves_negbheight("flaggedcurves")
	endif
	if (bheightoutlier > 0)
		flagged_bheightoutlier = FlagCurves_bheightoutlier("flaggedcurves", bheightoutlier)
	endif
	
	Print "Flagged:"
	Print "Deflection sensitivity diff (" + num2str(deflsenspct) + "%): " + num2str(flagged_deflsenspct)
	Print "Negative brush height (" + num2str(negbheight) + "): " + num2str(flagged_negbheight)
	Print "Brush height outliers (" + num2str(bheightoutlier) + " SD): " + num2str(flagged_bheightoutlier)
End


// Flag curves where the calculated deflection sensitivity differs
// from the one in metadata by more than 'pct' percent.
// Returns: number of flagged waves.
Function FlagCurves_deflsenspct(flagged, pct)
	String flagged	// Wave name to put flagged pixels into (must exist)
	Variable pct		// Percentage difference above which the curves are flagged
	
	WAVE flaggedW = $flagged
	
	NVAR numcurves = :internalvars:numCurves
	
	SVAR selectionwave = :internalvars:selectionwave
	WAVE sel = $selectionwave
	WAVE/T fcmeta
	
	Variable deflmeta, deflcalc, pctdiff
	
	Variable i
	Variable numflagged = 0
	for (i=0; i < numcurves; i+=1)
		if (sel[i])
			deflmeta = NumberByKey("deflSens", fcmeta[i])
			deflcalc = NumberByKey("deflSensFit", fcmeta[i])
			pctdiff = 100*abs(1-(deflmeta / deflcalc))
			if (pctdiff > pct)
				flaggedW[i] = 1
				numflagged += 1
			endif
		endif
	endfor
	
	return numflagged
End

// Flag curves with negative brush heights
// Returns: number of flagged waves.
Function FlagCurves_negbheight(flagged)
	String flagged	// Wave name to put flagged pixels into (must exist)
	
	WAVE flaggedW = $flagged
	
	NVAR numcurves = :internalvars:numCurves
	
	SVAR selectionwave = :internalvars:selectionwave
	WAVE sel = $selectionwave
	WAVE brushheights
	
	Variable i
	Variable numflagged = 0
	for (i=0; i < numcurves; i+=1)
		if (sel[i])
			if (brushheights[i] < 0)
				flaggedW[i] = 1
				numflagged += 1
			endif
		endif
	endfor
	
	return numflagged
End

// Flag curves with brush heights which differ from the mean
// by the specified amount or more (given in standard deviations)
// Returns: number of flagged waves.
Function FlagCurves_bheightoutlier(flagged, sd)
	String flagged	// Wave name to put flagged pixels into (must exist)
	Variable sd			// Factor of SD above which curves are flagged
	
	WAVE flaggedW = $flagged
	
	NVAR numcurves = :internalvars:numCurves
	
	SVAR selectionwave = :internalvars:selectionwave
	WAVE sel = $selectionwave
	WAVE brushheights
	
	WaveStats/Q brushheights
	
	Variable i
	Variable numflagged = 0
	for (i=0; i < numcurves; i+=1)
		if (sel[i])
			Variable diff = abs(brushheights[i] - V_avg)
			if (diff > sd*V_sdev)
				flaggedW[i] = 1
				numflagged += 1
			endif
		endif
	endfor
	
	return numflagged
End


Function ReviewCurvesAll()
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	NVAR numcurves = :internalvars:numCurves
	
	// Create accept and reject waves
	Make/N=(numcurves)/O heights_acc = NaN
	Make/N=(numcurves)/O heights_rej = NaN
	
	// Construct filter wave (all previously selected pixels)
	SVAR selectionwave = :internalvars:selectionwave
	WAVE sel = $selectionwave
	Make/N=(numcurves)/FREE filter = 0
	
	Variable i
	for (i=0; i < numcurves; i+=1)
		if (sel[i])
			filter[i] = 1
		endif
	endfor
	
	ReviewCurves("brushheights", "heights_acc", "heights_rej", filter)
End


Function ReviewCurvesFlagged()
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	NVAR numcurves = :internalvars:numCurves
	
	// Create accept and reject waves
	Make/N=(numcurves)/O heights_acc = NaN
	Make/N=(numcurves)/O heights_rej = NaN
	
	// Construct filter wave (selected pixels AND flagged pixels) [logical AND]
	SVAR selectionwave = :internalvars:selectionwave
	WAVE sel = $selectionwave
	WAVE fl = flaggedcurves
	WAVE heights = brushheights
	Make/N=(numcurves)/FREE filter = 0
	
	Variable i
	Variable autoacc = 0
	for (i=0; i < numcurves; i+=1)
		if (sel[i])
			// if flagged, put into review filter; otherwise automatically accept
			if (fl[i] == 1)
				filter[i] = 1
			else
				heights_acc[i] = heights[i]
				if (numtype(heights[i]) == 0)
					// normal number
					autoacc += 1
				endif
			endif
		endif
	endfor
	
	ReviewCurves("brushheights", "heights_acc", "heights_rej", filter)
	
	Print "(" + num2str(autoacc) + " curves automatically accepted)"
	
End


Function MarkFlaggedPixels()
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	NVAR numcurves = :internalvars:numCurves
	NVAR rowsize = :internalvars:FVRowSize
	SVAR imagegraph = :internalvars:imagegraph
	SVAR resultgraph = :internalvars:resultgraph
	WAVE fl = flaggedcurves
	Variable i
	Variable first = 1
	for (i=0; i < numcurves; i+=1)
		if (fl[i] == 1)
			Variable pixelX = mod(i,rowsize)
			Variable pixelY = floor(i/rowsize)
			if (first)
				DrawPointMarker(imagegraph, pixelX, pixelY, 1)
				DrawPointMarker(resultgraph, pixelX, pixelY, 1)
				first = 0
			else
				DrawPointMarker(imagegraph, pixelX, pixelY, 0)
				DrawPointMarker(resultgraph, pixelX, pixelY, 0)
			endif
		endif
	endfor
End


// Interactive review of force curves and curve fits
// Displays curves one by one and allows the user
// to accept or reject a given curve + fit.
// Accepted and rejected heights are copied to separate waves
//
// Input and output waves must exist.
// Output waves will not be deleted, but a value is overwritten once a curve at that position
// has been accepted or rejected.
//
// Filter wave defines which curves are being reviewed.
Function ReviewCurves(inputWname, accWname, rejWname, filter)
	String inputWname	// Input wave name of brush heights
	String accWname		// Output wave name of accepted brush heights
	String rejWname		// Output wave name of rejected brush heights
	WAVE filter			// Filter wave. Value 1 at index i means that this curve is reviewed,
							// otherwise not. Must be of same length as the input/output waves.
	
	WAVE inputw = $inputWname
	WAVE accw = $accWname
	WAVE rejw = $rejWname
	
	WAVE fc
	WAVE fc_x_tsd
	WAVE fc_expfit
	WAVE/T fcmeta
	
	SVAR imagegraph = :internalvars:imagegraph
	SVAR resultgraph = :internalvars:resultgraph
	
	NVAR rowsize = :internalvars:FVRowSize

	WaveStats/Q inputw
	Variable totalcurves = V_npnts
	Variable filtercurves = 0
	Variable wavesize = numpnts(inputw)
	Variable i
	for (i=0; i < wavesize; i+=1)
		if (filter[i]==1)
			filtercurves += 1
		endif
	endfor
	
	String header, shortHeader, numtext
	Variable curvesdone = 0
	
	// Create temporary data folder for the duration of the review
	NewDataFolder/O tmp_reviewDF
	
	// default zoom level 1
	// (0: autoscale; higher numbers increasing zoom; see PlotFC_setzoom)
	Variable/G :tmp_reviewDF:defzoom = 1
	
	Variable userabort = 0
	
	for (i=0; i < wavesize; i+=1)
		if (filter[i] == 1)			
			Variable pixelX = mod(i,rowsize)
			Variable pixelY = floor(i/rowsize)
			
			header = fcmeta[i]

			DoWindow/K tmp_reviewgraph
			PlotFC(i)
			DoWindow/C tmp_reviewgraph
			
			NVAR defzoom = :tmp_reviewDF:defzoom
			Variable/G :tmp_reviewDF:zoom = defzoom
			PlotFC_setzoom(defzoom)
			
			Variable/G :tmp_reviewDF:choice = 0
	
			// Create and show dialog window
			// with Accept/Reject etc. buttons
			// and some header data about current curve
			NewPanel/K=2 /W=(300,300,600,600) as "Accept or reject curve?"
			DoWindow/C tmp_reviewDialog
			AutoPositionWindow/E/M=0/R=tmp_reviewgraph
			
			shortHeader = "FCNum: " + num2str(i)
			shortHeader += "; X: " + num2str(pixelX) + "; Y: " + num2str(pixelY) + "\r"
			shortHeader += "BrushHeight: " + num2str(inputw[i]) + "\r"
			shortHeader += "DeflSens: " + num2str(NumberByKey("deflSens", header)) + " (saved)  "
			shortHeader += num2str(NumberByKey("deflSensFit", header)) + " (fit)"
			DrawText 20, 70, shortHeader
			
			Button accb,pos={30,120},size={100,40},title="Accept"
			Button accb,proc=ReviewCurves_Button			
			Button rejb,pos={135,120},size={100,40},title="Reject"
			Button rejb,proc=ReviewCurves_Button
			
			Button zoomb,pos={30,165},size={100,40},title="Zoom"
			Button zoomb,proc=ReviewCurves_Button
			Button unzoomb,pos={135,165},size={100,40},title="Unzoom"
			Button unzoomb,proc=ReviewCurves_Button
			PopupMenu defzoompop,pos={240,180},mode=(defzoom+1),value="0;1;2;3"
			PopupMenu defzoompop,proc=ReviewCurves_ChgDefzoom
						
			Button redob,pos={30,220},size={100,40},title="Redo last"
			Button redob,proc=ReviewCurves_Button
			
			Button stopb,pos={200,270},size={40,20},title="Stop"
			Button stopb,proc=ReviewCurves_Button

			if (curvesdone < 1)
				Button redob,disable=2
			endif
			
			numtext = num2str(curvesdone+1) + "/" + num2str(filtercurves)
			DrawText 200, 260, numtext
			
			DrawPointMarker(imagegraph, pixelX, pixelY, 1)
			DrawPointMarker(resultgraph, pixelX, pixelY, 1)
			
			// Wait for user interaction (ends when dialog window is killed)
			PauseForUser tmp_reviewDialog, tmp_reviewgraph
	
			// gChoice==1 for accepted, 2 for rejected
			NVAR gChoice = :tmp_reviewDF:choice
			Variable val = gChoice
			
			switch(val)
				case 1:
					// accepted
					accw[i] = inputw[i]
					rejw[i] = NaN
					break
				case 2:
					// rejected
					rejw[i] = inputw[i]
					accw[i] = NaN
					break
				case 3:
					// redo last
					Variable j
					for (j=i-1; j>=0; j-=1)
						if (filter[j] == 1)
							i = j-1
							curvesdone -= 2
							break
						endif
					endfor
					break
				case 4:
					// stop
					print "Review aborted by user, curve " + num2str(i) + " not reviewed"
					userabort = 1
					break
				default:
					print "User interaction error (neither accepted nor rejected curve " + num2str(i) + ")"
					userabort = 1
					break
			endswitch
			
			if (userabort)
				break
			endif
			
			curvesdone += 1
		endif
	endfor
	
	DoWindow/K tmp_reviewgraph
	KillDataFolder tmp_reviewDF
	
	WaveStats/Q accw
	Variable acctot = V_npnts
	WaveStats/Q rejw
	Variable rejtot = V_npnts
	Print "Reviewed " + num2str(curvesdone) + " out of " + num2str(totalcurves) + " total curves"
	Print "Total:  Accepted " + num2str(acctot) + ", rejected " + num2str(rejtot)
End

Function ReviewCurves_Button(ctrlName)
	String ctrlName

	NVAR zoom = :tmp_reviewDF:zoom
	
	strswitch (ctrlName)
		case "accb":
			Variable/G :tmp_reviewDF:choice = 1
			DoWindow/K tmp_reviewDialog			// Kill self
			break
		case "rejb":
			Variable/G :tmp_reviewDF:choice = 2
			DoWindow/K tmp_reviewDialog			// Kill self
			break
		case "redob":
			Variable/G :tmp_reviewDF:choice = 3
			DoWindow/K tmp_reviewDialog			// Kill self
			break
		case "zoomb":
			zoom += 1
			if (zoom > 3)
				zoom = 3
			endif
			PlotFC_setzoom(zoom)
			break
		case "unzoomb":
			zoom -= 1
			if (zoom < 0)
				zoom = 0
			endif
			PlotFC_setzoom(zoom)
			break
		case "stopb":
			Variable/G :tmp_reviewDF:choice = 4
			DoWindow/K tmp_reviewDialog
			break
	endswitch
End

Function ReviewCurves_ChgDefzoom(ctrlName, popnum, popstr)
	String ctrlName, popstr
	Variable popnum
	
	Variable/G :tmp_reviewDF:defzoom = popnum-1
End

// Ask user for settings and initialize environment
Function SetSettings(flags)
	// Flags is a bit field for settings
	// 1: setting set / yes
	// 0: setting unset / no
	//
	// bits:
	// 0: load friction data (SETTINGS_LOADFRIC)
	// 1: load zsensor data (SETTINGS_LOADZSENS)
	Variable flags

	if (CheckRoot() < 0)
		return -1
	endif
	
	if (!DataFolderExists("internalvars"))
		NewDataFolder internalvars
	endif
	
	Variable fric = NumVarOrDefault(":internalvars:loadFriction", flags & SETTINGS_LOADFRIC)
	Variable zsens = NumVarOrDefault(":internalvars:loadZSens", flags & SETTINGS_LOADZSENS)
	String list = "Yes;No;"
	
	String fricStr = SelectString(fric, "No", "Yes")
	String zsensStr = SelectString(zsens, "No", "Yes")
	
	Prompt fricStr, "Load Friction data?", popup, list
	Prompt zsensStr, "Load Z Sensor data?", popup, list
	DoPrompt "Set Settings", fricStr, zsensStr
	
	if (V_flag == 1)
		// User pressed cancel
		return -1
	endif
	
	Variable/G :internalvars:loadFriction = (cmpstr(fricStr, "Yes") == 0) ? 1 : 0
	Variable/G :internalvars:loadZSens = (cmpstr(zsensStr, "Yes") == 0) ? 1 : 0
	
End



Function ImageToForeground()
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	SVAR imagegraph = :internalvars:imagegraph
	DoWindow/F $imagegraph
End


Function MapToForeground()
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	SVAR resultgraph = :internalvars:resultgraph
	DoWindow/F $resultgraph
End


Function PrintInfo()
	SVAR ig = :internalvars:imagegraph
	SVAR iw = :internalvars:imagewave
	SVAR rg = :internalvars:resultgraph
	SVAR rw = :internalvars:resultwave
	SVAR sel = :internalvars:selectionwave
	SVAR path = :internalvars:totalpath
	SVAR params = :internalvars:analysisparameters
	printf "IMAGE graph: %s,  wave: %s\r", ig, iw
	printf "BRUSHHEIGHTS graph: %s,  wave: %s\r", rg, rw
	printf "selectionwave: %s,  totalpath: %s\r", sel, path
	printf "analysis parameters: %s\r", params
End

Function PrintInfoDF(df)
	String df		// data folder (without 'root:' part) to print info from
	String fullDF = "root:" + df
	String prevDF = GetDataFolder(1)
	SetDataFolder fulldf
	PrintInfo()
	SetDataFolder prevDF
End


// Return -1 if user is in root and does not want to continue; 0 otherwise
Function CheckRoot()
	String df = GetDataFolder(0)
	if (cmpstr(df, "root") == 0)
		DoAlert 1, "You are in root data folder, this is not recommended.\rContinue anyway?"
		if (V_flag == 2)
			return -1
		endif
	endif
	
	return 0
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



constant PROGWIN_BAR_HEIGHT=20
constant PROGWIN_BAR_WIDTH=250
constant PROGWIN_MAX_DEPTH=10
constant AUTO_CLOSE=1

Function ProgWinOpen([coords])
	wave coords
	
	dowindow ProgWin
	if(v_flag)
		dowindow /k/w=ProgWin ProgWin
	endif
	if(paramisdefault(coords))
		make /free/n=4 coords={100,100,200+PROGWIN_BAR_WIDTH,110+PROGWIN_BAR_HEIGHT}
	endif
	NewPanel /K=1 /N=ProgWin /W=(coords[0],coords[1],coords[2],coords[3]) /FLT=1 as "Progress"
	SetActiveSubwindow _endfloat_
	MoveWindow /W=ProgWin coords[0],coords[1],coords[2],coords[3]
	DoUpdate /W=ProgWin /E=1
	SetWindow ProgWin userData=""
	SetWindow ProgWin userData(abortName)=""
	if(AUTO_CLOSE)
		Execute /P/Q "dowindow /k/w=ProgWin ProgWin" // Automatic cleanup of progress window at the end of function execution.  
	endif
End

Function Prog(name,num,denom[,msg])
	String name,msg
	variable num,denom
	if(!wintype("ProgWin"))
		ProgWinOpen()
	endif
	string data=GetUserData("ProgWin","","")
	name=cleanupname(name,0)
	variable currDepth=itemsinlist(data)
	variable depth=whichlistitem(name,data)
	depth=(depth<0) ? currDepth : depth
	ControlInfo $("Prog_"+name)
	if(!V_flag)
		variable yy=10+(10+PROGWIN_BAR_HEIGHT)*depth
		ValDisplay $("Prog_"+name),pos={50,yy},size={PROGWIN_BAR_WIDTH,PROGWIN_BAR_HEIGHT},limits={0,1,0},barmisc={0,0}, mode=3, win=ProgWin
		TitleBox $("Status_"+name), pos={55+PROGWIN_BAR_WIDTH,yy},size={60,PROGWIN_BAR_HEIGHT}, win=ProgWin
		Button $("Abort_"+name), pos={4,yy}, size={40,20}, title=name, proc=ProgWinButtons, win=ProgWin
	endif
	variable frac=num/denom
	ValDisplay $("Prog_"+name),value=_NUM:frac, win=ProgWin, userData(num)=num2str(num), userData(denom)=num2str(denom)
	string message=num2str(num)+"/"+num2str(denom)
	if(!ParamIsDefault(msg))
		message+=" "+msg
	endif
	TitleBox $("Status_"+name), title=message, win=ProgWin
	if(depth==currDepth)
		struct rect coords
		GetWinCoords("ProgWin",coords,forcePixels=1)
		MoveWindow /W=ProgWin coords.left,coords.top,coords.right,coords.bottom+(10+PROGWIN_BAR_HEIGHT)*72/ScreenResolution
		SetWindow ProgWin userData=addlistitem(name,data,";",inf)
	endif
	DoUpdate /W=ProgWin /E=1
	string abortName=GetUserData("ProgWin","","abortName")
	if(stringmatch(name,abortName))
		SetWindow ProgWin userData(abortName)=""
		debuggeroptions
		if(v_enable)
			debugger
		else
			abort
		endif
	endif
End

Function ProgWinButtons(ctrlName)
	String ctrlName
	
	Variable button_num
	String action=StringFromList(0,ctrlName,"_")
	string name=ctrlName[strlen(action)+1,strlen(ctrlName)-1]	
	strswitch(action)
		case "Abort":
			SetWindow ProgWin userData(abortName)=name
	endswitch
End

static Function GetWinCoords(win,coords[,forcePixels])
	String win
	STRUCT rect &coords
	Variable forcePixels // Force values to be returned in pixels in cases where they would be returned in points.  
	Variable type=WinType(win)
	Variable factor=1
	if(type)
		GetWindow $win wsize;
		if(type==7 && forcePixels==0)
			factor=ScreenResolution/72
		endif
		//print V_left,factor,coords.left
		coords.left=V_left*factor
		coords.top=V_top*factor
		coords.right=V_right*factor
		coords.bottom=V_bottom*factor
	else
		print "No such window: "+win
	endif
End


// For debugging purposes
// Put debug snippets in this function to be able to run them
// from the console.
Function DebugTest()
	Variable tmpRet
	String tmpHd
	
	//tmpRet = ParseFCHeader("C:Users:Janne:Desktop:au-rings-afm:peg57:peg57-pbs-0.spm", tmpHd)
	Print "ret:" + num2str(tmpRet)
	Print tmpHd
End