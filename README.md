AFM Force Curve Analysis Software Package for Wavemetrics IGOR Pro
==================================================================

This software offers a basic user interface for analysis of AFM (atomic force microscopy)
force curves and force volume maps from Bruker (formerly Veeco) Nanoscope files.

It consists of procedure files (i.e. scripts) written for [IGOR Pro][igor], a scientific programming and graphing environment by
Wavemetrics.

  [igor]: https://www.wavemetrics.com/products/igorpro/igorpro.htm


The software provides analysis, review and classification of force curves and force volume maps.



Requirements
------------

You need to have IGOR Pro in order to run the AFM analysis software.

The software has been tested with IGOR Pro 6.3.4 under Windows 7. It should also run on Igor for Mac, but that
has not been tested.

The software has been tested with data from Bruker Nanoscope versions 7.3 and 8.1x. Nanoscope 9.x seems to work as well, but
has not been thoroughly tested. As long as the Nanoscope data file format does not change, the software should work without
problems.



Installation
------------

* Go to <https://github.com/jhyot/afm-forcecurve-analysis/releases/latest>
* Download the `afm-forcecurve-analysis.zip` file.
* Unpack the contents of the zip file into any directory on your computer.
* Open `force-curve-analysis.ipf` in IGOR and compile the file. You are now ready to use the software.


Building from source
--------------------

There is no build process, the `.ipf` files can be directly openend with IGOR Pro. The folder structure must be
kept the same so that the individual files can be found from the main `force-curve-analysis.ipf` file.

Run `./build.sh` (currently on Linux only) from the project root folder to automatically generate a zip file with the
necessary files for easy redistribution.

To also generate the PDF manual from Latex sources, a Tex distribution must be present on the build system.



Acknowledgements
----------------
This software was originally developed in Prof. Roderick Lim's [Nanobiology Group][nanobio]
at the University of Basel.

Original contributors:
* Janne Hyötylä, [jhyotyla@gmail.com](mailto:jhyotyla@gmail.com)
* Raphael Wagner, [raphael@wagner-net.ch](mailto:raphael@wagner-net.ch)


  [nanobio]: http://www.biozentrum.unibas.ch/research/groups-platforms/overview/unit/lim/



License
-------
This software is licensed under the Apache License 2.0. See the LICENSE file for full details.


------

Copyright &copy; 2016 University of Basel


