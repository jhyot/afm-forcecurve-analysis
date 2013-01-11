#pragma rtGlobals=1		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc
#include <SaveGraph>
#include <Wave Loading>

#include ":analysis-code"
#include ":plotting-code"


// TODO
// LoadImage() or similar for quasi-height image
// retraction curve handling (make optional, variable names etc)
// Make multiple 2d arrays possible in same datafolder (keep track of wave names etc instead of hardcoding)
// Make button in heightimage and heightmap for inspect mode (i.e. be able to turn off inspect mode)


// **** USER CONFIGURABLE CONSTANTS ****
//
// Change constants to adjust procedure behaviour

// Allowed force map versions, comma separated
// (add versions once they have been tested)
StrConstant ksVersionReq = "0x07300000,0x08100000,0x08150300"

// Points per FC
// for now only works with 4096
Constant ksFCPoints = 4096

// Force curves per row.
// For now designed and tested only for square images with 32*32 = 1024 curves
Constant ksFVRowSize = 32

// FC file type as written in header
StrConstant ksFileType = "FVOL"

// String to be matched (full match, case insensitive) at header end
StrConstant ksHeaderEnd = "\\*File list end"

// Brush height calculation parameters
Constant ksBaselineFitLength = .3	// Fraction of points used for baseline fits
Constant ksBrushCutoff = 3	// height from force in exponential fit (in pN)
Constant ksBrushOverNoise = 1		// height from point on curve above noise multiplied by this factor
 

//
// **** END USER CONFIGURABLE CONSTANTS ****
//


// Create Igor Menu
Menu "Force Map Analysis"
	"Load File/1", LoadForceMap()
	"Choose Force Curves/2", ChooseForceCurves()
	"Do Analysis/3", Analysis()
	"Load and Analyse All FCs", LoadandAnalyseAll()
	"-"
	"Load Image", LoadImage()
	"Show Image", ImageToForeground()
	"Show Height Map", MapToForeground()
	"Review All Curves", ReviewCurvesMenu()
End


Function LoadandAnalyseAll()

	Variable result
	
	result = LoadForceMap()

	if (result<0)
		print "Aborted loading force map"
		return -1
	endif
	
	Variable i
	String/G headerstuff, selectedCurvesW = "selectedcurves"

	Make/O/N=(ksFVRowSize*ksFVRowsize) $selectedCurvesW = NaN


	Wave sel=$selectedCurvesW

	for(i=0;i<(ksFVRowSize*ksFVRowSize);i+=1)
		sel[i] = NumberByKey("dataOffset", headerstuff) + ksFCPoints*2*2*i
	endfor

	String/G totalpath


	ReadAllFCs(totalpath)


	Analysis()

End


// Displays dialog to select force map file and
// calls the function to load header and FV image.
// Saves filename to global string variable.
//
// Returns 0 if map loaded correctly, -1 otherwise.
// Also sets global variable isMapLoaded to 1.
Function LoadForceMap()

	String/G totalpath
	
	Variable/G isMapLoaded = 0

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
	
	totalpath = S_fileName
	
	result = ReadMap(totalpath)
	
	if (result < 0)
		print "Error reading FV map"
		return -1
	endif
	
	isMapLoaded = 1
	return 0
	
End



Function LoadImage()
	
	Variable/G isMapLoaded
	
	if (isMapLoaded != 1)
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
	
	String/G imagegraph
	SetWindow $imagegraph,hook(imageinspect)=inspector

	return 0
		
End


