#pragma rtGlobals=3		// Use modern global access method and strict wave access.

Function hertz(w,h) : FitFunc
	Wave w
	Variable h

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(h) = 4/3 * 1/(1-n^2) * E * sqrt(R) * (h/1e9 - h0/1e9)^(3/2) * 1e12 + F0
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ h
	//CurveFitDialog/ Coefficients 5
	//CurveFitDialog/ w[0] = n
	//CurveFitDialog/ w[1] = E
	//CurveFitDialog/ w[2] = R
	//CurveFitDialog/ w[3] = h0
	//CurveFitDialog/ w[4] = F0
	
	if (h > w[3])
		h = w[3]
	endif
	
	return 4/3 * 1/(1-w[0]^2) * w[1] * sqrt(w[2]) * (w[3]/1e9 - h/1e9)^(3/2) * 1e12 + w[4]
End

Function twohertz(w,h) : FitFunc
	Wave w
	Variable h

	//hertz: F(h) = 4/3 * 1/(1-n^2) * sqrt(R) * E * (h0 - h)^(3/2) + F0
	//w[0] = n
	//w[1] = E1
	//w[2] = R
	//w[3] = h01
	//w[4] = F01
	//w[5] = E2
	//w[6] = h02
	//w[7] = F02
	
	Variable res = 4/3 * 1/(1-w[0]^2) * sqrt(w[2])
	if (h > w[6])
		// region 1
		if (h > w[3])
			h = w[3]
		endif
		res = res * w[1] * (w[3]/1e9 - h/1e9)^(3/2) * 1e12 + w[4]
	else
		// region 2
		res = res * w[5] * (w[6]/1e9 - h/1e9)^(3/2) * 1e12 + w[7]
	endif
	
	return res
End

Function hertz_m(w,h) : FitFunc
	Wave w
	Variable h

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(h) = 4/3 * 1/(1-n^2) * E * sqrt(R) * (h/1e9 - h0/1e9)^m * 1e12 + F0
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ h
	//CurveFitDialog/ Coefficients 6
	//CurveFitDialog/ w[0] = n
	//CurveFitDialog/ w[1] = E
	//CurveFitDialog/ w[2] = R
	//CurveFitDialog/ w[3] = m
	//CurveFitDialog/ w[4] = h0
	//CurveFitDialog/ w[5] = F0

	return 4/3 * 1/(1-w[0]^2) * w[1] * sqrt(w[2]) * (h/1e9 - w[4]/1e9)^w[3] * 1e12 + w[5]
End

Function power_Xoffset(w,x) : FitFunc
	Wave w
	Variable x

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(x) = y0 + A*(x-x0)^m
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ x
	//CurveFitDialog/ Coefficients 4
	//CurveFitDialog/ w[0] = A
	//CurveFitDialog/ w[1] = m
	//CurveFitDialog/ w[2] = x0
	//CurveFitDialog/ w[3] = y0

	return w[3] + w[0]*(x-w[2])^w[1]
End

