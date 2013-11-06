#pragma rtGlobals=3		// Use modern global access method.


// Function returns wave with 4 rows in this order:
// y-min; y-max; x-min; x-max
// This function is here at the beginning of the file so that the user can
// "conveniently" change zoom levels and have them available at the different
// plotting/zooming functions
Function/WAVE GetZoom(xtype, level)
	Variable xtype, level
	
	// Set zoom levels in a 3D wave:
	// 1D: xtype;  2D: zoom level;  3D: y-min, y-max, x-min, x-max
	// NaN = autoscale (check only "min" value)
	Make/FREE/N=(3, 5, 4) zoom = NaN

	
	// ========
	// ZOOM VALUES BLOCK
	
	//          left     ;    bottom
	// TSD, lvl0
	zoom[1][0][0] = NaN; zoom[1][0][2] = NaN
	zoom[1][0][1] = NaN; zoom[1][0][3] = NaN
	// TSD, lvl1
	zoom[1][1][0] = NaN; zoom[1][1][2] = -5
	zoom[1][1][1] = NaN; zoom[1][1][3] = 80
	// TSD, lvl2
	zoom[1][2][0] = -5000; zoom[1][2][2] = -5
	zoom[1][2][1] = 250; zoom[1][2][3] = 60
	// TSD, lvl3
	zoom[1][3][0] = -35; zoom[1][3][2] = -5
	zoom[1][3][1] = 150; zoom[1][3][3] = 75
	// Xsection plot zoom
	zoom[1][4][0] = -200; zoom[1][4][2] = -5
	zoom[1][4][1] = 250; zoom[1][4][3] = 120
	
	//          left     ;    bottom
	// Zp, lvl0
	zoom[2][0][0] = NaN; zoom[2][0][2] = NaN
	zoom[2][0][1] = NaN; zoom[2][0][3] = NaN
	// Zp, lvl1
	zoom[2][1][0] = NaN; zoom[2][1][2] = -5
	zoom[2][1][1] = NaN; zoom[2][1][3] = 350
	// Zp, lvl2
	zoom[2][2][0] = -40; zoom[2][2][2] = 20
	zoom[2][2][1] = 300; zoom[2][2][3] = 120
	// Zp, lvl3
	zoom[2][3][0] = -20; zoom[2][3][2] = 30
	zoom[2][3][1] = 150; zoom[2][3][3] = 100

	// ========
	// END ZOOM VALUES BLOCK
	
	
	Make/FREE/N=4 zoomret
	zoomret = zoom[xtype][level][p]
	
	return zoomret
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


// Displays new graph with topography image
// and saves reference to it in internal var
Function ShowImage()
	SVAR imagewave = :internalvars:imagewave
	String/G :internalvars:imagegraph = RecreateImage(imagewave)	
	return 0
End

// Displays new graph with image in parameter
// Returns graph name
Function/S RecreateImage(img)
	String img	// name of image wave to be displayed
	
	Display/W=(30,55,30+387,55+358)
	String name = MakeGraphName("image")
	DoWindow/C $name
	AppendImage $img
	ModifyImage $img ctab={*,*,Gold,0}
	ModifyGraph width=300,height=300,margin(right)=90
	ColorScale/C/N=scale/F=0/A=RC/X=-28 image=$img, "topography (nm)"
	
	PutDFNameOnGraph()

	DoUpdate
	
	return name
End


// Displays new graph with topography image
Function ShowResultMap()
	SVAR resultwave = :internalvars:resultwave

	Display/W=(30+430,55,30+387+430,55+358)
	String name = MakeGraphName("result")
	DoWindow/C $name
	AppendImage $resultwave
	
	String/G :internalvars:resultgraph = name
	
	// Scale range between 0 and 99th percentile of heights (ignore extreme outliers)
	WAVE brushheights
	Variable upper = GetUpperPercentile(brushheights, 99)
	// Round to upper decade
	upper = 10*ceil(upper/10)
	
	ModifyImage $resultwave ctab={0,upper,Gold,0}, minRGB=(46592,51712,63488), maxRGB=(29440,0,58880)
	
	ColorScale/C/N=text0/F=0/A=RC/E image=$resultwave
	ModifyGraph width=300, height=300
	
	PutDFNameOnGraph()
	
	DoUpdate
	
	SetWindow kwTopWin,hook(resultinspect)=inspector
	
	return 0	