// Loads external image from a file (e.g. FV, image(s) only)
// and replaces quasi-height topo of the original FV file.
//
// Returns 0 on success, < 0 for error
Function LoadImageFromFile(filename, index, header)
	String filename
	Variable index
	String header
	
	//Offsets(a), lengths(b), bytes(c), scale(d) in header: "a0,b0,c0,d0;a1,b1,c1,d1;..."
	Variable offset = str2num(StringFromList(0, StringFromList(index,header), ","))
	Variable length = str2num(StringFromList(1, StringFromList(index,header), ","))
	Variable bpp = str2num(StringFromList(2, StringFromList(index,header), ","))
	Variable scale = str2num(StringFromList(3, StringFromList(index,header), ","))
	
	if (length/bpp != ksFVRowSize*ksFVRowSize)
		print filename + ": Size does not match FV data for image " + num2str(index)
		return -1
	endif
	
	GBLoadWave/Q/B/A=image/T={bpp*8,4}/S=(offset)/W=1/U=(length/bpp) filename
	
	if (V_flag < 1)
		print filename + ": Could not load image " + num2str(index)
		return -1
	endif

	String/G imagewave = StringFromList(0,S_waveNames)
	
	WAVE w = $imagewave
	
	w *= scale
	
	redimension/N=(ksFVRowSize,ksFVRowSize) $imagewave
	
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

	Variable result
	Variable index=0
	Variable totalWaves=ksFVRowSize*ksFVRowSize
	Variable success=0
	String headerData, image
	String/G imagewave, imagegraph
	
	
	// Read and parse FC file header
	result = ParseFCHeader(fileName, "fullHeader", "subGroupTitles", headerData)
	
	if (result < 0)
		print "Could not parse force volume header correctly"
		return -1
	endif
	
	String/G headerstuff=headerData
	
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
	Make/O/N=(ksFCPoints, totalWaves) fc=NaN, rfc=NaN
	Make/T/O/N=(totalWaves) fcmeta=""

	ShowImage()

End



Function ChooseForceCurves()

	string/G totalpath, selectedCurvesW = "selectedcurves"
	variable/G isMapLoaded
	if (isMapLoaded==1)
		Variable del = 1
		WAVE/Z sel = $selectedCurvesW
		if (WaveExists(sel) && (numpnts(sel) == ksFVRowSize*ksFVRowSize))
			WaveStats/Q sel
			if (V_npnts > 0)
				// Some pixels were previously already selected. Keep?
				DoAlert 1, "Keep previous selection?"
				if (V_flag == 1)
					del = 0
				endif
			endif
		endif
		
		if (del == 1)
			Make/N=(ksFVRowSize*ksFVRowSize)/O $selectedCurvesW = NaN
			
			// Delete markers from image graph if exists
			String/G imagegraph
			DoWindow $imagegraph
			if (V_flag > 0)
				DrawAction/W=$imagegraph delete
			endif
		endif
			
		ChooseFVs()
	else
		print "Load Force Map via \"Force Map Analysis\"->\"Load File\" first!"
		return 1
	endif
End



Function ChooseFVs()
	string/G imagegraph
	PauseUpdate; Silent 1		// building window...
	NewPanel/N=Dialog/W=(225,105,525,305) as "Dialog"
	AutoPositionWindow/M=0/R=$imagegraph
	Button done,pos={119,150},size={50,20},title="Done"
	Button done,proc=DialogDoneButtonProc
	Button sall, pos={119,100},size={50,20},title="All"
	Button sall,proc=selectall
	
	DoWindow/F $imagegraph
	SetWindow kwTopWin,hook(choose)= chooser
End


Function selectall(sall) : ButtonControl
	String sall
	variable i
	String/G headerstuff, selectedCurvesW

	wave sel=$selectedCurvesW

	for(i=0;i<(ksFVRowsize*ksFVRowSize);i+=1)
		sel[i]=NumberByKey("dataOffset", headerstuff)+ksFCPoints*2*2*i
	endfor
End



Function chooser(s)
	STRUCT WMWinHookStruct &s
	Variable rval = 0
	string/G imagegraph, selectedCurvesW
	String/G headerstuff

	// React only on left mousedown
	if ((s.eventCode == 3) && (s.eventMod & 1 != 0))
		Variable mouseY = s.mouseLoc.v
		Variable mouseX = s.mouseLoc.h

		// Get image pixel and force curve number
		Variable pixelY = round(axisvalfrompixel(imagegraph, "left", mouseY-s.winrect.top))
		Variable pixelX = round(axisvalfrompixel(imagegraph, "bottom", mouseX-s.winrect.left))
		Variable fcnum = pixelX+(pixelY*ksFVRowSize)

		if(pixelX >= 0 && pixelX <= (ksFVRowSize-1) && pixelY >= 0 && pixelY <= (ksFVRowSize-1))
			// Draw marker on top of pixel
			SetDrawEnv xcoord=prel, ycoord=prel, linethick=0, fillfgc=(65280,0,0)
			DrawRect pixelX/ksFVRowSize+0.3/ksFVRowSize, 1-pixelY/ksFVRowSize-0.3/ksFVRowSize,  pixelX/ksFVRowSize+0.7/ksFVRowSize, 1-pixelY/ksFVRowSize-0.7/ksFVRowSize
			
			// Write selected fc offset to selection wave
			Variable offs = NumberByKey("dataOffset", headerstuff)+ksFCPoints*2*fcnum*2
			WAVE sel=$selectedCurvesW
			
			sel[fcnum] = offs
			print "X: " + num2str(pixelX) + "; Y: " + num2str(pixelY) + "; FC: ", num2str(fcnum)
		endif

		rval = 1
	endif

	return rval

