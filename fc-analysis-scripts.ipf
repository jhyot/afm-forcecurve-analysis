#pragma rtGlobals=3		// Use modern global access method.
//#pragma IndependentModule=ForceMapAnalysis  // disabled for easier debugging etc
SetIgorOption colorize,UserFuncsColorized=1


#include ":includes"


// SEE fc-script.config.ipf FOR USER CUSTOMIZABLE PARAMETERS




// TODO
// Make multiple 2d arrays possible in same datafolder (keep track of wave names etc instead of hardcoding)
// Make button in heightimage and heightmap for inspect mode (i.e. be able to turn off inspect mode)
// indicate flagged curves in review//
// Print analysis algorithm name and parameters when starting analysis
// rename analysis parameter constants to be absolutely clear from their names





// Internal constants, do not change
Constant SETTINGS_LOADFRIC = 1
Constant SETTINGS_LOADZSENS = 2



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
	"Show Height Results", MapToForeground()
	"-"
	Submenu "Review"
		"Flag Curves...", FlagCurves()
		"Mark Flagged", MarkFlaggedPixels()
		"-"
		"Review Flagged Curves", ReviewCurvesFlagged()
		"Review All Curves", ReviewCurvesAll()
		"-"
		"Classify Curves", ClassifyCurves()
		"Mark Classified", MarkClassifiedPixels()
		"Mark Classified and Excluded", MarkClassifiedAndExcludedPixels()
	End
	Submenu "Helper"
		"Brush Histogram", BrushHisto(1)
		"Subtract Baseline", SubtractBaseline()
		"Median Filter Image", MedianFilterMap()
	End
	"-"
	"Settings...", SetSettings(0)
End



Function IsDataLoaded()
	NVAR/Z isDataLoaded = :internalvars:isDataLoaded
	
	if (!NVAR_Exists(isDataLoaded) || isDataLoaded != 1)
		return 0
	else
		return 1
	endif
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
	
	NVAR/Z nodialogs = :internalvars:noDialogs
	if (!NVAR_Exists(nodialogs) || nodialogs == 0)
		Prompt fricStr, "Load Friction data?", popup, list
		Prompt zsensStr, "Load Z Sensor data?", popup, list
		DoPrompt "Set Settings", fricStr, zsensStr
		
		if (V_flag == 1)
			// User pressed cancel
			return -1
		endif
	endif
	
	Variable/G :internalvars:loadFriction = (cmpstr(fricStr, "Yes") == 0) ? 1 : 0
	Variable/G :internalvars:loadZSens = (cmpstr(zsensStr, "Yes") == 0) ? 1 : 0
	
	NVAR/Z isdataloaded = :internalvars:isDataLoaded
	if (!NVAR_Exists(isdataloaded))
		Variable/G :internalvars:isDataLoaded = 0
	endif
	
	NVAR/Z iszsensloaded = :internalvars:isZsensLoaded
	if (!NVAR_Exists(iszsensloaded))
		Variable/G :internalvars:isZsensLoaded = 0
	endif	
End


// Return -1 if user is in root and does not want to continue; 0 otherwise
Function CheckRoot()
	String df = GetDataFolder(0)
	if (cmpstr(df, "root") == 0)
		DoAlert 1, "You are in root data folder, this is not recommended.\rContinue anyway?"
		if (V_flag == 1)
			return 0
		endif
	endif
	
	return -1
End



// Progress bar code

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