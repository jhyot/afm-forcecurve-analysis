#pragma rtGlobals=1		// Use modern global access method.

#include ":fc-analysis-scripts"

Function absrelheights(img, bheights, added, nobrushrel, nobrushabs)
	String img, bheights, added, nobrushrel, nobrushabs

	// Create "absolute brush heights" wave
	WAVE imgw = $img
	WAVE bheightsw = $bheights
	Duplicate/O imgw, $added
	WAVE addedw = $added
	addedw += bheightsw
	
	// Display "absolute brush heights" image graph
	Display
	Appendimage addedw
	ModifyImage $added ctab={*,*,Gold,0}
	ModifyGraph width=300,height=300, margin(right)=90
	ColorScale/C/N=scale/F=0/A=RC/X=-28 image=$added, "absolute brush height (nm)"
	PutDFNameOnGraph()
	DoUpdate
	
	scatterplots(img, bheights, added, nobrushrel, nobrushabs)
End


Function scatterplots(img, bheights, added, nobrushrel, nobrushabs)
	String img, bheights, added, nobrushrel, nobrushabs
	
	WAVE imgw = $img
	WAVE bheightsw = $bheights
	WAVE addedw = $added
	
	// Create relative "zero brush height" line (y = -x)
	Make/N=10/O $nobrushrel
	WAVE nobrushrelw = $nobrushrel
	WaveStats/Q imgw
	SetScale/I x, V_min, V_max, nobrushrelw
	nobrushrelw = -x
	
	// Display scatterplot relative brush heights
	Display bheightsw vs imgw
	ModifyGraph marker=19,msize=1.5,rgb=(0,0,0),mode=3
	AppendToGraph nobrushrelw
	SetAxis/A
	SetAxis/A/E=1 left
	ModifyGraph standoff(bottom)=0,zero(left)=1
	Label left "brush height (nm)"
	Label bottom "feature depth (nm)"
	Tag/C/N=surface/AO=1/X=0/Y=-5/B=1/G=(65280,0,0)/F=0/L=0 $nobrushrel, ((V_min+V_max)/2), "gold surface"
	PutDFNameOnGraph()
	DoUpdate
	
	// Create absolute "zero brush height" line (y=x)
	Make/N=10/O $nobrushabs
	WAVE nobrushabsw = $nobrushabs
	SetScale/I x, V_min, V_max, nobrushabsw
	nobrushabsw = x
	
	// Display scatterplot absolute brush heights
	Display addedw vs imgw
	ModifyGraph marker=19,msize=1.5,rgb=(0,0,0),mode=3
	AppendToGraph nobrushabsw
	SetAxis/A
	ModifyGraph standoff(bottom)=0
	Label left "absolute brush height (nm)\r(feature depth + brush height)"
	Label bottom "feature depth (nm)"
	ModifyGraph lblMargin(left)=10
	ModifyGraph zero=1
	Tag/C/N=hardwall/AO=1/X=0/Y=-5/B=1/G=(65280,0,0)/F=0/L=0 $nobrushabs, ((V_min+V_max)/2), "hardwall"
	Tag/C/N=surface/O=0/X=7/Y=.5/B=1/G=(0,0,0)/F=0/L=0 left, 0, "gold surface"
	PutDFNameOnGraph()
	DoUpdate
End

Function plot_color(hole, edge, top, textpos)
	Variable hole, edge, top		// X coords where the region ends (upper edge)
	Variable textpos					// Where region text gets placed vertically (y-axis value)
	
	// Draw colors on background
	SetDrawLayer/K UserBack
	SetDrawEnv save, xcoord=bottom, ycoord=prel, linethick=0, fillpat=1
	
	GetAxis/Q bottom
	Variable brange = V_max - V_min
	
	// hole region, light blue color
	SetDrawEnv fillfgc=(48896,52992,65280)
	DrawRect V_min, 0, hole, 1
	
	// edge region, light orange color
	SetDrawEnv fillfgc=(65280,59904,48896)
	DrawRect hole, 0, edge, 1
	
	// top region, light green color
	SetDrawEnv fillfgc=(57344,65280,48896)
	DrawRect edge, 0, top, 1
	
	// Put text above regions
	SetDrawEnv save, fstyle=1, ycoord=left, xcoord=bottom
	SetDrawEnv textrgb=(0,0,65280)
	DrawText ((V_min+hole)/2)-0.04*brange, textpos, "hole"
	SetDrawEnv textrgb=(52224,34816,0)
	DrawText ((hole+edge)/2)-0.05*brange, textpos, "edge"
	SetDrawEnv textrgb=(0,26112,13056)
	DrawText ((edge+top)/2)-0.07*brange, textpos, "surface"