End


Function GetUpperPercentile(w, pct)
	WAVE w				// wave from where to get value
	Variable pct		// which percentile to return
	
	Duplicate/O/FREE w, wsort
	Sort wsort, wsort
	WaveStats/Q/M=1 wsort
	Variable i = min(round((V_npnts-1)*pct/100), V_npnts-1)
	return wsort[i]
End


Function PlotFC(index)
	Variable index
	
	Display
	String name = MakeGraphName("fc" + num2str(index) + "_plot")
	DoWindow/C $name
	
	PutDFNameOnGraph()

	ShowInfo
	
	ControlBar/T 30
	
	// Zoom buttons
	Button zoomb,title="Zoom",proc=PlotFC_zoom
	Button unzoomb,title="Unzoom",proc=plotFC_zoom
	
	// Buttons for showing and hiding curves
	// Save in userdata whether curve is shown at the moment
	// Default (i.e. on first curve): show approach, hide retract
	Button showapproachb,title="Hide approach",size={80,20},proc=PlotFC_showcurves
	Button showretractb,title="Show retract",size={80,20},proc=PlotFC_showcurves	
	GetWindow kwTopWin, userdata
	String winUserdata = S_Value
	winUserdata = ReplaceNumberByKey("approach", winUserdata, 1)
	winUserdata = ReplaceNumberByKey("retract", winUserdata, 0)
	
	// X axis type:
	// 1: tip-sample distance
	// 2: Z piezo position
	Button xtypeb,title="X: TSD",size={60,20},proc=PlotFC_switchx
	winUserdata = ReplaceNumberByKey("xtype", winUserdata, 1)
	
	Button printmetab,title="Metadata",size={55,20},proc=PlotFC_printmeta
	
	SetWindow kwTopWin, userdata=winUserdata
	
	PlotFC_plotdata(index)
	
	SetWindow kwTopWin,hook(fcnavigate)=PlotFC_navigate
End


