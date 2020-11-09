filename=$1

if(command -v parallel &>/dev/null) then 
para="parallel -j2 --pipe"
fi
#unset para

## -z := --null-data 
## 一个 0 字节的数据行，但不是空行
##  sed  's/\x0//g' 
##  use for deleting null data ^@ 

grep -v "^[ \t]*\/\/" $filename |\
	sed 's/\/\/.*//' |\
	sed '/\/\*/{N;/\*\//be;:a;N;/\*\//!ba;:e;s#/\*.*\*/##g}' |\
        tee src_copy|\
	grep -zo "\w\+[ ]*<<<\([^;]\|\s\)*;" |\
	sed  's/\x0//g' |\
        awk 'BEGIN{RS="^$"}{gsub(/\n/," ");gsub(/;/,"\n");gsub("\t"," ");printf $0;}' \
	> api_call

fun_set=$(grep -o "^[ \t]*\w\+" api_call)
fun_array=($fun_set)
fun_cnt=${#fun_array[@]}

for fun in $fun_set ;do 

cat src_copy |\
awk '{if($0~"__global__[ ]* void[ ]* " "'"$fun"'" "[ ]*\\(")
 	{print NR; sum=10;} 
	sum+=gsub(/{/,"&"); 
	sum-=gsub(/}/,"&");
	if($0~/}/ && sum==10){print NR;sum=100}}' |\
	xargs |\
	awk '{system("sed -n \""$1","$2"p\" src_copy")}' |\
	tee $fun.log |\
	grep -zo "__global__[ \t]* \w\+[ ]*\([^)]\|\s\)*)" |\
	sed  's/\x0//g' |\
	awk 'BEGIN{RS="^$"}{gsub(/\n/," ");gsub(/__global__/,"\n");printf $0;}' \
	> $fun.global

grep "\<$fun\>" api_call |\
	awk -F "[()]" '{print $2}' |\
	awk -F "," '{
		for(i=1;i<=NF;i++) print gensub(" ","","g",$i);
		}' \
	> $fun.tmp1

grep "\<$fun\>" $fun.global |\
	awk -F "[()]" '{print gensub("\t"," ","g",$2)}' |\
	awk -F "," '{gsub("(^|\\W)(const )?(double|float|int) "," ");
		gsub(/*/,"");
		for(i=1;i<=NF;i++) print gensub(" ","","g",$i);
		}' \
	> $fun.tmp2

str_orig=$(diff $fun.tmp1 $fun.tmp2 | grep "^<" | sed "s/<//")
str_fun=$(diff $fun.tmp1 $fun.tmp2 | grep "^>" | sed "s/>//")

if(test -n "$str_orig") then

cat $fun.log |\
awk -v b="$str_orig" -v a="$str_fun" \
	'BEGIN{RS="^$";cnt=split(a,a_);split(b,b_);}{
		for(i=1;i<=cnt;i++){
			gsub("\\<"a_[i]"\\>",b_[i]);
		}
		printf $0; 	
	}' > $fun.log.1
mv $fun.log{.1,} 
fi

done

function merge_kernel(){

cat $1.log |\
	awk 'BEGIN{RS="^$"}{sub("\\).*$",",");printf $0;}' \
	> $1.log.1

cat $2.log |\
	awk 'BEGIN{RS="^$"}{sub("{.*$","{");sub("^.*\\(","\t\t");print $0;}' \
	>> $1.log.1	

var_comm=$(comm -1 -2 <(sort $1.tmp1) <(sort $2.tmp1))

cat $1.log.1 |\
	awk -v co="$var_comm" \
	'BEGIN{RS="^$";cnt=split(co,a_);}{
		for(i=1;i<=cnt;i++){
			$0=gensub("([(,])([^(,]|\\s)*\\<"a_[i]"\\>[ \\s]*,","\\1","1");
		}
		printf $0; 	
	}' > $1.log.2

grep "^[ \t]*\<\($1\|$2\)\>" api_call |\
        sed "/$1/{N;s/)\n[ \t]*$2.*(/,/}" |\
	awk -v co="$var_comm" \
	'BEGIN{RS="^$";cnt=split(co,a_);}{
		for(i=1;i<=cnt;i++){
			sub("\\<"a_[i]"\\>[ \\s]*,","");
		}
		printf $0; 	
	}' > $1.call

head -n -1 $1.log |\
	awk 'BEGIN{RS="^$"}{sub("^[^{]*{","");sub("return;[^}]*$","");printf $0;}' \
	>> $1.log.2

cat $2.log |\
	awk 'BEGIN{RS="^$"}{sub("^[^{]*{","");printf $0;}' \
	>> $1.log.2	

}

for i in `seq 0 $[fun_cnt-2]`;do 
	merge_kernel ${fun_array[i]} ${fun_array[i+1]}
done

rename .log.2 .log *.log.2
rm -f *.{tmp1,tmp2,log.1}
rm -f *.global
