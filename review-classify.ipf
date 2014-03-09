#pragma rtGlobals=3		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc


Function FlagCurves()
	
	if (!IsDataLoaded())
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
			deflcalc = NumberByKey("deflSensUsed", fcmeta[i])
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
	if (!IsDataLoaded())
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
	if (!IsDataLoaded())
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
	if (!IsDataLoaded())
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	WAVE flaggedcurves
	
	MarkPixels(flaggedcurves, 1, 1)
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
			shortHeader += num2str(NumberByKey("deflSensUsed", header)) + " (used)"
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



Function ClassifyCurves()
	if (!IsDataLoaded())
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	
	Variable ret = 0
	ret = ImageToForeground()
	if (ret < 0)
		print "Error: No image."
		return -1
	endif
	
	SVAR/Z classifymeta
	if (!SVAR_Exists(classifymeta))
		String/G classifymeta = ""
	endif
		
	SVAR imagegraph = :internalvars:imagegraph
	
	DrawPointMarker(imagegraph, NumberByKey("centerX", classifymeta), NumberByKey("centerY", classifymeta), 1)
	
	NewPanel/N=selectcenter/W=(0,0,270,30) as "Select center"
	AutoPositionWindow/M=0/R=$imagegraph
	TitleBox text0, title="Select center of feature in the image.",frame=0,fstyle=1,pos={10,10}
	
	DoWindow/F $imagegraph
	SetWindow $imagegraph, hook(imageinspect)=$""		// deactivate inspector hook
	SetWindow $imagegraph, hook(classifycenter)=ClassifyCurves_SelectCenter
End


Function ClassifyCurves_SelectCenter(s)
	STRUCT WMWinHookStruct &s
	
	Variable rval = 0
	SVAR imagegraph = :internalvars:imagegraph

	// React only on left mousedown
	if ((s.eventCode == 3) && (s.eventMod & 1 != 0))
		Variable mouseY = s.mouseLoc.v
		Variable mouseX = s.mouseLoc.h
		
		NVAR rowsize = :internalvars:FVRowSize
		
		// Get image pixel and force curve number
		Variable pixelY = round(AxisValFromPixel(imagegraph, "left", mouseY-s.winrect.top))
		Variable pixelX = round(AxisValFromPixel(imagegraph, "bottom", mouseX-s.winrect.left))

		if(pixelX >= 0 && pixelX <= (rowsize-1) && pixelY >= 0 && pixelY <= (rowsize-1))
			DrawPointMarker(imagegraph, pixelX, pixelY, 1)
			SVAR classifymeta
			classifymeta = ReplaceNumberByKey("centerX", classifymeta, pixelX)
			classifymeta = ReplaceNumberByKey("centerY", classifymeta, pixelY)
			print "Center selected. X: " + num2str(pixelX) + "; Y: " + num2str(pixelY)
			
			Variable avgtopo = ClassifyCurves_GetAvgTopo()
			classifymeta = ReplaceNumberByKey("avgTopo", classifymeta, avgtopo)
			print "Avg height near center: " + num2str(avgtopo) + " nm"
			
			// Reactivate inspector hook, kill info panel
			SetWindow $imagegraph, hook(imageinspect)=inspector
			SetWindow $imagegraph, hook(classifycenter)=$""
			KillWindow selectcenter
			
			// Call function after operation queue is empty (i.e. current function finishes)
			Execute/P/Q "ClassifyCurves_ShowCurves()"
		endif

		rval = 1
	endif

	return rval
End


Function ClassifyCurves_GetAvgTopo()
	SVAR classifymeta
	Variable centerx = NumberByKey("centerX", classifymeta)
	Variable centery = NumberByKey("centerY", classifymeta)
	
	NVAR rowsize = :internalvars:FVRowSize
	SVAR imwavename = :internalvars:imagewave
	WAVE imwave = $imwavename
	
	
	Variable i, j
	Variable range = ceil(rowsize/10)
	Variable numpix = 0
	Variable avg = 0
	
	for (i=centerx-range; i<=centerx+range; i+=1)
		for (j=centery-range; j<=centery+range; j+=1)
			if (i>=0 && i<rowsize && j>=0 && j<rowsize)
				avg += imwave[i][j]
				numpix += 1
			endif
		endfor
	endfor
	
	avg /= numpix
	
	return avg
