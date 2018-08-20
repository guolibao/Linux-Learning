#!/bin/bash
#    Copyright 2012-Ajay
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

chapters=0
orig=$1
IFS="."
s=$1
set -- $s
arr=($s)
string=${arr[0]}
i=0
mkdir data-$1
pdfsam-console -f $1.pdf -s BLEVEL -bl 1  -o data-$1/ split 1>asd.txt
error_str=`cat asd.txt | grep FATAL`
if [ -z "$error_str" ]; then
cd data-$1
chapters=1
renameDir="Cover"
for d in *.pdf
do
	arr2=($d)
	mkdir ${arr2[0]}
	pdfsam-console -f ${arr2[0]}.pdf -s BURST -o ${arr2[0]}/ split 1>/dev/null
	cd ${arr2[0]}
	first=1
	for e in *.pdf
	do
		arr3=($e)
		pdftoppm ${arr3[0]}.pdf > ${arr3[0]}.ppm
		mogrify -scale 200% ${arr3[0]}.ppm
		tesseract ${arr3[0]}.ppm ${arr3[0]} 1>/dev/null 2>/dev/null
		text2wave ${arr3[0]}.txt -o ${arr3[0]}.wav 1>/dev/null 2>/dev/null
		if [ $first -eq 1 ]; then
			sed '/^ *$/d' ${arr3[0]}.txt > ${arr3[0]}.bak
			mv ${arr3[0]}.bak ${arr3[0]}.txt
			renameDir=`head -1 ${arr3[0]}.txt`
			first=0
		fi
	done
	rm *.pdf *.ppm *.txt
	sox *.wav $renameDir.wav 1>/dev/null 2>/dev/null
	gst-launch-0.10 filesrc location=$renameDir.wav ! decodebin ! lame ! filesink location=$renameDir.mp3 1>/dev/null 2>/dev/null
	cd ..
	mv ${arr2[0]} ${renameDir//[[:space:]]}
done
rm *.pdf
else
pdfsam-console -f $1.pdf -s BURST -o data-$1/ split 1>/dev/null
cd data-$1
for c in *.pdf
do
	arr1=($c)
	string1=${arr1[0]}
	pdftoppm $string1.pdf > $string1.ppm 
	mogrify -scale 200% $string1.ppm
	tesseract $string1.ppm $string1 1>/dev/null 2>/dev/null
	text2wave $string1.txt -o $string1.wav 1>/dev/null 2>/dev/null
done
sox *.wav $string.wav 1>/dev/null 2>/dev/null
gst-launch-0.10 filesrc location=$string.wav ! decodebin ! lame ! filesink location=$string.mp3 1>/dev/null 2>/dev/null
fi
