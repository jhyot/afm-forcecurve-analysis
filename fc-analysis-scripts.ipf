#pragma rtGlobals=1		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disable for easier debugging etc
#include <SaveGraph>
#include <Wave Loading>


// TODO
// Code style
// Quasi-height image, load byte offset from header
// rewrite(style, variable names) chooser, inspector and rinspector functions (possibly refactor)
// retraction curve handling (make optional, variable names etc)
// general variable names ("bla", "temp" etc)
// use free waves (when temp waves needed)
// Make multiple 2d arrays possible in same datafolder (keep track of wave names etc instead of hardcoding)
// all timing (debug) code, check if needed


// **** USER CONFIGURABLE CONSTANTS ****
//
// Change constants to adjust procedure behaviour

// Allowed force map versions, comma separated
// (add versions once they have been tested)
static StrConstant ksVersionReq = "0x08100000,0x08150300"

// Points per FC
// for now only works with 4096
static Constant ksFCPoints = 4096

// Force curves per row.
// For now designed and tested only for square images with 32*32 = 1024 curves
static Constant ksFVRowSize = 32

// FC file type as written in header
static StrConstant ksFileType = "FVOL"

// String to be matched (full match, case insensitive) at header end
static StrConstant ksHeaderEnd = "\\*File list end\r"
 

//
// **** END USER CONFIGURABLE CONSTANTS ****
//


// Create Igor Menu
Menu "Force Map Analysis"
	"Load File/1", LoadForceMap()
	"Choose Force Curves/2", ChooseForceCurves()
	"Do Analysis/3", Analysis()
	"Load and Analyse All FCs/4", LoadandAnalyseAll()
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

	make/O/N=(ksFVRowSize*ksFVRowsize) $selectedCurvesW


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
	
	Open/D/R/M="Open Veeco Force Volume Experiment File"/F="All Files:.*;" fileref
	
	if (cmpstr(S_fileName, "") == 0)
		print "No file selected"
		return -1
	endif
	
	NewPath/Q/O temp, ParseFilePath(1, S_fileName, ":", 1, 0)
	
	totalpath = S_fileName
	
	result = ReadMap("temp", totalpath)
	
	if (result < 0)
		print "Error reading FV map"
		return -1
	endif
	
	isMapLoaded = 1
	return 0
	
End



// Kills all waves in the current data folder starting with fc
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
Function ReadMap(path, fileName)
	String path
	String fileName			// Igor-style path: e.g. "X:Code:igor-analyse-forcecurves:test-files:pegylated_glass.004"


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
	result = ParseFCHeader(path, fileName, headerData)
	
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
	string fcWaveCurrent, fcWaveLoaded, fcNumLoaded

	
	DoWindow/F $imagename	// Bring graph to front
	if (V_Flag == 0)			// Verify that graph exists
		Abort "UserCursorAdjust: No such graph."
		return -1
	endif
	
	variable t0=ticks
	
	wave dataOffsets=$selectedCurvesW
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




Function Analysis()