End


Function ClassifyCurves_ShowCurves()

	WAVE fc
	WAVE fc_x_tsd

	SVAR imagegraph = :internalvars:imagegraph
	NVAR rowsize = :internalvars:FVRowSize
	NVAR numcurves = :internalvars:numCurves
	
	SVAR imwavename = :internalvars:imagewave
	WAVE imwave = $imwavename
	
	Make/O/N=(numcurves) classify = NaN

	SVAR classifymeta
	Variable avgtopo = NumberByKey("avgTopo", classifymeta)
	Variable igntopo = avgtopo / 2
	classifymeta = ReplaceNumberByKey("ignoreBelowTopo", classifymeta, igntopo)
	print "Ignoring points with height below " + num2str(igntopo) + " nm"

	Variable pixelX = 0
	Variable pixelY = 0
	Variable del = 0		// Draw first marker without deleting old one so that user sees center marker
	Variable i = 0
	Variable lastnotignored = 0
	Variable numAutoIgnored = 0
	for (i=0; i < numcurves; i+=1)
		if (imwave[i] < igntopo)
			numAutoIgnored += 1
			continue
		endif
		DoWindow/K tmp_classifygraph
		PlotFC(i)
		DoWindow/C tmp_classifygraph
		
		PlotFC_setzoom(1)
		
		pixelX = mod(i,rowsize)
		pixelY = floor(i/rowsize)
		DrawPointMarker(imagegraph, pixelX, pixelY, del)
		
		NewPanel/N=tmp_classifydialog/W=(0,0,200,80) as "Classify Curve"
		AutoPositionWindow/M=0/R=tmp_classifygraph
		String helptxt = "\\f01Enter: \\f00Mark as feature.\r"
		helptxt += "\\f01Esc: \\f00No feature."
		TitleBox text0, title=helptxt,frame=0,pos={10,10}
		helptxt = "\\f01Tab: \\f00Exclude from classification.\r"
		helptxt += "\\f01Backspace: \\f00Redo last."
		TitleBox text1, title=helptxt,frame=0,pos={10,40}
		
		SetWindow tmp_classifygraph, hook(classifycurves)=ClassifyCurves_KeybHook
		SetWindow tmp_classifydialog, hook(classifycurves)=ClassifyCurves_KeybHook
		SetWindow tmp_classifydialog, userdata=("index:" + num2str(i))
		
		Variable/G tmp_classifydialog_redo = 0
		
		// Wait for user interaction (ends when dialog window is killed)
		PauseForUser tmp_classifydialog, tmp_classifygraph
		
		NVAR tmp_classifydialog_redo
		if (tmp_classifydialog_redo)
			i = lastnotignored-1
		else
			lastnotignored = i
		endif
		KillVariables tmp_classifydialog_redo
		
		del = 1
	endfor
	
	print "Number of automatically ignored curves: " + num2str(numAutoIgnored)
	
	DoWindow/K tmp_classifygraph
	
	Classify_CalcRadius()
	Classify_MakeHisto()
	
	print "All curves classified."
End


Function ClassifyCurves_KeybHook(s)
	STRUCT WMWinHookStruct &s
	
	Variable rval = 0

	// Keyboard
	if (s.eventCode == 11)
		if (s.keycode == 13 || s.keycode == 27 || s.keycode == 9 || s.keycode == 8)
			// Enter, Esc, Tab, Backspace
			Variable index = NumberByKey("index", GetUserData("tmp_classifydialog", "", ""))
			WAVE classify
	
			switch (s.keycode)
				case 13:	// Enter
					classify[index] = 1
					break
				case 27:	// Esc
					classify[index] = 0
					break
				case 9:	// Tab
					classify[index] = NaN
					break
				case 8:	// Backspace
					classify[index] = NaN
					NVAR tmp_classifydialog_redo
					tmp_classifydialog_redo = 1
					break
			endswitch
			
			KillWindow tmp_classifydialog
			
			rval = 1
		else
			switch (s.keycode)
				case 120:		// x
					// focus plot window and call event handler manually
					DoWindow/F tmp_classifygraph
					PlotFC_switchx("")
					rval = 1
					break
			endswitch
		endif
	endif

	return rval