Function PlotFC_plotdata(index)
	Variable index		// force curve number to plot
	
	NVAR numcurves = :internalvars:numCurves
	
	if (index < 0 || index >= numcurves)
		return -1
	endif
	
	// Somewhat of a "hack" to switch on/off parts of elements on graph
	Variable mode = 1
	
	GetWindow kwTopWin, userdata
	String winUserdata = S_Value
	Variable showapproach = NumberByKey("approach", winUserdata)
	Variable showretract = NumberByKey("retract", winUserdata)
	Variable zoomlvl = NumberByKey("zoomlvl", winUserdata)
	Variable xtype = NumberByKey("xtype", winUserdata)
	
	showapproach = (numtype(showapproach) > 0) ? 1 : showapproach
	showretract = (numtype(showretract) > 0) ? 0 : showretract
	zoomlvl = (numtype(zoomlvl) > 0) ? 1 : zoomlvl
	xtype = (numtype(xtype) > 0) ? 1 : xtype
	
	// Remove all previous traces
	Variable numtraces = ItemsInList(TraceNameList("", ";", 1))
	Variable i=0
	String t=""
	for (i=0; i < numtraces; i+=1)
		RemoveFromGraph $"#0"		// remove the currently first trace, others shift up
	endfor
	
	Variable tracenum = 0
	
	if (showapproach)
		WAVE fc, fc_x_tsd, fc_expfit, fc_smth, fc_smth_xtsd
		AppendToGraph fc[][index]
		if (xtype == 1)
			ReplaceWave/X trace=fc, fc_x_tsd[][index]
		endif
		if (mode == 0)
			if (fc_expfit[0][index] && xtype == 1)
				AppendToGraph fc_expfit[][index]
			elseif (fc_smth[0][index])
				AppendToGraph fc_smth[][index]
				if (xtype == 1)
					ReplaceWave/X trace=fc_smth, fc_smth_xtsd[][index]
				endif
			endif
		endif
		ModifyGraph rgb[tracenum]=(0,15872,65280)
		tracenum += 1
		
		// Color 2nd trace if present
		if (ItemsInList(TraceNameList("", ";", 1)) > tracenum)
			ModifyGraph rgb[tracenum]=(65280,0,0)
			tracenum += 1
		endif
	endif
	
	if (showretract)
		WAVE rfc, rfc_x_tsd
		AppendToGraph rfc[][index]
		if (xtype == 1)
			ReplaceWave/X trace=rfc, rfc_x_tsd[][index]
		endif
		ModifyGraph rgb[tracenum]=(0,52224,0)
		tracenum += 1
	endif
	
	ModifyGraph marker=19,msize=1,mrkThick=0,mode=3
	ModifyGraph nticks(bottom)=10,minor(bottom)=1,sep=10,fSize=12,tickUnit=1
	Label left "\\Z13force (pN)"
	if (xtype == 1)
		Label bottom "\\Z13tip-sample distance (nm)"
	elseif (xtype == 2)
		Label bottom "\\Z13Z piezo (nm)"
	endif
	ModifyGraph zero=8
	
	PlotFC_setzoom(zoomlvl)	
	
	WAVE brushheights
	NVAR rowsize = :internalvars:FVRowSize
	SVAR iwavename = :internalvars:imagewave
	WAVE iwave = $iwavename
	
	String text=""
	sprintf text, "FC: %d;   X: %d; Y: %d", index, mod(index,rowsize), floor(index/rowsize)
	sprintf text, "%s\rTopo: %.1f nm", text, iwave[index]

//	if (mode==0)
		sprintf text, "%s\rBrush height: %.2f nm", text, brushheights[index]
//	endif
	TextBox/C/N=fcinfobox/A=RT (text)
	
	// Draw drop-line at brush height
	DrawAction delete
	if (mode==0 && brushheights[index])		
		SetDrawEnv xcoord=bottom, ycoord=prel, dash=11
		DrawLine brushheights[index],0.3, brushheights[index],1.05
	endif
	
	// Put curve index and zoom level into window userdata
	winUserdata = ReplaceNumberByKey("index", winUserdata, index)
	winUserdata = ReplaceNumberByKey("zoomlvl", winUserdata, zoomlvl)
	winUserdata = ReplaceNumberByKey("mode", winUserData, mode)
	SetWindow kwTopWin, userdata=winUserdata
End


Function PlotFC_navigate(s)
	STRUCT WMWinHookStruct &s
	
	Variable ret = 0
	
	// keyboard events with ctrl pressed
	if (s.eventCode == 11 && s.eventmod == 8)
		NVAR rowsize = :internalvars:FVRowSize
		NVAR numcurves = :internalvars:numCurves
		GetWindow kwTopWin, userdata
		Variable index = NumberByKey("index", S_Value)
		switch (s.keycode)
			case 28:		// left arrow
				index -= 1
				ret = 1
				break
			
			case 29:		// right arrow
				index += 1
				ret = 1
				break
				
			case 30:		// up arrow
				index += rowsize
				ret = 1
				break
				
			case 31:		// down arrow
				index -= rowsize
				ret = 1
				break
		endswitch
	endif
	
	if (index < 0 || index >= numcurves)
		ret = 0
	endif
	
	// if updated index, update plot and redraw markers on the images
	if (ret == 1)
		PlotFC_plotdata(index)
		NVAR rowsize = :internalvars:FVRowSize
		SVAR imagegraph = :internalvars:imagegraph
		SVAR resultgraph = :internalvars:resultgraph
		Variable pixelX = mod(index, rowsize)
		Variable pixelY = floor(index/rowsize)
		DrawPointMarker(imagegraph, pixelX, pixelY, 1)
		DrawPointMarker(resultgraph, pixelX, pixelY, 1)
	endif
	
	return ret
