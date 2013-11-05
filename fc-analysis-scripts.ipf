#pragma rtGlobals=3		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc


#include ":fc-script-config"
#include ":loader"
#include ":parser"
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