// Analyse all force curves (FC) in a folder
// Returns 0 on success, -1 on error
	String path		// Symbolic path name
	String wavei			
	
	Variable totalWaves=ksFVRowSize*ksFVRowSize
	Variable result=-1
	
	Variable i, t0=ticks
	
	String/G selectedCurvesW
	
	wave brushheights
	wave retractfeature

	
	wave sel=$selectedCurvesW
		

	WAVE/T fcmeta
	make/N=(totalWaves)/O usedtime //DEBUG
	make/N=(totalWaves)/O usedtimeresult //DEBUG
	variable zres
	make/N=(totalWaves)/O usedtimefeature  //DEBUG
	variable zfeat
	
	
	string header
	Variable num = 0
	
	// Create 2d waves for Analysis
	Make/N=(ksFCPoints, totalWaves)/O fc_blfit=NaN
	Make/N=(ksFCPoints/8, totalWaves)/O fc_sensfit=NaN
	Make/N=(ksFCPoints, totalWaves)/O fc_x_tsd=NaN
	Make/N=(ksFCPoints, totalWaves)/O fc_expfit=NaN
	
	for (i=0; i < totalWaves; i+=1)
	
		variable z0=ticks		//DEBUG
		
		if(sel[i])
		
			header = fcmeta[i]
		
			variable rampSize=numberbykey("rampSize", header)
			variable VPerLSB=numberbykey("VPerLSB", header)
			variable springConst=numberbykey("springConst", header)	
			
			// Set Z piezo ramp size (x axis)
			SetScale/I x 0, (rampSize), "nm", fc
			SetScale/I x 0, (rampSize), "nm", fc_blfit
			SetScale/I x 0, (rampSize/8), "nm", fc_sensfit
			SetScale/I x 0, (rampSize), "nm", fc_expfit
		
			zres=ticks //DEBUG
		
			result = AnalyseBrushHeight(i, brushheight_names, brushheights)
			if(result < 0) //could not find start/endpoint of fit or could not fit
				brushheights[i] = -1 //put some out-of-range number for brushheight (for better visualization in result-graph)
			endif
			usedtimeresult[i]=(ticks-zres)/60 //DEBUG
			
			zfeat=ticks	//DEBUG
			
			
			usedtimefeature[i]=(ticks-zfeat)/60	//DEBUG
			
			//retractfeature[i]=retractedforcecurvebaselinefit(i, rampSize, VPerLSB, springConst)	//baselinefit for the retracted curves.
			retractfeature[i]=1 // until retractedforcecurvebaselinefit is fixed for 2d waves
		
			num += 1
		endif
		
	Prog("Analysis",i,totalWaves)
	

	usedtime[i]= (ticks-z0)/60  //DEBUG
	
	
		
	endfor

	
	printf "Elapsed time: %g seconds\r",(ticks-t0)/60
	
	if(waveexists(brushheights2))
		KillWaves brushheights2
	endif
	
	Make/N=(num)/O brushheights2
	
	num=0
	wave brushheights
	
	// What does this loop do !?
	for (i=0; i < totalWaves; i+=1)
		if(sel[i])	
			num += 1
			brushheights2[num-1] = brushheights[i]
		endif
	endfor


//	if (result==0)
//	ReviewCurves("brushheight_names", "brushheights")
//	endif
	
	
	string heights="heightsmap", temp="tempwave"
	
	if(waveexists(heights))
		killwaves $heights
	endif
	make/N=(totalWaves)/O $heights
	wave urstheights=$heights
	
	if(waveexists(temp))
		killwaves $temp
	endif
	make/N=(totalWaves)/O $temp
	wave urst=$temp
	
	duplicate/O brushheights urstheights
	duplicate/O brushheights $temp
	
	wavestats urstheights
	variable maxheight=V_max
	
	for (i=0; i < totalWaves; i+=1)
	
		if(urst[i]==-1)	
		urstheights[i]=1e6
		endif
		
	endfor
	
	
	
	redimension/N=(ksFVRowSize,ksFVRowSize) retractfeature
	
	Display/W=(29.25+450.75+400,55.25,450.75+450.75+400,458)
	AppendImage retractfeature 
	
	DoWindow/C retractfeaturesdetection
	ModifyImage retractfeature explicit=1,eval={0,46592,51712,63488},eval={-1,0,0,0},eval={1,65535,65535,65535}
	
	redimension/N=(ksFVRowSize,ksFVRowSize) urstheights

	Display/W=(29.25+450.75,55.25,450.75+450.75,458)
	AppendImage $heights
	
	DoWindow/C results
	
	ModifyImage $heights ctab={V_min+1+1e-3,V_max,Gold,0}, minRGB=(46592,51712,63488), maxRGB=(63488,0,0)
	
	DoWindow/F results
	ColorScale/C/N=text0/F=0/A=RC/E image=heightsmap
	ModifyGraph width=300, height=300
	
	DoUpdate
	SetWindow kwTopWin,hook(inspect)= inspector
	
	
	DoWindow/F retractfeaturesdetection
	SetWindow kwTopWin,hook(inspect)=rinspector
	DoUpdate

	return 0

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