End


Function PlotFC_zoom(cname) : ButtonControl
	String cname
	
	GetWindow kwTopWin, userdata
	Variable zoomlvl = NumberByKey("zoomlvl", S_Value)
	
	strswitch (cname)
		case "zoomb":
			zoomlvl += 1
			if (zoomlvl > 3)
				zoomlvl = 3
			endif
			break
			
		case "unzoomb":
			zoomlvl -= 1
			if (zoomlvl < 0)
				zoomlvl = 0
			endif
			break
	endswitch
	
	PlotFC_setzoom(zoomlvl)
	String udata = ReplaceNumberByKey("zoomlvl", S_Value, zoomlvl)
	SetWindow kwTopWin, userdata=udata
	
End


Function PlotFC_showcurves(cname) : ButtonControl
	String cname
	
	ControlInfo $cname
	
	// Get fc number
	GetWindow kwTopWin, userdata
	String winUserdata = S_Value
	Variable index = NumberByKey("index", winUserdata)
	Variable showapproach = NumberByKey("approach", winUserdata)
	Variable showretract = NumberByKey("retract", winUserdata)
	Variable mode = NumberByKey("mode", winUserdata)
	Variable xtype = NumberByKey("xtype", winUserdata)
	
	if (numtype(index) != 0)
		// Not a normal number, do nothing, since we don't know what curve we have
		return -1
	endif
	
	Variable trace = 0
	Variable newtracenum = 0
	
	strswitch (cname)
		case "showapproachb":
			if (showapproach)
				// Hide approach graph
					RemoveFromGraph/Z fc, fc_smth, fc_expfit
					Button showapproachb,title="Show approach"
					winUserdata = ReplaceNumberByKey("approach", winUserdata, 0)
			else
				// Show approach graph
					WAVE fc, fc_x_tsd, fc_smth, fc_smth_xtsd
					
					AppendToGraph fc[][index]
					newtracenum += 1
					if (xtype == 1)
						ReplaceWave/X trace=fc, fc_x_tsd[][index]
					endif
					if (mode == 0)
						AppendToGraph fc_smth[][index]
						newtracenum += 1
						if (xtype == 1)
							ReplaceWave/X trace=fc_smth, fc_smth_xtsd[][index]
						endif
					endif
					
					trace = ItemsInList(TraceNameList("", ";", 1)) - newtracenum
					ModifyGraph rgb[trace]=(0,15872,65280)
					if (mode == 0)
						ModifyGraph rgb[trace+1]=(65280,0,0)
					endif
					
					Button showapproachb,title="Hide approach"
					winUserdata = ReplaceNumberByKey("approach", winUserdata, 1)
			endif
			break
		
		case "showretractb":
			if (showretract)
				// Hide retract graph
					RemoveFromGraph/Z rfc
					Button showretractb,title="Show retract"
					winUserdata = ReplaceNumberByKey("retract", winUserdata, 0)
			else
				// Show retract graph
					WAVE rfc, rfc_x_tsd
					AppendToGraph rfc[][index]
					if (xtype == 1)
						ReplaceWave/X trace=rfc, rfc_x_tsd[][index]
					endif
					
					trace = ItemsInList(TraceNameList("", ";", 1)) - 1
					ModifyGraph rgb[trace]=(0,52224,0)
					
					Button showretractb,title="Hide retract"
					winUserdata = ReplaceNumberByKey("retract", winUserdata, 1)
			endif
			break
			
	endswitch
	
	ModifyGraph marker=19,msize=1,mrkThick=0,mode=3
	
	SetWindow kwTopWin, userdata=winUserdata
End


