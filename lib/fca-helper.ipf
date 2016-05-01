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

#pragma rtGlobals=3		// Use modern global access method.


// waves: StringList of wave names (";" as separator)
// from, to: average wave range [from, to] (both inclusive)
// wavg, wsd: waves for averaged values and standard deviations
Function AvgWaves(waves, from, to, wavg, wsd)
	String waves
	Variable from, to
	WAVE wavg, wsd
	
	if ((numpnts(wavg) < (to-from+1)) || (numpnts(wsd) < (to-from+1)))
		Print "Target wave is not big enough"
		return -1
	endif
	
	Variable i = 0
	String wname
	Make/O/WAVE/FREE wlist
	
	do
		wname = StringFromList(i, waves, ";")
		if (strlen(wname) == 0)
			break
		endif
		if (WaveExists($wname) == 0)
			break
		endif
		
		wlist[i] = $wname
		i += 1
		
	while (1)
	
	Variable wnum = i
	
	Print num2str(wnum) + " input waves"
	
	Variable j
	Variable k = 0
	Make/N=(wnum)/FREE wrow
	
	for (i=from; i <= to; i+=1)
		wrow = 0
		for (j=0; j < wnum; j+=1)
			WAVE w = wlist[j]
			wrow[j] = w[i]
		endfor
		WaveStats/Q wrow
		wavg[k] = V_avg
		wsd[k] = V_sdev
		k += 1
	endfor
	
	return 0
End


Function GetAllRampSizeUsed()
	
	WAVE/T fcmeta
	
	Variable numfc = numpnts(fcmeta)
	
	Make/O/N=(numfc) rampsizeused = NaN
	
	Variable i
	for (i=0; i < numfc; i += 1)
		rampsizeused[i] = NumberByKey("rampsizeUsed", fcmeta[i])
	endfor
End


Function AvgAllRampSizeUsed()
	WAVE/T fcmeta
	Variable numfc = numpnts(fcmeta)
	
	Variable avg = 0
	Variable i
	for (i=0; i < numfc; i += 1)
		avg += NumberByKey("rampsizeUsed", fcmeta[i])
	endfor
	return avg / numfc
End


Function findmax()
	Variable i = 0
	WAVE fc
	Variable pt = 4096
	for (i=0; i < 1024; i+=1)
		Duplicate/FREE/O/R=[][i] fc, w
		FindLevel/P/Q w, (w[0] + 1000)
		if (!V_flag)
			pt = min(pt, V_LevelX)
		endif
	endfor
	
	print "max pt: " + num2str(pt)
End


Function FitDeflSensAndMakeTSD(w, meta)
	WAVE w
	String meta
	
	NVAR/Z deflfit = $(NameOfWave(w) + "_deflfit")
	if (NVAR_Exists(deflfit))
		meta = ReplaceNumberByKey("deflSensUsed", meta, deflfit)
	else
		Variable/G $(NameOfWave(w) + "_deflfit")
		NVAR deflfit = $(NameOfWave(w) + "_deflfit")
	endif
	
	STRUCT FitDeflReturn ret
	ConvertForceToV(w, meta)
	FitDeflectionSensitivity(w, meta, $"", ret)
	deflfit = ret.deflsensfit
	
	w *= deflfit
	
	print "deflSensFit:", deflfit
	
	STRUCT CreateTSDReturn rettsd
	CreateTSDWave(w, $"", rettsd)
	
	Duplicate/O rettsd.tsd, $(NameOfWave(w) + "_xtsd")
	
	w *= 1000 * NumberByKey("springConst", meta)
	SetScale d 0,0,"pN", w
End

// check hardcoded values
Function rengraph()
	WAVE w = fc_z
	String suffix = "xsect"
	String g = StringFromList(0, FindGraphsWithWave(w))
	String name = MakeGraphName(suffix)
	DoWindow/C/W=$g $name
End

// check hardcoded values
Function killwin()
	WAVE w = brushheights_histo
	String g = StringFromList(0, FindGraphsWithWave(w))
	KillWindow $g
End

Function ConvTempRawToV(i)
	Variable i
	
	NVAR fcpoints = :internalvars:FCNumPoints
	
	Make/N=(fcpoints)/O wtemp
	
	WAVE fc
	WAVE/T fcmeta
	
	wtemp[] = fc[p][i]
	String h = fcmeta[i]
	
	ConvertRawToV(wtemp, h)
End

Function BinSizeFreedmanDiaconis(wname)
	String wname
	
	WaveStats/Q $wname
	StatsQuantiles/Q $wname
	
	return 2 * V_IQR / (V_npnts^(1/3))
End

Function BinSizeSuggestion(wname)
	String wname
	
	return BinSizeFreedmanDiaconis(wname)
End