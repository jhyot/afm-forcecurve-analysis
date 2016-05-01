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

// Returns name of backup wave
Function/S SaveBackupWave(orig, suffix)
	String orig		// original wave to be backed up (in current folder)
	String suffix	// name for backed up wave with <orig>_<suffix> (automatically in backups subfolder)
	
	WAVE w = $orig
	
	NewDataFolder/O backups
	String backname = NameOfWave(w) + "_" + suffix
	Duplicate/O w, :backups:$backname
	
	return "backups:" + backname
End


Function RestoreBackupWave(orig, suffix)
	String orig		// orig wave name, will be restored into
	String suffix	// suffix in backup folder
	
	String backupname = orig + "_" + suffix
	
	WAVE/Z backupw = :backups:$backupname
	
	if (!WaveExists(backupw))
		print "Backup wave not found: " + backupname
		return -1
	endif
	
	Duplicate/O backupw, $orig
End

Function MakeTempCurve(name, orig, idx)
	String name		// name of duplicated temp wave
	String orig		// original wave (2D)
	Variable idx		// curve index to duplicate; -1 if taken from graph
	
	if (idx < 0)
		GetWindow kwTopWin, userdata
		idx = NumberByKey("index", S_Value)
	endif
	
	
	WAVE fc = $orig
	
	WAVE/T fcmeta
	
	Duplicate/O/R=[][idx] fc, $name
	WAVE dup = $name
	Redimension/N=(numpnts(dup)) dup
	Note dup, "orig:" + num2str(idx)
	print idx
End


// Function by Jon Tischler
// TischlerJZ at ornl.gov
// http://www.wavemetrics.com/search/viewmlid.php?mid=23626
Function/S FindGraphsWithWave(w) // find the graph windows which contain the specified wave, returns a list of graph names
	Wave w
	if (!WaveExists(w))
		return ""
	endif
	String name0=GetWavesDataFolder(w,2), out=""
	String win,wlist = WinList("*",";","WIN:1"), clist, cwin
	Variable i,m,Nm=ItemsInList(wlist)
	for (m=0;m<Nm;m+=1)
		win = StringFromList(m,wlist)
		CheckDisplayed/W=$win w
		if (V_flag>0)
			out += win+";"
		else
			clist = ChildWindowList(win)
			for (i=0;i<ItemsInLIst(clist);i+=1)
				cwin = StringFromList(i,clist)
				CheckDisplayed/W=$(win+"#"+cwin) w
				if (V_flag>0)
					out += win+"#"+cwin+";"
					break
				endif
			endfor
		endif
	endfor
	return out
End