End




Function DialogDoneButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	
	string/G imagegraph, totalpath

	switch( ba.eventCode )
		case 2:									// mouse up
			// turn off the chooser hook
			SetWindow $imagegraph,hook(choose)= $""
			// kill the window AFTER this routine returns
			Execute/P/Q/Z "DoWindow/K "+ba.win
			ReadAllFCs(totalpath)
	endswitch

	return 0
End



Function ReadAllFCs(fileName)
	String fileName			// Igor-style path: e.g. "X:Code:igor-analyse-forcecurves:test-files:pegylated_glass.004"
	
	Variable result
	Variable index=0
	Variable totalWaves=ksFVRowSize*ksFVRowSize
	Variable success=0
	String/G headerstuff, imagegraph, selectedCurvesW

	
	DoWindow/F $imagegraph	// Bring graph to front
	if (V_Flag == 0)			// Verify that graph exists
		Abort "UserCursorAdjust: No such graph."
		return -1
	endif
	
	variable t0=ticks
	
	WAVE dataOffsets=$selectedCurvesW
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
				
				fcmeta[index] = headerstuff
				// Increment number of successfully read files
				success += 1
			else
				Print "Did not find approach + retract curves at position " + num2str(index)
			endif
		endif

		index += 1
		
		Prog("ReadWaves",index,totalWaves)
		
	while (index<totalWaves)
	
	printf "Elapsed time: %g seconds\r",round(10*(ticks-t0)/60)/10

	// Create 2 waves
	// One holds file and wave names, the other the corresponding brush heights
	// Value will be filled in AnalyseBrushHeight
	// Old waves will be overwritten
	// (same for retractfeature)
	Make/T/O/N=(totalWaves, 2) brushheight_names = {"", ""}
	Make/O/N=(totalWaves) brushheights = NaN
	Make/O/N=(totalWaves) retractfeature = NaN
	
	KillWaves/Z fcload0, fcload1

	return success	
End





Function rinspector(s)			//retractfeature
	STRUCT WMWinHookStruct &s
	Variable rval= 0
	variable mouseloc,xval,yval, xbla,ybla
	string/G selectedCurvesW


	switch(s.eventCode)
		case 3:
			yval=s.mouseLoc.v
			xval=s.mouseLoc.h


			ybla=round(axisvalfrompixel("retractfeaturesdetection","left",yval-s.winrect.top))
			xbla=round(axisvalfrompixel("retractfeaturesdetection","bottom",xval-s.winrect.left))


			wave sel=$selectedCurvesW


			if(xbla>=0 && xbla<=(ksFVRowSize-1) && ybla>=0 && ybla<=(ksFVRowSize-1) && sel[xbla+(ybla*ksFVRowSize)])

				rplot2(abs(xbla+(ybla*ksFVRowSize)))


				print "FCNumber:",xbla+(ybla*ksFVRowSize)
				print "X:",xbla,"Y:",ybla
				//print "Brushheight for selection:",brushheights[xbla+(ybla*ksFVRowSize)],"nm"

			else

				print "No Data here!"

			endif

	EndSwitch

	return rval

End



