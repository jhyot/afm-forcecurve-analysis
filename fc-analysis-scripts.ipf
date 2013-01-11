#pragma rtGlobals=1		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc
#include <SaveGraph>
#include <Wave Loading>

#include ":analysis-code"
#include ":plotting-code"


// TODO
// Code style
// Quasi-height image, load byte offset from header
// rewrite(style, variable names) chooser, inspector and rinspector functions (possibly refactor)
// retraction curve handling (make optional, variable names etc)
// general variable names ("bla", "temp" etc)
// use free waves (when temp waves needed)
// Make multiple 2d arrays possible in same datafolder (keep track of wave names etc instead of hardcoding)


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
	"Load Image", LoadImage()
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
// Also kills previous force volume related files in current data folder.
//
// Returns 0 if no errors, -1 otherwise
Function ReadMap(fileName)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")

	Variable result
	Variable index=0
	Variable totalWaves=ksFVRowSize*ksFVRowSize
	Variable success=0
	String headerData, image
	String/G imagewave, imagename
	

	// IMPORTANT: will delete all previous waves in the current data folder starting with "fc"
	// Make sure that the waves are not in use anymore (i.e. close graphs etc.)
	KillPreviousWaves()
	
	// Read and parse FC file header
	result = ParseFCHeader(fileName, headerData)
	
	if (result < 0)
		print "Could not parse header correctly"
		return -1
	endif
	
	String/G headerstuff=headerData

	GBLoadWave/Q/B/N=image/T={16,4}/S=(NumberByKey("dataOffset", headerData)-2*totalWaves)/W=1/U=(totalWaves) fileName
	
	if (V_flag < 1)
		print "Could not load force volume image data"
		return -1
	endif

	imagewave = StringFromList(0,S_waveNames)
	redimension/N=(ksFVRowSize,ksFVRowSize) $imagewave

	// Create waves for holding the curves (2d array, 1 column per curve)
	// and for metadata about each curve (1 row per curve)
	Make/O/N=(ksFCPoints, totalWaves) fc=NaN, rfc=NaN
	Make/T/O/N=(totalWaves) fcmeta=""

	Display/W=(29.25,55.25,450.75,458)
	AppendImage $imagewave

	imagename=S_name

	ModifyImage $imagewave ctab={*,*,Gold,0}

	DoUpdate

End



Function ChooseForceCurves()

	string/G totalpath, selectedCurvesW = "selectedcurves"
	variable/G isMapLoaded
	if (isMapLoaded==1)
		if(waveexists($selectedCurvesW))
			KillWaves $selectedCurvesW
		endif
		
		Make/N=(ksFVRowSize*ksFVRowSize)/O $selectedCurvesW
			
		ChooseFVs()
	else
		print "Load Force Map via \"Force Map Analysis\"->\"Load File\" first!"
		return 1
	endif
End



Function ChooseFVs()
	string/G imagename
	PauseUpdate; Silent 1		// building window...
	NewPanel/N=Dialog/W=(225,105,525,305) as "Dialog"
	AutoPositionWindow/M=0/R=$imagename
	Button done,pos={119,150},size={50,20},title="Done"
	Button done,proc=DialogDoneButtonProc
	Button sall, pos={119,100},size={50,20},title="All"
	Button sall,proc=selectall
	TitleBox warning,pos={131,83},size={20,20},title=""
	TitleBox warning,anchor=MC,fColor=(65535,16385,16385)
	
	DoWindow/F $imagename
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
	Variable rval= 0
	variable mouseloc,xval,yval, xbla,ybla,fcn
	string/G imagename, selectedCurvesW
	String/G headerstuff

	switch(s.eventCode)
		case 3:
			yval=s.mouseLoc.v
			xval=s.mouseLoc.h


			ybla=axisvalfrompixel(imagename,"left",yval-s.winrect.top)
			xbla=axisvalfrompixel(imagename,"bottom",xval-s.winrect.left)

			Variable xblar =  round(xbla)
			Variable yblar =  round(ybla)

			SetDrawEnv xcoord= prel,ycoord=prel, linethick=0, fillfgc=(65280,0,0);DelayUpdate
			DrawRect xblar/ksFVRowSize+0.3/ksFVRowSize, 1-yblar/ksFVRowSize-0.3/ksFVRowSize,  xblar/ksFVRowSize+0.7/ksFVRowSize, 1-yblar/ksFVRowSize-0.7/ksFVRowSize

			fcn=xblar+(yblar*ksFVRowSize)

			print "fcn: ",fcn

			Variable offs = NumberByKey("dataOffset", headerstuff)+ksFCPoints*2*fcn*2

			wave sel=$selectedCurvesW

			print xblar, yblar

			if(xblar>=0 && xblar<=(ksFVRowSize-1) && yblar>=0 && yblar<=(ksFVRowSize-1))

				sel[fcn] = offs

				print "offset read: ", offs

			else

				print "Out of Range"
			endif

			rval= 1

	EndSwitch

	return rval

End




Function DialogDoneButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	
	string/G imagename, totalpath

	switch( ba.eventCode )
		case 2:									// mouse up
			// turn off the chooser hook
			SetWindow $imagename,hook(choose)= $""
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
	String/G headerstuff, imagename, selectedCurvesW

	
	DoWindow/F $imagename	// Bring graph to front
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
	
	printf "Elapsed time: %g seconds\r",(ticks-t0)/60

	// Create 2 waves
	// One holds file and wave names, the other the corresponding brush heights
	// Value will be filled in in AnalyseBrushHeight
	// Old waves will be overwritten
	if (WaveExists(brushheight_names))
		KillWaves brushheight_names
	endif
	if (WaveExists(brushheights))
		KillWaves brushheights
	endif
	if (WaveExists(retractfeature))
		KillWaves retractfeature
	endif
	Make/T/O/N=(totalWaves, 2) brushheight_names
	Make/O/N=(totalWaves) brushheights
	Make/O/N=(totalWaves) retractfeature
	
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
Function ParseFCHeader(fileName, headerData)
	String fileName			// Full Igor-style path to file ("folder:to:file.ext")
	String &headerData		// Pass-by-ref string will be filled with header data
	
	Variable result, subGroupOffset
	headerData = ""
	
	
	result = ReadFCHeaderLines(fileName)
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


// Read FC file given by fileName.
// Add all lines into a new text wave (fullHeader)
// return 0 if end of header found (defined by ksHeaderEnd)
// -1 otherwise.
// Last line of header not included in fullHeader.
// CR (\r) is at end of each line in the wave.
Function ReadFCHeaderLines(fileName)
	String fileName			// Full Igor-style path to filename ("folder:to:file.ext")
	
	Variable result = -1			// Set to 0 if end of header found
	
	if (strlen(fileName) == 0)
		return -1
	endif
	
	Variable refNum
	Open/R refNum as fileName				
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





End


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
	
	tmpRet = ParseFCHeader("C:Users:Janne:Desktop:au-rings-afm:peg57:peg57-pbs-0.spm", tmpHd)
	Print "ret:" + num2str(tmpRet)
	Print tmpHd
End