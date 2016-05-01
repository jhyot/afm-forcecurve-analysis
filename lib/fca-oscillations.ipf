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

// Takes section between markers A and B and does linear baseline
// subtraction, and afterwards FFT on it.
Function MakeCurveFFT(wname)
	String wname		// name of wave from which to make FFT
						// FFT is saved in wname_fft
						// and the baseline subtracted wave in wname_linsub.
						// if empty, use first trace of top graph.
	
	if (strlen(wname) == 0)
		WAVE wtemp1 = WaveRefIndexed("", 0, 1)
		wname = WaveName("", 0, 1)
		WAVE wtemp2 = $wname
		if (!WaveRefsEqual(wtemp1, wtemp2))
			print "Couldn't select wave (correct datafolder?)"
			return -1
		endif
	endif
	
	
	
	WAVE w = $wname
	Duplicate/O w, $(wname + "_linsub")
	WAVE wtemp = $(wname + "_linsub")
	
	Redimension/N=(floor(pcsr(B)/2)*2 - floor(pcsr(A)/2)*2) wtemp
	wtemp[] = w[p+floor(pcsr(A)/2)*2]
	CurveFit/Q line, wtemp
	WAVE W_coef
	wtemp -= W_coef[0] + W_coef[1]*x
	
	FFT/MAGS/DEST=$(wname + "_fft") wtemp
End


// Measure oscillation frequency between two markers (A,B)
Function oscfreq(reswave, curve, rrate)
	String reswave		// results wave in root folder
	String curve			// curve wave (2D wave)
	Variable rrate			// ramp rate in Hz
	
	Variable makenew = 0
	WAVE/Z freqs = $("root:" + reswave)
	
	if (WaveExists(freqs))
		if (DimSize(freqs, 1) != 3)
			DoAlert 1, "Result wave has incorrect form, overwrite?"
			if (V_flag == 1)
				makenew = 1
			else
				Abort
			endif
		endif
	else
		makenew = 1
	endif
	
	if (makenew)
		Make/N=(100,3)/O $("root:" + reswave) = NaN
		WAVE freqs =  $("root:" + reswave)
	endif
	
	Wavestats/Q/M=1/R=[0,DimSize(freqs,0)-1] freqs
	Variable nextpt = V_npnts
	if (nextpt >= DimSize(freqs,0))
		// extend result wave because its full
		Redimension/N=(DimSize(freqs,0)+50) freqs
	endif
	
	
	MakeTempCurve("fctemp", curve, -1)
	
	MakeCurveFFT("fctemp")
	
	GetWindow kwTopWin, userdata
	Variable i = NumberByKey("index", S_Value)
	
	WAVE fctemp, fctemp_linsub, fctemp_fft
	WAVE/T fcmeta
	
	Wavestats/Q/M=1 fctemp_fft
	Variable osclength = 1/V_maxloc
	
	// osc. length in nm
	freqs[nextpt][0] = osclength
	// curve number
	freqs[nextpt][1] = i
	// osc freq in Hz
	freqs[nextpt][2] = 2.0 * rrate * NumberByKey("rampsize", fcmeta[i]) / osclength
	
	// display fft and curve, and results table
	DoWindow/F oscfftgra
	if (V_flag == 0)
		Display/L/B fctemp_fft
		AppendToGraph/T/R fctemp_linsub
		DoWindow/C oscfftgra
		
		ModifyGraph lsize(fctemp_fft)=1.5, rgb(fctemp_fft)=(0,0,0)
		SetAxis bottom 0,0.7
	else
		ReplaceWave/W=oscfftgra allinCDF
	endif
	
	DoWindow/F oscffttab
	if (V_flag == 0)
		Edit freqs
		DoWindow/C oscffttab
	endif
End


Function FilterOsc(rate)
	Variable rate		// ramp rate in Hz
	
	NVAR fcpoints = :internalvars:FCNumPoints
	NVAR numcurves = :internalvars:numCurves
	
	Variable samprate = rate * 2.0 * fcpoints
	
	Variable fir_center = 250	// Hz
	Variable fir_width = 300		// Hz
	Variable fir_eps = 1e-14
	Variable fir_nmult = 2
	
	Variable fir_center_frac = fir_center / samprate
	Variable fir_width_frac = fir_width / samprate
	
	WAVE fc, rfc, fc_x_tsd, rfc_x_tsd
	WAVE/T fcmeta
	Duplicate/O fc, fc_orig
	Duplicate/O rfc, rfc_orig
	Duplicate/O fc_x_tsd, fc_x_tsd_orig
	Duplicate/O rfc_x_tsd, rfc_x_tsd_orig
	
	Variable i
	Variable springc = 0
	for (i=0; i < numcurves; i+=1)
		Duplicate/FREE/O/R=[][i] fc, fctemp
		FilterFIR/NMF={fir_center_frac, fir_width_frac, fir_eps, fir_nmult} fctemp
		fc[][i] = fctemp[p]
		// recalc tip-sample dist
		Duplicate/FREE/O/R=[][i] fc, fctemp_xtsd
		springc = NumberByKey("springConst", fcmeta[i])
		fctemp /= springc * 1000
		fctemp_xtsd = NumberByKey("rampSize", fcmeta[i])/fcpoints * p
		fctemp_xtsd += fctemp
		fc_x_tsd[][i] = fctemp_xtsd[p]
		
		// retraction curve same thing
		Duplicate/FREE/O/R=[][i] rfc, fctemp
		FilterFIR/NMF={fir_center_frac, fir_width_frac, fir_eps, fir_nmult} fctemp
		rfc[][i] = fctemp[p]
		Duplicate/FREE/O/R=[][i] rfc, fctemp_xtsd
		fctemp /= springc * 1000
		fctemp_xtsd = NumberByKey("rampSize", fcmeta[i])/fcpoints * p
		fctemp_xtsd += fctemp
		rfc_x_tsd[][i] = fctemp_xtsd[p]
		
		
		Prog("Filtering", i, numcurves)
	endfor
	
End
