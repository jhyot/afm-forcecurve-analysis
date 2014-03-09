#pragma rtGlobals=3		// Use modern global access method and strict wave access.


Proc histocolors() : GraphStyle
	//Variable binsize = .1
	//Variable offsetlen = binsize/10
	
	String trace = StringFromList(0, TraceNameList("", ";", 1))
	Variable binsize = DimDelta(TraceNameToWaveRef("", trace), 0)
	Variable offsetlen = binsize/25
	
	//GetAxis/Q bottom
	//Variable offsetlen = (V_max - V_min) / 350
	
	PauseUpdate; Silent 1		// modifying window...
	
	ModifyGraph/Z mode=6, hbFill=2, useBarStrokeRGB=1, lSize=2

	ModifyGraph/Z rgb[0]=(65280,32768,58880),rgb[1]=(32768,40704,65280)
	ModifyGraph/Z rgb[2]=(65280,32512,16384)
	ModifyGraph/Z rgb[3]=(0,52224,26368),rgb[4]=(52224,52224,0)
	ModifyGraph/Z rgb[5]=(65280,65280,32768),rgb[6]=(65280,49152,16384)

	ModifyGraph/Z offset[0]={-1*offsetlen,0},offset[1]={1*offsetlen,0}
	ModifyGraph/Z offset[3]={-2*offsetlen,0},offset[4]={2*offsetlen,0}
	ModifyGraph/Z offset[5]={-3*offsetlen,0},offset[6]={3*offsetlen,0}

	Label/Z left "probability density"
	//Label/Z bottom "defl. sens. (nm/V)"

	//SetAxis/Z bottom 4,7
	
	//Legend/C/N=text0/J/A=MC/X=44.26/Y=35.79 "\\s(brushheights_histo) 29.3\r\\s(brushheights_histo#1) 9.8\r\\s(brushheights_histo#2) 3.4\r\\s(brushheights_histo#3) 1.0"
	//AppendText "\\s(brushheights_histo#4) 1.0 ZCL"
	//TextBox/C/N=text1/A=MC/X=-31.78/Y=43.51 "Brush height ; Full dataset"
EndMacro


Proc scattercolors() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z mode=3
	ModifyGraph/Z marker[0]=19,marker[1]=19,marker[2]=19,marker[3]=19,marker[4]=19,marker[5]=16
	ModifyGraph/Z marker[6]=16
	ModifyGraph/Z rgb[0]=(65280,32768,58880),rgb[1]=(32768,40704,65280)
	ModifyGraph/Z rgb[2]=(65280,32512,16384),rgb[3]=(0,52224,26368)
	ModifyGraph/Z rgb[4]=(52224,52224,0),rgb[5]=(0,52224,26368)
	ModifyGraph/Z rgb[6]=(49152,65280,32768)
	ModifyGraph/Z useMrkStrokeRGB[5]=1,useMrkStrokeRGB[6]=1
	//SetAxis/Z left 8,14
EndMacro



Proc ratecolors() : GraphStyle
	ModifyGraph/Z hbFill=2, useBarStrokeRGB=1, lSize=2

	ModifyGraph/Z rgb[0]=(65280,32768,58880),rgb[1]=(32768,40704,65280)
	ModifyGraph/Z rgb[2]=(65280,32512,16384)
	ModifyGraph/Z rgb[3]=(0,52224,26368),rgb[4]=(52224,52224,0)
	ModifyGraph/Z rgb[5]=(65280,65280,32768),rgb[6]=(65280,49152,16384)
EndMacro



Proc escapefraction_histo() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z mode=5
	ModifyGraph/Z rgb=(0,0,65280)
	ModifyGraph/Z hbFill=2
	ModifyGraph/Z useBarStrokeRGB=1
	ModifyGraph/Z fSize=14
	ModifyGraph/Z standoff=0
	ModifyGraph/Z lblLatPos(left)=8
	ModifyGraph/Z tickUnit(bottom)=1
	Label/Z left "fraction of curves with escape"
	Label/Z bottom "distance from ring center (nm)"
	SetAxis/Z/E=1 left 0,0.6
	SetAxis/Z bottom 0,300
EndMacro

