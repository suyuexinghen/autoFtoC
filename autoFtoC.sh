#!/bin/bash

mkdir -p build
cp $1 *.h build/
obj=build/$1
filename=$(cut -d "." -f 1 <<<$1)
sed -i -e "/^[ \t]*\!.*/d" -e "/\#/!{s/\!.*//}" $obj
sed -i '/\&/{:a;N;s/\&.*\n//g;/\&/ba}' $obj

file=$(grep -i "^[ \t]*use" $obj|\
        awk -F "use |USE " '{print $2}'|\
        awk -F "[, ]+" '{print $1".F90"}'|\
        sort|uniq )
#define the dimentional variable
awk 'BEGIN{IGNORECASE=1}{
    if ($0~/^[ \t]*real.*dimension\([^\(\)]*\).*::/){
    split($0,a,"::");
    b1=gensub(/.*dimension[ ]*(\([^\(\)]*\)).*/,"\\1","1",a[1]);
    b2=gensub(/,/,b1",","g",a[2]);
    print "\tdouble "b2 b1";"
    }else print $0;}' $obj > $obj.copy
mv $obj{.copy,}
grep -i  "^[ \t]*real.*dimension[^:]*::" $obj | awk -F "::" '{print $2}'|\
    sed  -e "s/,/\n/g" -e "s/[A-Z]/\l&/g" >$obj.varmap.double
    sed -i "s/^[ \t]*\(real.*dimension\)[ ]*(\([^()]*\))[^:]*::\(.*\),/\1(\2)::\3,/Ig;" $obj
s0="^[ \t]*"
s1="\([ \t]*\|^\)"
s3="\(\W\|$\)"
s4="[A-Za-z]\+[A-Za-z_0-9]*"
# find the called funtion
grep -oi "\Scall[ ]\+[a-z]\+\w*[ ]*(" $obj |\
    sed -e "s/call //I" -e "s/ //g" -e "s/[A-Z]/\l&/g" |\
    sort | uniq >$obj.call

#replace external variable
grep -vi "$s1\(write\|subroutine\|integer\|real\|private\|allocate\)$2" $obj |\
        grep -oi "[a-z_]\+\w*[ ]*([^()]*)" | grep -vi "float" |\
        awk -F "[(]" '{print $1"("}'|\
        sed -e "s/[A-Z]/\l&/g" -e "s/=//" -e "s/ //g" |\
        sort | uniq > $obj.varlist.tmp

sed -i "/^\(if\|type\)(/d" $obj.varlist.tmp
grep -v -f $obj.call $obj.varlist.tmp | sed "s/(//" > $obj.varlist
rm -f $obj.varmap.double  $obj.varlist.tmp

cp $file build/ || exit
cd build
sed -i  "s/\!.*$//"  $file
sed -i '/\&/{:a;N;s/\&.*\n//g;/\&/ba}' $file

#define the allocated variable
str=$(cat $1.varlist)
grep -i "$s0\(integer\|real\|dimension\)\W" $file| grep -v "\.F90:[ \t]*\!" >tmp
rm $file
proc1(){
grep -i "${s1}allocate\W" ../*.F90 >tmp_ &
grep -h -A 10 -i "${s1}allocate\W.*\&" ../*.F90 | sed -e "s/\!.*$//"|\
    sed '/\&/{:a;N;s/\&.*\n//g;/\&/ba}' >tmp1_ &
grep -vi "dimension" tmp > tmp0
grep -i "dimension" tmp > tmp1
rm -f $1.varmap.tmp
wait
for var in $str;do
    grep -io ".*\W$var[ ]*([^()]*)" tmp0 |\
            sed "s/\.F90.*\(real\|integer\).*$var[ ]*\(([^)]*)\)/_mp_${var}_\2\1/I" >>$1.varmap.tmp &
    grep -io ".*dimension.*\W$var$s3" tmp1 |\
    sed  "s/\W$//g" | \
    sed "s/\.F90.*\(real\|integer\).*dimension[ ]*\(([^()]*)\).*$var/_mp_${var}_\2\1/I" |\
    sed "s/[A-Z]/\l&/g"  >>$1.varmap.tmp &
    grep -hio ".*allocate.*\W$var[ ]*([^()]*)" tmp_ tmp1_ |\
        sed -e "s/.*$var/${var}/I" -e "s/^\.\.\///" >>$1.varmap.allo_ 
done
sort $1.varmap.allo_ |uniq|sed "s/(/_(/" > $1.varmap.allo
rm -f $1.varmap.allo_
wait
sort $1.varmap.tmp|uniq > $1.varmap.sav
for str in $(cat $1.varmap.allo);do
        str1=$(sed "s/_(.*//" <<<$str);
        sed -i "s/_mp_${str1}_(.*)/_mp_${str}/" $1.varmap.sav; 
done
}
proc1 $1 &
for var in $str;do
    grep -io "^.*\W$var$s3" tmp|\
    sed  "s/\W$//g" | \
    sed  "s/\.F90.*$var/_mp_${var}_/I" >>$1.varmap1