Function PlotFC_switchx(cname) : ButtonControl
	String cname
	
	// Get window metadata
	GetWindow kwTopWin, userdata
	String winUserdata = S_Value
	Variable index = NumberByKey("index", winUserdata)
	Variable showapproach = NumberByKey("approach", winUserdata)
	Variable showretract = NumberByKey("retract", winUserdata)
	Variable mode = NumberByKey("mode", winUserdata)
	Variable xtype = NumberByKey("xtype", winUserdata)
	
	if (numtype(index) != 0)
		// Not a normal number, do nothing, since we don't know what curve we have
		return -1
	endif
	
	switch (xtype)
		case 1:	// TSD -> switch to Zpiezo
			if (showapproach)
				ReplaceWave/X trace=fc, $""
				if (mode == 0)
					ReplaceWave/X trace=fc_smth, $""
				endif
			endif
			if (showretract)
				ReplaceWave/X trace=rfc, $""
			endif
			xtype = 2
			Button xtypeb,title="X: Zpiezo"
			Label bottom "\\Z13Z piezo (nm)"
			break
			
		case 2:	// Zpiezo -> switch to TSD
			WAVE fc_x_tsd, fc_smth_xtsd, rfc_x_tsd
			if (showapproach)
				ReplaceWave/X trace=fc, fc_x_tsd[][index]
				if (mode == 0)
					ReplaceWave/X trace=fc_smth, fc_smth_xtsd[][index]
				endif
			endif
			if (showretract)
				ReplaceWave/X trace=rfc, rfc_x_tsd[][index]
			endif
			xtype = 1
			Button xtypeb,title="X: TSD"
			Label bottom "\\Z13tip-sample distance (nm)"
			break
	endswitch
	
	winUserdata = ReplaceNumberByKey("xtype", winUserdata, xtype)
	SetWindow kwTopWin, userdata=winUserdata
	
	Variable zoomlvl = NumberByKey("zoomlvl", winUserdata)
	PlotFC_setzoom(zoomlvl)
	
	return 0
End


Function PlotFC_printmeta(cname) : ButtonControl
	String cname
	
	WAVE/T fcmeta
	WAVE brushheights
	GetWindow kwTopWin, userdata
	Variable i = NumberByKey("index", S_Value)
	String s = ""
	sprintf s, "FC %d; Brushheight: %.1f;  %s", i, brushheights[i], fcmeta[i]
	print s
	
	return 0
End


Function PlotFC_setzoom(level)
	Variable level
	
	GetWindow kwTopWin, userdata
	Variable xtype = NumberByKey("xtype", S_Value)
	
	WAVE zoom = GetZoom(xtype, level)
	
	Variable leftmin = zoom[0]
	Variable leftmax = zoom[1]
	Variable bottmin = zoom[2]
	Variable bottmax = zoom[3]
	
	if (numtype(leftmin) > 0)
		SetAxis/A left
	else
		SetAxis left, leftmin, leftmax
	endif
	if (numtype(bottmin) > 0)
		SetAxis/A bottom
	else
		SetAxis bottom, bottmin, bottmax
	endif
	
	SetWindow kwTopWin, userdata=(ReplaceNumberByKey("zoomlvl", S_Value, level))
	
	return 0
End


