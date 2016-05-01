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

Function PrintInfo()
	String ig = StrVarOrDefault(":internalvars:imagegraph", "")
	String iw = StrVarOrDefault(":internalvars:imagewave", "")
	String rg = StrVarOrDefault(":internalvars:resultgraph", "")
	String rw = StrVarOrDefault(":internalvars:resultwave", "")
	String sel = StrVarOrDefault(":internalvars:selectionwave", "")
	String path = StrVarOrDefault(":internalvars:totalpath", "")
	String params = StrVarOrDefault(":internalvars:analysisparameters", "")
	print "IMAGE graph: " + ig + ",  wave: " + iw
	print "BRUSHHEIGHTS graph: " + rg + ",  wave: " + rw
	print "selectionwave: " + sel + ",  totalpath: " + path
	print "analysis parameters: " + params
End

Function PrintInfoDF(df)
	String df		// data folder (without 'root:' part) to print info from
	String fullDF = "root:" + df
	DFREF prevDF = GetDataFolderDFR()
	SetDataFolder fulldf
	PrintInfo()
	SetDataFolder prevDF
End

// Shows parameters from different possible sources:
// analysis params, fc metadata
Function PrintParams(params, idx)
	String params		// semicolon-separated list of parameters
	Variable idx
	
	SVAR/Z aparams = :internalvars:analysisparameters
	if (!SVAR_Exists(aparams))
		aparams = ""
	endif
	
	WAVE/Z/T fcmeta
	
	Variable i
	String currparam = ""
	String currres = ""
	String out = ""
	for (i=0; i < ItemsInList(params); i+=1)
		out += "\r"
		currparam = StringFromList(i, params)
		currres = StringByKey(currparam, aparams)
		
		if (strlen(currres) > 0)
			out += currparam + "[analysis]: " + currres
			continue
		endif
		
		if (WAVEExists(fcmeta) && idx >= 0)
			currres = StringByKey(currparam, fcmeta[idx])
		endif
		
		if (strlen(currres) > 0)
			out += currparam + "[" + num2str(idx) + "]: " + currres
			continue
		endif	
	endfor
	
	print out	
End