done
sed -e "s/[A-Z]/\l&/g"  -e "/^$/d" $1.varmap1 |\
    sort | uniq > $1.varmap
rm -f $1.varmap1

sed -e "s/.*mp_\(.*\)_/\1(/"  $1.varmap > $1.varout
grep -v -f $1.varout $1.varlist > $1.varin
sed -i  "s/([^()]*)//g"  $1.varin

sed -i "s/(.*//" $1.var{in,out}
sed -i -e "s/[A-Z]/\l&/g" -e "s/(.*//" $1.varmap
a="\([^(),]*\)"
awk -v a="$(cat $1.varout)" -v b="$(cat $1.varmap)" -v c="$(cat $1.varin)"\
    'BEGIN{IGNORECASE=1;RS="#%";cnt=split(a,a_);split(b,b_);
    cnt2=split(c,c_);re_="(\\W)a_[ ]*(\\W)";}
    {tmp=$0;
    for(i=1;i<=cnt;i++){
        re_a=re_; 
        sub(/a_/,a_[i],re_a);
        tmp=gensub(re_a,"\\1"b_[i]"\\2","g",tmp);
        }
    for(i=1;i<=cnt1;i++){
            re_c=re_;
            sub(/a_/,c_[i],re_c);
            tmp=gensub(re_c,"\\1"c_[i]"_\\2","g",tmp);
    };print tmp}' $1 |\
        sed -e "s/_($a,$a,$a,$a,$a)/_[\5][\4][\3][\2][\1]/gI" \
             -e "s/_($a,$a,$a,$a)/_[\4][\3][\2][\1]/gI" \
             -e "s/_($a,$a,$a)/_[\3][\2][\1]/gI" \
             -e "s/_($a,$a)/_[\2][\1]/gI" -e "s/_($a)/_[\1]/gI" |\
       awk '{print gensub("\\[([^a-z_A-Z]+)\\]","[\\1-1]","g")}'|\
    tee -i $1.copy.tmp|\
    awk -F "do |Do |DO |[=,]" \
    '{print ($0!~/^[ \t]*(do |Do |DO )/)?$0:($1"for ("$2"="(($3!~/[a-z_A-Z]+/)?$3-1:$3"-1")";"$2"<"$4";"$2"++){")}' >$1.copy

mv $1{.copy,}
    awk -F "do |Do |DO |[=,]" \
    '{print ($0!~/^[ \t]*(do |Do |DO )/)?$0:($1"if ("$2">="(($3!~/[a-z_A-Z]+/)?$3-1:$3"-1")"&&"$2"<"$4"){")}' $1.copy.tmp >$1.copy