// Plots line cross-section topography with brush height;
// and single curves (defl + friction) based on marker point in the cross-section plot
Function PlotXsectFC()
	WAVE brushheights, fc_z, fc, fc_fric, fc_x_tsd
	
	Display/T brushheights,fc_z
	AppendToGraph/L=fc fc[][0]
	AppendToGraph/R fc_fric[][0]
	AppendToGraph/L=fc fc[][0]/TN=fc_tsd vs fc_x_tsd[][0]
	
	ModifyGraph rgb(brushheights)=(65280,0,0), rgb(fc_z)=(0,0,0)
	ModifyGraph rgb(fc)=(0,15872,65280), rgb(fc_fric)=(65280,0,0), rgb(fc_tsd)=(0,0,0)
	ModifyGraph useNegRGB(brushheights)=1, negRGB(brushheights)=(32768,54528,65280)
	
	ModifyGraph mode(brushheights)=7, hbFill(brushheights)=2, toMode(brushheights)=2, lsize(brushheights)=0
	//ModifyGraph offset(fc_fric)={0,300}, muloffset(fc_fric)={0,3000}
	ModifyGraph offset(fc_tsd)={30,0}
	ModifyGraph standoff=0, zero(left)=1
	ModifyGraph freePos(fc)={0,kwFraction}
	ModifyGraph freePos(right)={0,kwFraction}
	ModifyGraph axisEnab(left)={0.65,1}
	ModifyGraph axisEnab(fc)={0,0.6}
	ModifyGraph axisEnab(right)={0,0.6}
	
	SetAxis bottom 0,100
	
	String text = "FC: 0"
	TextBox/C/N=fcinfobox/A=RC text
	
	ShowInfo
	
	SetWindow kwTopWin, hook(xsectcursor)=PlotXsectFC_movecursor
End

Function PlotXsectFC_movecursor(s)
	STRUCT WMWInHookStruct &s
	
	if (s.eventcode != 7)
		return 0
	endif
	
	// eventcode 7 = cursormoved
	
	if (cmpstr(s.traceName, "brushheights") == 0 || cmpstr(s.traceName, "fc_z") == 0)
		Variable pt = s.pointNumber
		
		WAVE fc, fc_fric, fc_x_tsd
		
		ReplaceWave trace=fc, fc[][pt]
		ReplaceWave trace=fc_fric, fc_fric[][pt]
		ReplaceWave trace=fc_tsd, fc[][pt]
		ReplaceWave/X trace=fc_tsd, fc_x_tsd[][pt]
		
		String text = "FC: " + num2str(pt)
		TextBox/C/N=fcinfobox text
		
		return 1
	endif
	
End


// Print the name of the data folder onto the graph
// If a graph is in front, use the data folder of the first trace/image
// Otherwise use current data folder
Function PutDFNameOnGraph()
	String df
// If a graph is in front, return the data folder of the first trace/image
// Otherwise return current data folder
Function/S GetGraphDF()
	String df = ""
	
	// Test if graph is an image
	String imlist = ImageNameList("", ";")
	if (cmpstr("", imlist) != 0)
		// is an image
		WAVE w = ImageNameToWaveRef("", StringFromList(0, imlist))
		df = GetWavesDataFolder(w, 1)
	else
		// not an image, i.e. might be normal traces
		// check whether any window is on top
		DoWindow kwTopWin
		if (V_flag == 1)
			WAVE/Z w = WaveRefIndexed("", 0, 3)
			if (WaveExists(w))
				df = GetWavesDataFolder(w, 1)
			else
				// didn't find image or normal traces, just use current data folder
				df = GetDataFolder(1)
			endif
		else
			// no window displayed, use current data folder
			df = GetDataFolder(1)
		endif
	endif
	
	return df
End


// Print the name of the data folder onto the graph
Function PutDFNameOnGraph()
	String df = TidyDFName(GetGraphDF())
	TextBox/C/N=dfname/F=0/A=LB/X=.5/Y=.1/E=2 "\\Zr085" + df
End


// "Tidies up" data folder name for displaying/printing.
// E.g. the string you get from GetDataFolder(1)
// Removes 'root:' in front, removes all single quotes
// Returns tidied up name
Function/S TidyDFName(df)
	String df
	
	df = ReplaceString("'", df, "")
	SplitString/E="(?i)^root:(.*?):?$" df, df
	
	return df
End