Function retractedforcecurvebaselinefit(index, rampSize, VPerLSB, springConst)
	Variable index, rampSize, VPerLSB, springConst
	
	Variable totalWaves = ksFVRowSize*ksFVRowSize

	Variable/G V_fitoptions=4 //no fit window

	String wnametemp = "fc" + num2str(index)		
	WAVE w = $wnametemp
	String header = note(w)

	String wname= "rfc" + num2str(index)
	WAVE rw=$wname

	
	make/N=(totalWaves)/O timer1
	Variable tic1
	make/N=(totalWaves)/O timer2
	Variable tic2
	make/N=(totalWaves)/O timer3
	Variable tic3
	make/N=(totalWaves)/O timer4
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
	
	Variable V_fitOptions = 4		// suppress progress window
	
	WAVE/T fcmeta
	
	String header = fcmeta[index]
	
	wNames[index][0] = "fc" + num2str(index)
	wNames[index][1] = StringByKey("fileName", header)
	
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
	
	WAVE fc, fc_x_tsd, fc_expfit
	
	Display/K=1 fc[][idx] vs fc_x_tsd[][idx]
	AppendToGraph/W=$S_name fc_expfit[][idx]
	ModifyGraph rgb[0]=(0,15872,65280) 

	ModifyGraph nticks(bottom)=10,minor(bottom)=1,sep=10,fSize=12,tickUnit=1
	Label left "\\Z13force (pN)"
	Label bottom "\\Z13tip-sample distance (nm)"
	SetAxis left -25,270
	SetAxis bottom -5,75
	ModifyGraph zero=8
	
	ShowInfo
End

Function rplot2(idx)
	Variable idx
	
	String rwName = "rfc" + num2str(idx)
	String wName = "fc" + num2str(idx)
	WAVE rw = $rwName
	WAVE rwx = $(rwName + "_x_tsd")
	WAVE w = $wName
	WAVE wx = $(wName + "_x_tsd")
	WAVE wf = $(wName + "_expfit")
	
	Display w vs wx
//	AppendToGraph/W=$S_name wf
//	ModifyGraph rgb[0]=(0,15872,65280)
	
	AppendToGraph/W=$S_name rw vs rwx
	ModifyGraph rgb[0]=(0,15872,35280)
	

	ModifyGraph nticks(bottom)=10,minor(bottom)=1,sep=10,fSize=12,tickUnit=1
	Label left "\\Z13force (pN)"
	Label bottom "\\Z13tip-sample distance (nm)"
	SetAxis/A
	
	ShowInfo
End

Function plot4(idx)
	Variable idx
	
	String wname = "fc" + num2str(idx)
	WAVE w = $wname
	WAVE xTSD = $(wname + "_x_tsd")
	WAVE wlog = $(wname + "_log")
	
	WAVE ws = $(wname + "_smooth")
	WAVE xTSDs = $(wname + "_x_tsd_smooth")
	WAVE wslog = $(wname + "_smooth_log")

	Make/N=2/D/O tmp_noiselevel
	WAVE tmp_noiselevel

	if (WaveExists($(wname + "_linfit1")))
		WAVE linfit1 = $(wname + "_linfit1")
		WAVE linfit2 = $(wname + "_linfit2")
	endif
	
	// Display traces
	DoWindow/K tmp_reviewgraph
	
	Display/N=tmp_reviewgraph w vs xTSD
	AppendToGraph/L ws vs xTSDs
	ModifyGraph offset[0]={10,0}, offset[1]={10,0}
	
	AppendToGraph/R wlog vs xTSD
	AppendToGraph/R wslog vs xTSDs
	
	tmp_noiselevel = log(str2num(StringByKey("noiseLevel", note(w))))
	SetScale/I x 0, (xTSDs[numpnts(xTSDs)-1]), "nm", tmp_noiselevel
	AppendToGraph/R tmp_noiselevel
	
	AppendToGraph/R linfit1
	AppendToGraph/R linfit2
	
	SetAxis right -0.5,2.5
	
	ModifyGraph rgb[0]=(0,15872,65280), rgb[1]=(0,52224,52224), rgb[2]=(0,39168,0)
	ModifyGraph rgb[3]=(65280,43520,0), rgb[4]=(0,0,0), rgb[5]=(0,0,0), rgb[6]=(65280,0,0)

	ModifyGraph msize=0.5, mode=3
	ModifyGraph marker[0]=16, marker[2]=16, marker[1]=0, marker[3]=0
	ModifyGraph mode[4]=0, mode[5]=0, mode[6]=0
	ModifyGraph lsize[4]=1, lsize[5]=2, lsize[6]=2
	
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
	NewPath/O tmpPath1, "C:Users:Janne:Desktop:au-rings-afm:peg57:"
	Variable tmpRet
	String tmpHd
	
	tmpRet = ParseFCHeader("tmpPath1", "peg57-pbs-0.spm", tmpHd)
	Print "ret:" + num2str(tmpRet)
	Print tmpHd
End