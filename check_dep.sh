
filename=$1
#if(test -z $filename);then 
#        filename=dens_cu.log
#fi
echo -e "\n"$filename"\n"
 cat $filename |\
         grep  -Pzo "\b\w+\b[ ]*(\[[^]]*\][ ]*)?=[^;=]*;" |\
        sed -e "s/\x0//g" -e "s/[ ]\{2,\}//g" |\
        awk 'BEGIN{RS="^$"}{gsub(/\n/," ");gsub(/;/,";\n");gsub("\t"," ");printf $0;}' \
	> expr_line

var_list=$(grep -o "^\w\+[ ]*\[" expr_line | sed "s/[ ]*\[//g" |sort | uniq)
sed  -e "s/^[^=]*=//" -e "s/ //g" expr_line > line_right

a="-----------"
for var in $var_list;do
        grep -on "$var[ ]*\[[^]]*\]" line_right > tmp_file && echo $var >var_match
        tmp_list=$(cut -d : -f 2 tmp_file | sort | uniq )
        for tmp_var in $tmp_list;do
                fgrep "$tmp_var" tmp_file | tail -n 1
        done

        if(test -s var_match )then
                echo $a$a
                var_match=$(cat var_match) 
                grep -on  "^$var_match[ ]*\[[^]]*\]" expr_line |\
                sed "s/ //g" | sort | uniq > var_match1 
                rm var_match
        fi
        if (test -s var_match1 )then
                tmp_list=$(cut -d : -f 2 var_match1 | sort | uniq )
                for tmp_var in $tmp_list;do
                        fgrep "$tmp_var" var_match1 | head -n 1
                done
                echo && rm var_match1
        fi
done

