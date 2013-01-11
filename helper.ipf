#pragma rtGlobals=1		// Use modern global access method.


Function scatterplots(img, bheights, added, nobrushrel, nobrushabs)
	String img, bheights, added, nobrushrel, nobrushabs

	WAVE imgw = $img
	WAVE bheightsw = $bheights
	
	Duplicate/O imgw, $added
	
	WAVE addedw = $added
	
	addedw += bheightsw
	
	Display
	Appendimage addedw
	ModifyImage $added ctab={*,*,Gold,0}
	ModifyGraph width=300,height=300, margin(right)=65
	ColorScale/C/N=text0/F=0/A=RC/X=-20 image=$added
	PutDFNameOnGraph()
	DoUpdate
	
	
	Make/N=10/O $nobrushrel
	WAVE nobrushrelw = $nobrushrel
	WaveStats/Q imgw
	SetScale/I x, V_min, V_max, nobrushrelw
	nobrushrelw = -x
	
	Display bheightsw vs imgw
	ModifyGraph marker=19,msize=1.5,rgb=(0,0,0),mode=3
	AppendToGraph nobrushrelw
	SetAxis/A
	SetAxis/A/E=1 left
	Label left "brush height"
	Label bottom "feature depth"
	PutDFNameOnGraph()
	DoUpdate
	
	
	Make/N=10/O $nobrushabs
	WAVE nobrushabsw = $nobrushabs
	SetScale/I x, V_min, V_max, nobrushabsw
	nobrushabsw = x
	
	Display addedw vs imgw
	ModifyGraph marker=19,msize=1.5,rgb=(0,0,0),mode=3
	AppendToGraph nobrushabsw
	SetAxis/A
	Label left "absolute brush height\r(feature depth + brush height)"
	Label bottom "feature depth"
	ModifyGraph lblMargin(left)=10
	ModifyGraph zero=1
	PutDFNameOnGraph()
	DoUpdate
End