sed -i -e "/^[ \t]*subroutine/I{
        s/$/\{/;
        s/subroutine \(\w*\)\([(]\?\)\([^(){]*\)\([)]\?\)/extern void \1_(\3)/I;
        s/[A-Z]/\l&/g}" \
     -e "s/return/return 0\;/I" \
         -e "s/^[ \t]*use[ ]\+\([a-z_]*\).*/\#include \"\1.h\"/I" \
         -e "/integer[ ]*[:]*/I{s//int /;s/$/\;/}" \
        -e "/real[^:]*::/I{s//double /;s/$/\;/}" \
        -e "/^[ \t]*logical /I{s//bool /;s/$/\;/}" \
        -e "/\#/! s/\(\W\)end.*/\1}/I" \
         -e "s/\/=/!=/g" -e "s/\.or\./||/gI" -e "s/\.and\./\&\&/gI"\
            -e "s/\.eq\./==/gI" -e "s/\.le\./<=/gI" -e "s/\.lt\./</gI" \
            -e "s/\.ge\./>=/gI" -e "s/\.gt\./>/gI" -e "s/\.ne\./\!=/gI" -e "s/\.not\./\!/gI"\
            -e "s/\([0-9.]\)D\([-]\?[0-9]\)/\1e\2/Ig" \
            -e "s/IF/if/I" -e "s/then/{/I" -e "/\#/! s/else/}else{/I" \
             -e "s/else{[ ]*if/else if/" -e "/IMPLICIT/Is/^/\/\//" \
             -e "s/${s1}exit$s3/\1exit()\;/I" $1 $1.copy

sed -i -e "/^[ \t]\+$/d" -e "/\(for\|if\) /s/[A-Z]/\l&/g" \
        -e "s/\[[ \t]*/[/g" -e "s/[ ]*\]/]/g" -e "s/[ ]*\([+-]\|||\|\&\&\)[ ]*/\1/g"  \
        -e "s/\(\w\)[ ]*\*[ ]*\([a-z0-9(]\)/\1 * \2/g" -e "s/,\(\W\|\*\)*/, /g" \
        -e "s/\s*\;\([ ]*\|$\)/\; /g" -e "s/\/[ ]\+/\/ /"\
        -e "/\(double\|int\) /I{s/[A-Z]/\l&/g}" \
         -e '/\(=\|if\)/{/\#/be;s/[A-Z]/\l&/g;/\({\|}\)/be;:a;s/\([^;]\)[ ]*$/\1\;/;:e}' \
    -e  "1i#include <math.h>" -e "2i#include <stdlib.h>"\
    -e "s/^[ \t]*stop/\t exit()\;/I" \
    -e "s/(\([^()]*\)\*\*2)/(\1\*\1)/g" -e "s/(\([^()]*\)\*\*3)/(\1\*\1*\1)/g"\
    -e "s/ \(\w*\)\*\*2 / \1\*\1 /g" \
    -e "s/ \(\w*\)\*\*3 / \1\*\1*\1 /g" \
     -e "s/GO TO \([0-9]*\)/goto label_\1\;/" \
     -e "s/^\([0-9]\+\):/label_\1:/"\
    -e "s/^[ \t]*\([0-9]\+\)/\1:/" -e "s/continue//I" \
    -e "s/\(\W\)0\.\(\W\|$\)/\1 0\2/g" \
     -e "s/\(\W\)int(/\1(int)(/g" \
    -e "s/dfloat/(double)/g" -e "s/\(\W\)float/\1(float)/g" \
    -e "/$s1\(allocate\|call\|write\|type\|external\)\W/Is/^/\/\//" \
    -e "/\[:\]/s/^/\/\//" -e "/^[ \t]*dimension/I{s/^/\/\//}" $1 $1.copy

sed -i -e '/^$/{n;/^$/!be;:a;N;s/\n//;/^$/ba;:e;}' \
    -e  "s/^[\/]\+/\/\//" $1 $1.copy

rename "F90" "c" $1
wait

awk -F "[(,)]" '{printf "s/"$1;for(i=2;i<NF;i++)printf "\\[\\([^]]*\\)\\]";printf "/"$1"[" ;for(i=1;i<NF-1;i++){ printf "+(\\"i")";for(j=2;j<NF-i;j++) printf "*"$j;}; print "]/g";}' $1.varmap.sav > tmp.sed
sed -f tmp.sed $1.copy > $1.cu
grep -o "\<\w\+_mp_\w\+\>[^=]*=" $1.cu | grep -o "\<\w\+_mp_\w\+\>" | sort| uniq > var.tmp2 &
grep -o "=[^=]*\<\w\+_mp_\w\+\>" $1.cu | grep -o "\<\w\+_mp_\w\+\>" |sort|uniq > var.tmp1 &
echo "extern \"C\" void ${filename}_HtoD(){" > ${filename}_HtoD.cu
echo "extern \"C\" void ${filename}_DtoH(){" > ${filename}_DtoH.cu
echo "extern \"C\" void ${filename}_init(){" > ${filename}_init.cu
wait
grep -ho "\<d_\w\+\>" ../*.h | sort | uniq | sed -e "s/^/\\\</" -e "s/$/\\\>/" > excludeVar
grep -f var.tmp1 $1.varmap.sav | sed -e "s/,[^,]*)/)/" -e "s/real/double/" -e "s/integer/int/"|sed "s/,/*/g" |sed "s/\(\w\+\)_mp_\(\w\+\)_(\(.*\))\(\w\+\)/CHECK(cudaMemcpy(d_\2, \1_mp_\2_, \3*sizeof(\4), cudaMemcpyHostToDevice));/"| grep -v -f excludeVar  >>${filename}_HtoD.cu &
grep -f var.tmp2 $1.varmap.sav | sed -e "s/,[^,]*)/)/" -e "s/real/double/" -e "s/integer/int/"|sed "s/,/*/g" |sed "s/\(\w\+\)_mp_\(\w\+\)_(\(.*\))\(\w\+\)/CHECK(cudaMemcpy(\1_mp_\2_, d_\2, \3*sizeof(\4), cudaMemcpyDeviceToHost));/"| grep -v -f excludeVar  >>${filename}_DtoH.cu &
grep -f var.tmp1 -f var.tmp2  $1.varmap.sav | sed -e "s/,[^,]*)/)/" -e "s/real/double/" -e "s/integer/int/"|sed "s/,/*/g" |sed "s/\(\w\+\)_mp_\(\w\+\)_(\(.*\))\(\w\+\)/CHECK(cudaMalloc(\&d_\2, \3*sizeof(\4)));/"|  grep -v -f excludeVar  >>${filename}_init.cu
grep "cudaMalloc" ${filename}_init.cu | sed "s/.*\(d_\w\+\).*sizeof(\(\w\+\)).*/extern \2 *\1;/"  > ${filename}_cu.h &
insertStr1=$(grep "cudaMalloc" ${filename}_init.cu | sed "s/.*\(d_\w\+\).*sizeof(\(\w\+\)).*/\2 *\1=NULL;/")
sed -i "/extern/i${insertStr}\n" ${filename}_init.cu
sed -i -e "s/\[+/[/g" -e "s/(iblock)[^+]*+//g" -e "s/(\([a-z]\))/\1/g" -e "s/\w\+_mp_\(\w\+\)_/d_\1/g" -e "s/(1-1)/0/g" -e "s/(2-1)/1/g" $1.cu
kervar=$(grep -o "\<d_\w\+\>" $1.cu | sort | uniq | sed "s/^/(double */;:a;N;s/\n/, double */;ba;" | sed "s/[)]*$/)/")
kervar1=$(sed "s/double \*//g" <<< $kervar)
kervar2=$(sed "s/[ ]*d_\w\+//g" <<< $kervar)
sed -i "s/.*extern\(.*\){/extern \"C\"\1/" $1.cu
sed -i -e "/extern/i__global__ void ${filename}_ker${kervar2};\nextern \"C\" void ${filename}_HtoD();\nextern \"C\" void ${filename}_DtoH();\n" \
        -e  "/extern/a{\n\tdim3 blockSize(8,16,1);\n\tdim3 gridSize(1+(imt-1)/blockSize.x,1+(jmt-1)/blockSize.y,km);\n\t${filename}_HtoD();\n\t${filename}_ker<<<gridSize,blockSize>>>${kervar1};\n\t${filename}_DtoH();\n}\n__global__ void ${filename}_ker${kervar}{\n\tint i,j,k;\n\ti=blockIdx.x*blockDim.x+threadIdx.x;\n\tj=blockIdx.y*blockDim.y+threadIdx.y;k=blockIdx.z*blockDim.z+threadIdx.z;\n\tunsigned int tid=j*imt+i;\n\tunsigned int ttid=k*imt*jmt+tid;"  $1.cu 

add_include(){
        tmp=$(grep -o "\<\w\+_mp_\w\+\>" $1 | sed "s/\(\w\+\)_mp_\w\+/\1/"| sort|uniq | sed "s/\(.*\)/#include \"\1.h\"/"| sed ":a;N;s/\n/\\\n/;ba")
        sed -i "1 i$tmp\n#include \"cuda_data.h\"\n#include \"${filename}_cu.h\"\n#include \"common.h\""  $1
        echo "}" >> $1
}
wait
add_include ${filename}_HtoD.cu &
add_include ${filename}_DtoH.cu &
add_include ${filename}_init.cu &

sed -i "s/k\*imt\*jmt+j\*imt+i/ttid/g" $1.cu
sed -i "s/j\*imt+i/tid/g" $1.cu

rename ".F90" "" $1.cu