Function inspector(s)			//heightsmap
	STRUCT WMWinHookStruct &s
	Variable rval= 0
	variable mouseloc,xval,yval, xbla,ybla
	string/G selectedCurvesW


	switch(s.eventCode)
		case 3:
			yval=s.mouseLoc.v
			xval=s.mouseLoc.h


			ybla=round(axisvalfrompixel("results","left",yval-s.winrect.top))
			xbla=round(axisvalfrompixel("results","bottom",xval-s.winrect.left))


			wave sel=$selectedCurvesW
			wave brushheights


			if(xbla>=0 && xbla<=(ksFVRowSize-1) && ybla>=0 && ybla<=(ksFVRowSize-1) && sel[xbla+(ybla*ksFVRowSize)])

				plot2(abs(xbla+(ybla*ksFVRowSize)))

				print "FCNumber:",xbla+(ybla*ksFVRowSize)
				print "X:",xbla,"Y:",ybla
				print "Brushheight for selection:",brushheights[xbla+(ybla*ksFVRowSize)],"nm"
			else
				print "No Data here!"
			endif
	EndSwitch

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
	
	Make/T/O/N=0 $titleswave

	WAVE/T fullHeader = $headerwave
	WAVE/T subGroupTitles = $titleswave
	
	// Find indices of header subgroups (e.g. "\*Ciao scan list")
	// in fullHeader (created by ReadFCHeaderLines)
	Grep/INDX/E="^\\\\\\*.+$" fullHeader as subGroupTitles
	if (V_flag != 0)
		return -1			// Error
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
Function ParseFCHeader(fileName, headerwave, titleswave, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String headerwave		// Name of the text wave where full header will be saved to (will be overwritten)
	String titleswave		// Name of the text wave where the section titles will be written to (will be overwritten)
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result, subGroupOffset
	headerData = ""
	
	
	result = ReadFCHeaderLines(fileName, headerwave)
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
	
	FindValue/TEXT="\\*Force file list"/TXOP=4 subGroupTitles		// case insensitive full wave element search
	if (V_value < 0)
		Print filename + ": \\*Force file list not found"
		return -1
	endif
	subGroupOffset = W_Index[V_value]
	
	// Check if correct version and filetype
	String s
	FindValue/S=(subGroupOffset)/TEXT="\\Version:" fullheader
	if (V_value < 0)
		Print filename + ": Version not found"
		return -1
	endif
	SplitString/E=":\\s(.+)$" fullHeader[V_value], s
	if (WhichListItem(s, ksVersionReq, ",") < 0)
		Print filename + ": File version not supported"
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
	
	
	// Check if correct number of points
	FindValue/TEXT="\\*Ciao force image list"/TXOP=4 subGroupTitles
	if (V_value < 0)
		Print filename + ": \\*Ciao force image list not found"
		return -1
	endif
	subGroupOffset = W_Index[V_value]
	
	// Get data offset
	FindValue/S=(subGroupOffset)/TEXT="\Data offset:" fullHeader
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
	
	FindValue/S=(subGroupOffset)/TEXT="\\Samps/line:" fullHeader
	if (V_value < 0)
		Print filename + ":Data points number not found"
		return -1
	endif
	SplitString/E=":\\s(\\d+)\\s\\d+$" fullHeader[V_value], s
	if (str2num(s) != ksFCPoints)
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
	FindValue/S=(subGroupOffset)/TEXT="\\@4:Z scale: V" fullHeader
	if (V_value < 0)
		Print filename + ": Z scale not found"
		return -1
	endif
	String s2
	SplitString/E="\\[(.+)\\]\\s\\((.+)\\sV/LSB\\)" fullHeader[V_value], s2, s
	if (cmpstr(s2, "Sens. DeflSens") != 0)
		Print filename + ": FC data is not vertical deflection (" + s2 + ")"
		return -1
	endif
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
	
	result = ReadFCHeaderLines(fileName, headerwave)
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

// Read FC file given by fileName.
// Add all lines into a new text wave
// return 0 if end of header found (defined by ksHeaderEnd)
// -1 otherwise.
// Last line of header not included in header wave.
Function ReadFCHeaderLines(filename, headerwave)
	String filename			// Full Igor-style path to filename ("folder:to:file.ext")
	String headerwave		// Name of the text wave for header data (will be overwritten)
	
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
	
	Variable len
	String buffer
	Variable line = 0
	
	do
		FReadLine refNum, buffer
		
		len = strlen(buffer)
		if (len == 0)
			break										// No more lines to be read
		endif
		
		if (cmpstr(buffer[0,len-2], ksHeaderEnd) == 0)
			result = 0								// End of header reached
			break
		endif
		
		Redimension/N=(line+1) fullheader		// Add one more row to wave
		fullheader[line] = buffer[0,len-2]		// Add line to wave, omit trailing CR char

		line += 1
	while (1)

	Close refNum
	return result
End


Function ReviewCurvesMenu()
	Variable/G isMapLoaded
	
	if (isMapLoaded != 1)
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	Variable totalwaves = ksFVRowSize * ksFVRowSize
	
	// Create accept and reject waves
	Make/N=(totalWaves)/O heights_acc = NaN
	Make/N=(totalWaves)/O heights_rej = NaN
	
	ReviewCurves("brushheights", "heights_acc", "heights_rej")
End


// Interactive review of force curves and curve fits
// Displays curves one by one and allows the user
// to accept or reject a given curve + fit.
// Accepted and rejected heights are copied to separate waves
//
// Input and output waves must exist.
// Output waves will not be deleted, but a value is overwritten once a curve at that position
// has been accepted or rejected.
Function ReviewCurves(inputWname, accWname, rejWname)
	String inputWname	// input wave of brush heights
	String accWname		// output wave of accepted brush heights
	String rejWname		// output wave of rejected brush heights
	
	String/G selectedCurvesW
	
	WAVE inputw = $inputWname
	WAVE accw = $accWname
	WAVE rejw = $rejWname
	
	WAVE fc
	WAVE fc_x_tsd
	WAVE fc_expfit
	WAVE/T fcmeta
	
	WAVE sel = $selectedCurvesW

	Variable totalall = numpnts(inputw)
	Variable totalsel = 0
		
	Variable i
	
	// count how many points were selected
	for (i=0; i < totalall; i+=1)
		if (sel[i])
			totalsel += 1
		endif
	endfor
	
	String header, shortHeader, numtext
	Variable curvesdone = 0
	
	// Create temporary data folder for the duration of the review
	NewDataFolder/O tmp_reviewDF
	
	// default zoom level 1 (0: autoscale; 1,2 increasing zoom)
	Variable/G :tmp_reviewDF:defzoom = 1
	
	for (i=0; i < totalall; i+=1)
		if (sel[i])
			curvesdone += 1
			
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
			shortHeader += "; X: " + num2str(mod(i,ksFVRowSize)) + "; Y: " + num2str(floor(i/ksFVRowSize)) + "\r"
			shortHeader += "FitStart: " + StringByKey("expFitStartPt", header) + "\r"
			shortHeader += "FitEnd: " + StringByKey("expFitEndPt", header) + "\r"
			shortHeader += "FitTau: " + StringByKey("expFitTau", header) + "\r"
			shortHeader += "FitBL: " + StringByKey("expFitBL", header) + "\r"
			shortHeader += "BrushHeight: " + num2str(inputw[i])
			DrawText 20, 100, shortHeader
			
			Button accb,pos={30,120},size={100,40},title="Accept"
			Button accb,proc=ReviewCurves_Button			
			Button rejb,pos={135,120},size={100,40},title="Reject"
			Button rejb,proc=ReviewCurves_Button
			
			Button zoomb,pos={30,165},size={100,40},title="Zoom"
			Button zoomb,proc=ReviewCurves_Button
			Button unzoomb,pos={135,165},size={100,40},title="Unzoom"
			Button unzoomb,proc=ReviewCurves_Button
			PopupMenu defzoompop,pos={240,180},mode=(defzoom+1),value="0;1;2;"
			PopupMenu defzoompop,proc=ReviewCurves_ChgDefzoom
						
			Button redob,pos={30,220},size={100,40},title="Redo last"
			Button redob,proc=ReviewCurves_Button

			if (curvesdone <= 1)
				Button redob,disable=2
			endif
			
			numtext = num2str(curvesdone) + "/" + num2str(totalsel)
			DrawText 200, 260, numtext
			
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
						if (sel[j])
							i = j-1
							curvesdone -= 2
							break
						endif
					endfor
					break
				default:
					print "User interaction error (neither accepted nor rejected curve " + num2str(i) + ")"
					break
			endswitch
		endif
	endfor
	
	DoWindow/K tmp_reviewgraph
	KillDataFolder tmp_reviewDF
	
	WaveStats/Q accw
	Variable acc = V_npnts
	WaveStats/Q rejw
	Variable rej = V_npnts
	Print "Reviewed " + num2str(totalsel) + " selected out of " + num2str(totalall) + " total curves"
	Print "Accepted " + num2str(acc) + "/" + num2str(totalsel) + "; rejected " + num2str(rej) + "/" + num2str(totalsel)	
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
			zoom = (zoom==0 ? 1 : 2)
			PlotFC_setzoom(zoom)
			break
		case "unzoomb":
			zoom = 0
			PlotFC_setzoom(zoom)
			break
	endswitch
End

Function ReviewCurves_ChgDefzoom(ctrlName, popnum, popstr)
	String ctrlName, popstr
	Variable popnum
	
	Variable/G :tmp_reviewDF:defzoom = popnum-1
End





Function ImageToForeground()
	String/G imagegraph
	DoWindow/F $imagegraph
End


Function MapToForeground()
	String/G resultgraph
	DoWindow/F $resultgraph
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