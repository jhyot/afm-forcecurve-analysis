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


Proc fvmaps_plain() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z margin(right)=150,width=300,height=300
	ModifyGraph/Z mirror=2
	ModifyGraph/Z nticks=0
	ModifyGraph/Z standoff=0
	ColorScale/C/N=scale side=2,frame=1.50,fsize=14,tickLen=5.00,tickThick=2.00
EndMacro


Proc loadingrate_means_export() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z mode=4
	ModifyGraph/Z marker[0]=16,marker[1]=19
	ModifyGraph/Z lSize=2
	ModifyGraph/Z rgb[1]=(0,0,65280)
	ModifyGraph/Z msize=3
	ModifyGraph/Z mirror(left)=3,mirror(bottom)=2
	ModifyGraph/Z nticks(left)=6
	ModifyGraph/Z minor(left)=1
	ModifyGraph/Z sep=10
	ModifyGraph/Z fSize=14
	ModifyGraph/Z lblMargin(left)=4,lblMargin(bottom)=3
	ModifyGraph/Z standoff=0
	ModifyGraph/Z standoff(left)=1
	SetAxis/Z bottom 0,30
	ModifyGraph tick=2
	ModifyGraph minor=1,sep(bottom)=20,manTick(left)={0,4,0,0},manMinor(left)={1,50};DelayUpdate
	ModifyGraph manTick(bottom)={0,5,0,0},manMinor(bottom)={1,50}
EndMacro


Proc loadingrate_histograms_export() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z mode[5]=3,mode[6]=3,mode[7]=3,mode[8]=3,mode[9]=3
	ModifyGraph/Z marker[5]=16,marker[6]=19,marker[7]=17,marker[8]=23,marker[9]=18
	ModifyGraph/Z lSize[0]=2,lSize[1]=2,lSize[2]=2,lSize[3]=2,lSize[4]=2
	ModifyGraph/Z rgb[0]=(65280,32768,58880),rgb[1]=(32768,40704,65280),rgb[2]=(65280,32512,16384)
	ModifyGraph/Z rgb[3]=(0,52224,26368),rgb[4]=(52224,52224,0),rgb[5]=(65280,32768,58880)
	ModifyGraph/Z rgb[6]=(32768,40704,65280),rgb[7]=(65280,32512,16384),rgb[8]=(0,52224,26368)
	ModifyGraph/Z rgb[9]=(52224,52224,0)
	ModifyGraph/Z msize[5]=2,msize[6]=2,msize[7]=2,msize[8]=2,msize[9]=2
	ModifyGraph/Z hbFill[0]=2,hbFill[1]=2,hbFill[2]=2,hbFill[3]=2,hbFill[4]=2
	ModifyGraph/Z useBarStrokeRGB[0]=1,useBarStrokeRGB[1]=1,useBarStrokeRGB[2]=1,useBarStrokeRGB[3]=1
	ModifyGraph/Z useBarStrokeRGB[4]=1
	ModifyGraph/Z mirror=2
	ModifyGraph/Z nticks(left)=3
	ModifyGraph/Z minor(bottom)=1
	ModifyGraph/Z sep(bottom)=10
	ModifyGraph/Z fSize=14
	ModifyGraph/Z lowTrip(left)=0.01
	ModifyGraph/Z standoff=0
	Label/Z left "frequency"
EndMacro


Proc brushhisto_export() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z mode[0]=5
	ModifyGraph/Z lSize[1]=2,lSize[2]=2
	ModifyGraph/Z rgb[1]=(0,0,0),rgb[2]=(0,0,0)
	ModifyGraph/Z hbFill[0]=2
	ModifyGraph/Z useBarStrokeRGB[0]=1
	ModifyGraph/Z mirror=2
	ModifyGraph/Z nticks(left)=3
	ModifyGraph/Z minor(bottom)=1
	ModifyGraph/Z fSize=14
	ModifyGraph/Z lowTrip(left)=1e-05
	ModifyGraph/Z standoff=0
	Label/Z left "normalized frequency"
	Label/Z bottom "brush height (nm)"
	SetAxis/Z left 0,0.09
	SetAxis/Z bottom -2,45
EndMacro

Proc fcurve_export() : GraphStyle
	PauseUpdate; Silent 1		// modifying window...
	ModifyGraph/Z mode=3
	ModifyGraph/Z marker=19
	ModifyGraph/Z rgb[0]=(0,0,0),rgb[1]=(0,15872,65280)
	ModifyGraph/Z msize=1
	ModifyGraph/Z zero=1
	ModifyGraph/Z mirror=2
	ModifyGraph/Z minor=1
	ModifyGraph/Z fSize=14
	ModifyGraph/Z standoff=0
	Label/Z left "force (pN)"
	Label/Z bottom "tip-sample distance (nm)"
	SetAxis/Z left -40,500
	SetAxis/Z bottom -2,60
EndMacro