End


Function Classify_CalcRadius()
	
	NVAR numcurves = :internalvars:numCurves
	NVAR rowsize = :internalvars:FVRowSize
	SVAR classifymeta
	Variable centerX = NumberByKey("centerX", classifymeta)
	Variable centerY = NumberByKey("centerY", classifymeta)
	SVAR imagewavename = :internalvars:imagewave
	WAVE image = $imagewavename
	
	Make/O/N=(numcurves) classify_dist = NaN
	Make/O/N=(numcurves) classify_alldist = NaN
	
	WAVE classify
	Variable pixelX = 0
	Variable pixelY = 0	
	Variable i
	Variable r
	Variable numNaNs = 0
	for (i=0; i < numcurves; i += 1)	
		pixelX = mod(i,rowsize)
		pixelY = floor(i/rowsize)
		// if NaN, pixel was not included in classification
		if (numtype(classify[i]) == 0)
			classify_alldist[i] = sqrt( (centerX - pixelX)^2 + (centerY - pixelY)^2 )
		
			if (classify[i])
				// Feature was marked
				classify_dist[i] = classify_alldist[i]
			endif
		else
			numNaNs += 1
		endif
	endfor
	
	print "Number of curves excluded from classification (incl. outside of ring): " + num2str(numNaNs)
	
	Variable pixelsize = NumberByKey("scansize", note(image)) / rowsize
	
	Duplicate/O classify_dist, classify_dist_scaled
	classify_dist_scaled *= pixelsize
End


Function Classify_MakeHisto()
	Variable binsize = 1	// pixel
	
	NVAR rowsize = :internalvars:FVRowSize
		
	WAVE classify_dist, classify_alldist
	
	Variable bins = rowsize / binsize
	Make/O/N=(bins) classify_disthisto
	
	Histogram/B={0, binsize, bins} classify_dist, classify_disthisto
	
	// normalize histogram to number of total pixels in given distance from center
	Make/O/N=(bins) classify_alldisthisto
	Histogram/B={0, binsize, bins} classify_alldist, classify_alldisthisto
	
	Duplicate/O classify_disthisto, classify_disthisto_norm
	classify_disthisto_norm /= classify_alldisthisto
	
	Display classify_disthisto, classify_alldisthisto
	AppendToGraph/R classify_disthisto_norm
	SetAxis right 0,1
	ModifyGraph rgb[1]=(0,0,0), rgb[2]=(0,0,65280)
	Legend/C/N=text0/J/A=RT/X=0.00/Y=0.00 "\\s(classify_disthisto) dist histo\r\\s(classify_alldisthisto) all pixels\r\\s(classify_disthisto_norm) norm dist histo"
	
	PutDFNameOnGraph()
End


Function MarkClassifiedPixels()
	if (!IsDataLoaded())
	
		print "Error: no FV map loaded yet"
		return -1
	endif
	
	WAVE classify
	
	MarkPixels(classify, 1, 2)
End


Function MarkPixels(filterw, del, color)
	WAVE filterw		// Wave with pixels to be marked; 1 = mark pixel; any other value = don't mark
	Variable del		// 0: keep previous markers; 1: remove previous markers
	Variable color	// use color (1, 2) see DrawPointMarker for colors;
	
	Variable numcurves = numpnts(filterw)
	NVAR rowsize = :internalvars:FVRowSize
	SVAR imagegraph = :internalvars:imagegraph
	SVAR resultgraph = :internalvars:resultgraph
	
	if (del == 1)
		// delete previous markers
		DrawPointMarker(imagegraph, NaN, NaN, 1)
		DrawPointMarker(resultgraph, NaN, NaN, 1)
	endif

	Variable i
	for (i=0; i < numcurves; i+=1)
		if (filterw[i] == 1)
			Variable pixelX = mod(i,rowsize)
			Variable pixelY = floor(i/rowsize)
			DrawPointMarkerColor(imagegraph, pixelX, pixelY, 0, color)
			DrawPointMarkerColor(resultgraph, pixelX, pixelY, 0, color)
		endif
	endfor
End