// Returns graph name like:
// <datafolder>_<suffix>
Function/S MakeGraphName(suffix)
	String suffix
	
	String name = TidyDFName(GetGraphDF())
	name = ReplaceString(":", name, "_")
	
	name = name + "_" + suffix

	DoWindow $name
	if (V_flag > 0)
		// Window name in use, look for unused one
		Variable n = 0
		name = name + "0"
		do
			DoWindow $name
			if (V_Flag == 0)
				break
			endif
			
			n += 1
			name = name[0, strlen(name)-strlen(num2str(n-1))-1] + num2str(n)
		while (1)
	endif
	
	return name
End

// Renames top graph with to <datafolder>_<suffix>
Function RenameGraph(suffix)
	String suffix
	
	String name = MakeGraphName(suffix)
	DoWindow/C $name
	
	return 0
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
	
	WAVE fc, fc_x_tsd, fc_expfit, fc_smth, fc_smth_xtsd
	
	Display/K=1 fc[][idx] vs fc_x_tsd[][idx]
	if (fc_expfit[0][idx])
		AppendToGraph/W=$S_name fc_expfit[][idx]
	elseif (fc_smth[0][idx])
		AppendToGraph/W=$S_name fc_smth[][idx] vs fc_smth_xtsd[][idx]
	endif
	ModifyGraph rgb[0]=(0,15872,65280)

	ModifyGraph nticks(bottom)=10,minor(bottom)=1,sep=10,fSize=12,tickUnit=1
	Label left "\\Z13force (pN)"
	Label bottom "\\Z13tip-sample distance (nm)"
	SetAxis left -35,250
	SetAxis bottom -5,120
	ModifyGraph zero=8
	
	WAVE brushheights
	NVAR rowsize = :internalvars:FVRowSize
	
	String text, text2
	text = "FC: " + num2str(idx) + ";   X: " + num2str(mod(idx,rowsize))
	text += "; Y:" + num2str(floor(idx/rowsize))
	sprintf text2, "\rBrush height: %.2f nm", brushheights[idx]
	TextBox/A=RT (text + text2)
	
	// Draw drop-line at brush height
	if (brushheights[idx])
		SetDrawEnv xcoord=bottom, ycoord=prel, dash=11
		DrawLine brushheights[idx],0.3, brushheights[idx],1.05
	endif
	
	ShowInfo
	
	Variable/G plot2zoom = 1
	
	ControlBar/T 30
	Button zoomb,title="Zoom",proc=plot2_zoom
	Button unzoomb,title="Unzoom",proc=plot2_zoom
End

Function plot2_zoom(cname) : ButtonControl
	String cname
	
	NVAR plot2zoom
	
	strswitch (cname)
		case "zoomb":
			switch (plot2zoom)
				case 0:
					SetAxis left -35,250
					SetAxis bottom -5,120
					plot2zoom = 1
					break
				case 1:
					SetAxis left -35,150
					SetAxis bottom -5,75
					plot2zoom = 2
					break
			endswitch
			
			break
			
		case "unzoomb":
			SetAxis/A
			plot2zoom = 0
			break
			
	endswitch
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

Function DrawPointMarker(graph, xpos, ypos, del)
	String graph					// graph name where to draw marker
	Variable xpos, ypos			// x and y positions (in image pixels) for marker
	Variable del					// delete old markers before drawing new one (0=no, 1=yes)
	Variable marker
	
	NVAR rowsize = :internalvars:FVRowSize
	
	DoWindow $graph
	if (V_flag == 0)
		// graph does not exist
		return -1
	endif
	
	SetDrawLayer/W=$graph ProgFront
	String lastLayer = S_name
	
	if (del == 1)
		// delete previous markers (and other drawings)
		DrawAction/W=$graph delete
	endif
	
	SetDrawEnv/W=$graph xcoord=prel, ycoord=prel, linethick=0, fillfgc=(65280,0,0)
	DrawRect/W=$graph (xpos+0.3)/rowsize, 1-(ypos+0.3)/rowsize,  (xpos+0.7)/rowsize, 1-(ypos+0.7)/rowsize
	
	SetDrawLayer/W=$graph $lastLayer
End