Function expheight_lim(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = R*1e-9 * 100 * Pi * d*1e-9 / ((s*1e-9)^3) * 1.38e-23 * T * exp(-2 * Pi * d / L) * 1e12
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 4
	//CurveFitDialog/ w[0] = L
	//CurveFitDialog/ w[1] = s
	//CurveFitDialog/ w[2] = R
	//CurveFitDialog/ w[3] = T
	
	// comment on formula: does not seem correct;
	// has applied Langbein approximation for van der Waals forces
	// but questionable whether this is the correct approximation here.

	return w[2]*1e-9 * 100 * Pi * d*1e-9 / ((w[1]*1e-9)^3) * 1.38e-23 * w[3] * exp(-2 * Pi * d / w[0]) * 1e12
End

Function expheight_butt(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = R*1e-9 * 50 * L*1e-9 / ((s*1e-9)^3) * 1.38e-23 * T * exp(-2 * Pi * d / L) * 1e12
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 4
	//CurveFitDialog/ w[0] = R
	//CurveFitDialog/ w[1] = L
	//CurveFitDialog/ w[2] = s
	//CurveFitDialog/ w[3] = T

	return w[0]*1e-9 * 50 * w[1]*1e-9 / ((w[2]*1e-9)^3) * 1.38e-23 * w[3] * exp(-2 * Pi * d / w[1]) * 1e12
End

Function expheight_general(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = A * d * exp(-1 * d / L)
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 2
	//CurveFitDialog/ w[0] = A
	//CurveFitDialog/ w[1] = L

	return w[0] * d * exp(-1 * d / w[1])
End

Function expheight_limshort(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = A * exp(-2 * Pi * d / L)
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 2
	//CurveFitDialog/ w[0] = A
	//CurveFitDialog/ w[1] = L

	return w[0] * exp(-2 * Pi * d / w[1])
End

Function brushheight_alex_derj(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = 8*Pi/35 * R*1e-9 * 1.38e-23 * T * L*1e-9 / (s*1e-9)^3 * ( -12 + 7*(L/d)^(5/4) + 5*(d/L)^(7/4) ) * 1e12
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 4
	//CurveFitDialog/ w[0] = R
	//CurveFitDialog/ w[1] = T
	//CurveFitDialog/ w[2] = L
	//CurveFitDialog/ w[3] = s

	Variable ret
	
	if (d < 0)
		d = 1e-3
	endif
	
	return 8*Pi/35 * w[0]*1e-9 * 1.38e-23 * w[1] * w[2]*1e-9 / (w[3]*1e-9)^3 * ( -12 + 7*(w[2]/d)^(5/4) + 5*(d/w[2])^(7/4) ) * 1e12
End


Function brushheight_alex_derj_FR(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = 8*Pi/35 * 1.38e-23 * T * L*1e-9 / (s*1e-9)^3 * ( -12 + 7*(L/d)^(5/4) + 5*(d/L)^(7/4) ) * 1e12 * 1e-9
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 3
	//CurveFitDialog/ w[0] = T
	//CurveFitDialog/ w[1] = L
	//CurveFitDialog/ w[2] = s

	return 8*Pi/35 * 1.38e-23 * w[0] * w[1]*1e-9 / (w[2]*1e-9)^3 * ( -12 + 7*(w[2]/d)^(5/4) + 5*(d/w[2])^(7/4) ) * 1e12 * 1e-9
End

Function brushheight_butt2005(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = 8*Pi/35 * R*1e-9 * 1.38e-23 * T * L*1e-9 / (s*1e-9)^3 * ( 12 - 7*(d/L)^(-5/4) - 5*(d/L)^(7/4) ) * 1e12
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 4
	//CurveFitDialog/ w[0] = R
	//CurveFitDialog/ w[1] = T
	//CurveFitDialog/ w[2] = L
	//CurveFitDialog/ w[3] = s
	
	// Comment on formula: has sign error

	return 8*Pi/35 * w[0]*1e-9 * 1.38e-23 * w[1] * w[2]*1e-9 / (w[3]*1e-9)^3 * ( 12 - 7*(d/w[2])^(-5/4) - 5*(d/w[2])^(7/4) ) * 1e12
End

Function brushheights_milner_derj(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = Pi * R*1e-9 * 1.38e-23 * T * n * ( Pi^2 * (b*1e-9)^4 / 12 )^(1/3) / (s*1e-9)^(10/3) * ( L/d + (d/L)^2 - 1/5*(d/L)^5 - 9/5 ) * 1e12
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 6
	//CurveFitDialog/ w[0] = R
	//CurveFitDialog/ w[1] = T
	//CurveFitDialog/ w[2] = n
	//CurveFitDialog/ w[3] = b
	//CurveFitDialog/ w[4] = s
	//CurveFitDialog/ w[5] = L

	if (d < 0)
		d = 1e-3
	endif

	return Pi * w[0]*1e-9 * 1.38e-23 * w[1] * w[2] * ( Pi^2 * (w[3]*1e-9)^4 / 12 )^(1/3) / (w[4]*1e-9)^(10/3) * ( w[5]/d + (d/w[5])^2 - 1/5*(d/w[5])^5 - 9/5 ) * 1e12
End


Function escape_liquidmushroom(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = A * d^(-8/3) * exp( -L * d^(-5/3) )
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 2
	//CurveFitDialog/ w[0] = A
	//CurveFitDialog/ w[1] = L

	return w[0] * d^(-8/3) * exp( -w[1] * d^(-5/3) )
End

Function escape_liquidmushroom_vdw(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = A * d^(-8/3) * exp( -L * d^(-5/3) ) - B * d^(-2)
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 3
	//CurveFitDialog/ w[0] = A
	//CurveFitDialog/ w[1] = L
	//CurveFitDialog/ w[2] = B

	return w[0] * d^(-8/3) * exp( -w[1] * d^(-5/3) ) - w[2] * d^(-2)
End

Function escape_liquidmushroom_lj(w,d) : FitFunc
	Wave w
	Variable d

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(d) = A * d^(-8/3) * exp( -L * d^(-5/3) ) + C1 * ( (C2 / d)^13 - (C2 / d)^7 )
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ d
	//CurveFitDialog/ Coefficients 4
	//CurveFitDialog/ w[0] = A
	//CurveFitDialog/ w[1] = L
	//CurveFitDialog/ w[2] = C1
	//CurveFitDialog/ w[3] = C2

	return w[0] * d^(-8/3) * exp( -w[1] * d^(-5/3) ) + w[2] * ( (w[3] / d)^13 - (w[3] / d)^7 )
End
