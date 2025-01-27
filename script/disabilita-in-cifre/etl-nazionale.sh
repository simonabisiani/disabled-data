#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/../data
mkdir -p "$folder"/tmp
mkdir -p "$folder"/../../data/disabilita-in-cifre/processing/nazionale

output="$folder/../../data/disabilita-in-cifre/processing/nazionale"

if [ -f "$folder"/tmp/file.csv ]; then
  rm "$folder"/tmp/file.csv
fi

# a partire dai file xls scaricati con download.sh
find "$folder"/../../data/disabilita-in-cifre/rawdata/ -maxdepth 1 -iname "*.xls" -type f | while read line; do
  name="$(basename "$line" .xls)"
  # estrai il primo foglio
  qsv excel -s 0 "$line" |
    # rimuovi colonne e righe vuote e rimuovi caratteri bianchi ridondanti
    mlr -N --csv remove-empty-columns then clean-whitespace then skip-trivial-records >"$folder"/tmp/"$name".csv
  # calcola il numero di colonne per file ogni file estratto
  colonne=$(mlr -N --c2x filter 'NR==1' "$folder"/tmp/"$name".csv | wc -l)
  # crea anagrafica delle colonne per file, in formato miller
  echo 'name='"$name".csv',colonne'="$colonne"'' >>"$folder"/tmp/file.csv
done

# converti anagrafica da formato miller a CSV
mlr -I --ocsv cat "$folder"/tmp/file.csv
mv "$folder"/tmp/file.csv "$output"/file.csv

if [ -f "$folder"/tmp/2.jsonl ]; then
  rm "$folder"/tmp/2.jsonl
fi

# filtra i file fatti soltanto da 2 colonne
mlr --c2n filter '$colonne==2' then cut -f name "$output"/file.csv | while read line; do
  # estrai nome
  name="$(basename "$line" .csv)"
  # estrai da ogni file soltanto le righe che nella seconda colonna hanno un numero
  mlr -N --c2j filter -S '$2=~"^[0-9]"' then put '$file="'"$line"'"' "$folder"/tmp/"$line" >>"$folder"/tmp/2.jsonl
done

# converti il json in CSV e inserisci i nomi campi
mlr --j2c label territorio,valore,file then put '$file=sub($file,"\..+","")' then filter 'tolower($territorio)=~"^ital"' then put '$territorio="Italia"' "$folder"/tmp/2.jsonl >"$folder"/tmp/2.csv

mv "$folder"/tmp/2.csv "$output"/2.csv


# filtra i file fatti soltanto da 4 colonne
if [ -f "$folder"/tmp/4.jsonl ]; then
  rm "$folder"/tmp/4.jsonl
fi

mlr --c2n filter '$colonne==4' then cut -f name "$output"/file.csv | while read line; do
  name="$(basename "$line" .csv)"
  mlr -N --c2j put '$file="'"$line"'"' "$folder"/tmp/"$line" >>"$folder"/tmp/4.jsonl
done


mlr --j2c filter -x 'is_empty($4)' then sort -r 4 -f file "$folder"/tmp/4.jsonl | tail -n +2 |
  sed -r 's/^,/Regione,/g;s/,#,/,,/g' | mlr --csv filter -S '$Totale=~"^[0-9]"' then label Regione,Disabilità,Anziani,Totale,file then sort -f file,Regione then put '$file=sub($file,"\..+","")'  then filter 'tolower($Regione)=~"^ital"'>"$folder"/tmp/4.csv

mv "$folder"/tmp/4.csv "$output"/4.csv

# filtra i file fatti soltanto da 6 colonne

if [ -f "$folder"/tmp/6.jsonl ]; then
  rm "$folder"/tmp/6.jsonl
fi

mlr --c2n filter '$colonne==6' then cut -f name "$output"/file.csv | while read line; do
  name="$(basename "$line" .csv)"
  mlr -N --c2j put '$file="'"$line"'"' "$folder"/tmp/"$line" >>"$folder"/tmp/6.jsonl
done

mlr --j2c cat then put '$file=sub($file,"\..+","")' "$folder"/tmp/6.jsonl >"$folder"/tmp/6.csv

mlrgo --csv filter -x 'is_empty($4)' then put 'if(is_empty($1)){$tipo=$2}' then fill-down -f tipo then put 'if(is_empty($1)){$1="scelta"}' "$folder"/tmp/6.csv >"$folder"/tmp/6.csv.tmp

mlrgo --csv filter '$tipo=~"^Limi"' then filter -x '$1=="Totale"' "$folder"/tmp/6.csv.tmp | tail -n +2 | mlrgo --csv filter -x '$scelta=="scelta"' then uniq -a then sort -f file then cut -x -r -f ".+_2$" then cut -x -f Totale then rename -r "^g.+",file then filter '$scelta=~"^Ital"'>"$output"/6_01.csv


if [ -f "$output"/6.csv ]; then
  rm "$output"/6.csv
fi

# filtra i file fatti soltanto da 6 colonne
if [ -f "$folder"/tmp/7.jsonl ]; then
  rm "$folder"/tmp/7.jsonl
fi

mlr --c2n filter '$colonne==7' then cut -f name "$output"/file.csv | while read line; do
  name="$(basename "$line" .csv)"
  mlr -N --c2j put '$file="'"$line"'"' "$folder"/tmp/"$line" >>"$folder"/tmp/7.jsonl
done

mlr --j2c cat then put '$file=sub($file,"\..+","")' "$folder"/tmp/7.jsonl >"$folder"/tmp/7.csv

mlrgo --csv filter -x 'is_empty($4)' then put 'if(is_empty($1)){$1="regione"}' "$folder"/tmp/7.csv >"$folder"/tmp/7.csv.tmp

tail <"$folder"/tmp/7.csv.tmp -n +2 | mlrgo --csv filter 'tolower($regione)=~"^ital"'  then rename -r "^g.+",file >"$output"/7.csv

# fai pulizia

find "$output"/ -iname "*.jsonl" -delete

# aggiungi dati anagrafici
for i in "$output"/[0-9]*.csv; do
  name=$(basename "$i" .csv)
  mlrgo --csv join --ul -j file -f "$i" then unsparsify then put '$gerarchia="nazionale"' "$output"/../anagrafica.csv >"$output"/tmp.csv
  mv "$output"/tmp.csv "$output"/"$name".csv
done