End


// Automatically selects regions to color
// Find lower bound of surface ("edge") by fitting gaussian to normalized histogram
// and defining the surface where the density drops below .05
// Upper bound of surface ("top") is max depth value
// Upper bound of hole ("hole") is 60% from min depth value to "edge"
Function plot_color_auto(textpos)
	Variable textpos			// Where region text gets placed vertically (y-axis value)
	
	Variable fracHole = .6
	Variable densityLimit = .05
	Variable binSize = .5
	Variable histLimitForFit = .1
	Variable histLimitFitted = .05
	
	WAVE/Z depths = WaveRefIndexed("", 0, 2)
	
	if (WaveExists(depths) == 0)
		print "Error: No X wave found in top graph"
		return -1
	endif
	
	WaveStats/Q depths
	
	// ceil to next 0.5 step
	Variable top = ceil(V_max*2)/2
	
	Variable depthmin = V_min
	
	Variable bins = ceil((V_max - V_min)/binSize + 5)	
	Make/FREE/N=(bins) hist
	Histogram/P/C/B={V_min - 1, binSize, bins} depths, hist
	
	WaveStats/Q hist
	FindLevel/EDGE=1/P/R=[V_maxRowLoc,0]/Q hist, histLimitForFit
	if (V_flag != 0)
		print "Error: Histogram could not be fit"
		return -1
	endif
	
	CurveFit/Q gauss, hist[ceil(V_LevelX),]
	WAVE W_coef
	Variable f_y0 = W_coef[0]
	Variable f_A = W_coef[1]
	Variable f_x0 = W_coef[2]
	Variable f_s = W_coef[3]
	Variable f_y = histLimitFitted
	
	// Invert gauss function to get x value for given y
	Variable f_x = f_x0 - f_s * sqrt(ln(f_A/(f_y - f_y0)))
	
	// round to closest 0.5
	Variable edge = round(f_x*2) / 2
	
	Variable hole = depthmin + (edge - depthmin) * fracHole
	hole = round(hole*2) / 2
	
	printf "hole: %g,  edge: %g,  top: %g\r", hole, edge, top
	
	plot_color(hole, edge, top, textpos)
	
End


// Lists are in format: "new combined wave; old wave1; old wave2;..."
Function absrelheights_combine(imglist, bheightlist, absheightlist, nobrushrel, nobrushabs)
	String imglist, bheightlist, absheightlist, nobrushrel, nobrushabs
	
	Variable numimg = ItemsInList(imglist)
	Variable numbheight = ItemsInList(bheightlist)
	Variable numabsheight = ItemsInList(absheightlist)
	
	if ((numimg != numbheight) || (numimg != numabsheight))
		print "ERROR: non-matching list lenghts"
		return -1
	endif
	
	String newimg = StringFromList(0, imglist)
	imglist = RemoveListItem(0, imglist)
	
	String newbheight = StringFromList(0, bheightlist)
	bheightlist = RemoveListItem(0, bheightlist)
	
	String newabsheight = StringFromList(0, absheightlist)
	absheightlist = RemoveListItem(0, absheightlist)
	
	
	// Concatenate old to new waves
	Concatenate/O imglist, $newimg
	Redimension/N=(numpnts($newimg)) $newimg
	
	Concatenate/O/NP bheightlist, $newbheight
	
	Concatenate/O absheightlist, $newabsheight
	Redimension/N=(numpnts($newabsheight)) $newabsheight
	
	
	scatterplots(newimg, newbheight, newabsheight, nobrushrel, nobrushabs)
End


Function filterbydepth(from, to, depth, input, output)
	Variable from, to		// Depth values to include in filtered output (inclusive)
	String depth				// Input depth wave name
	String input				// Input height wave name
	String output			// Output height wave name (will be created/overwritten, same size as input wave	
								// with NaN for excluded points
	
	WAVE d = $depth
	WAVE i = $input
	
	Duplicate/O i, $output
	WAVE o  = $output
	o = NaN
	
	Variable j
	for (j=0; j < numpnts(i); j+=1)
		if ((d[j] >= from) && (d[j] <= to))
			o[j] = i[j]
		endif
	endfor	
End