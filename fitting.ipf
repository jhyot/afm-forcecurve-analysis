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