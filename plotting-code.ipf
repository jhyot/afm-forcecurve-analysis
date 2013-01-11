#pragma rtGlobals=1		// Use modern global access method.


// Displays new graph with topography image
Function ShowImage()
	String/G imagewave
	Display/W=(30,55,30+387,55+358)
	AppendImage $imagewave

	String/G imagegraph=S_name

	ModifyImage $imagewave ctab={*,*,Gold,0}
	ModifyGraph width=300,height=300
	
	PutDFNameOnGraph()

	DoUpdate
	
	return 0
End


// Displays new graph with topography image
Function ShowResultMap()
	String/G resultwave

	Display/W=(30+430,55,30+387+430,55+358)
	AppendImage $resultwave
	
	String/G resultgraph=S_name
	
	// Scale range between 0 and 99th percentile of heights (ignore extreme outliers)
	WAVE brushheights
	Duplicate/O brushheights, brushheights_sort
	Sort brushheights_sort, brushheights_sort
	WaveStats/Q brushheights_sort
	Variable upper = brushheights_sort[(V_npnts-1)*.99]
	// Round to upper decade
	upper = 10*ceil(upper/10)
	
	ModifyImage $resultwave ctab={0,upper,Gold,0}, minRGB=(46592,51712,63488), maxRGB=(29440,0,58880)
	
	ColorScale/C/N=text0/F=0/A=RC/E image=$resultwave
	ModifyGraph width=300, height=300
	
	PutDFNameOnGraph()
	
	DoUpdate
	
	return 0	
End


Function PlotFC(index)
	Variable index
	
	WAVE fc, fc_x_tsd, fc_expfit, fc_smth, fc_smth_xtsd
	
	Display/K=1 fc[][index] vs fc_x_tsd[][index]

	if (fc_expfit[0][index])
		AppendToGraph/W=$S_name fc_expfit[][index]
	elseif (fc_smth[0][index])
		AppendToGraph/W=$S_name fc_smth[][index] vs fc_smth_xtsd[][index]
	endif
	
	ModifyGraph rgb[0]=(0,15872,65280)
	ModifyGraph rgb[1]=(65280,0,0)
	

	ModifyGraph nticks(bottom)=10,minor(bottom)=1,sep=10,fSize=12,tickUnit=1
	Label left "\\Z13force (pN)"
	Label bottom "\\Z13tip-sample distance (nm)"
	SetAxis left -25,250
	SetAxis bottom -5,120
	ModifyGraph zero=8
	
	WAVE brushheights
	
	String text, text2
	text = "FC: " + num2str(index) + ";   X: " + num2str(mod(index,ksFVRowSize))
	text += "; Y:" + num2str(floor(index/ksFVRowSize))
	sprintf text2, "\rBrush height: %.2f nm", brushheights[index]
	TextBox/A=RT (text + text2)
	
	// Draw drop-line at brush height
	if (brushheights[index])
		SetDrawEnv xcoord=bottom, ycoord=prel, dash=11
		DrawLine brushheights[index],0.3, brushheights[index],1.05
	endif
	
	ShowInfo
	
	// Put curve index into window userdata
	SetWindow kwTopWin, userdata=num2str(index)
	
	
	Variable/G plotFCzoom = 1
	
	ControlBar/T 30
	
	// Zoom buttons
	Button zoomb,title="Zoom",proc=PlotFC_zoom
	Button unzoomb,title="Unzoom",proc=plotFC_zoom
	
	// Buttons for showing and hiding curves
	// Save in userdata whether curve is shown at the moment
	Button showapproach,title="Hide approach",size={80,20},userdata="1",proc=PlotFC_showcurves
	Button showretract,title="Show retract",size={80,20},userdata="0",proc=PlotFC_showcurves
End

Function PlotFC_zoom(cname) : ButtonControl
	String cname
	
	NVAR plotFCzoom
	
	strswitch (cname)
		case "zoomb":
			plotFCzoom = (plotFCzoom==0 ? 1 : 2)
			break
			
		case "unzoomb":
			plotFCzoom = 0
			break
	endswitch
	
	PlotFC_setzoom(plotFCzoom)
	
End


Function PlotFC_showcurves(cname) : ButtonControl
	String cname
	
	ControlInfo $cname
	
	// Get fc number
	GetWindow kwTopWin, userdata
	Variable index = str2num(S_Value)
	
	if (numtype(index) != 0)
		// Not a normal number, do nothing, since we don't know what curve we have
		return -1
	endif
	
	Variable trace
	
	strswitch (cname)
		case "showapproach":
			if (str2num(S_UserData) == 1)
				// Hide approach graph
					RemoveFromGraph/Z fc, fc_smth, fc_expfit
					Button showapproach,title="Show approach",userdata="0"
			else
				// Show approach graph
					AppendToGraph fc[][index] vs fc_x_tsd[][index]
					AppendToGraph fc_smth[][index] vs fc_smth_xtsd[][index]
					
					trace = ItemsInList(TraceNameList("", ";", 1)) - 2
					ModifyGraph rgb[trace]=(0,15872,65280)
					ModifyGraph rgb[trace+1]=(65280,0,0)
					
					Button showapproach,title="Hide approach",userdata="1"
			endif
			break
		
		case "showretract":
			if (str2num(S_UserData) == 1)
				// Hide retract graph
					RemoveFromGraph/Z rfc
					Button showretract,title="Show retract",userdata="0"
			else
				// Show retract graph
					AppendToGraph rfc[][index] vs rfc_x_tsd[][index]
					
					trace = ItemsInList(TraceNameList("", ";", 1)) - 1
					ModifyGraph rgb[trace]=(0,52224,0)
					
					Button showretract,title="Hide retract",userdata="1"
			endif
			break
			
	endswitch
End


Function PlotFC_setzoom(level)
	Variable level
	
	switch (level)
		case 0:
			SetAxis/A
			break
		case 1:
			SetAxis left -35,250
			SetAxis bottom -5,120
			break
		case 2:
			SetAxis left -35,150
			SetAxis bottom -5,75
			break
	endswitch
End

Function PutDFNameOnGraph()
	String df = GetDataFolder(0)
	TextBox/C/N=dfname/F=0/A=LB/X=.5/Y=.1/E=2 df
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
	
	String text, text2
	text = "FC: " + num2str(idx) + ";   X: " + num2str(mod(idx,ksFVRowSize))
	text += "; Y:" + num2str(floor(idx/ksFVRowSize))
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