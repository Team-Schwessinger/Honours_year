#!/bin/bash
#PBS -P sd34 
#PBS -q normal 
#PBS -l walltime=02:00:00
#PBS -l mem=120GB
#PBS -l ncpus=16
#PBS -l jobfs=200GB

set -vx

#define some variables at the start
#give this job a name
name=Pst79_run1-4_1d
short=/short/sd34/ap5514
###
INPUT=$short/basecalling/basecalled_albacore2110
OUTPUT=$short/basecalling/quality_control/minimap_qc/Pst_104E_v13_p_ctg
ASSEMBLY_BASE_FOLDER=$short/Pst_104_v13_assembly
gff_file=Pst_104E_v13_p_ctg.anno.gff3
genome_file=Pst_104E_v13_p_ctg.fa
threads=16
mem_size='120G'
LANFEAR_SCRIPTS=/home/106/ap5514/myapps/minion_qc


#make the output folder
mkdir -p ${OUTPUT}

##this is a script to do basecalling and basic QC of your reads

#now move everything to the node so we can get started
cd $PBS_JOBFS
mkdir TAR_FILES


cp ${INPUT}/Pst79_[1,2,3,4]/*tar.gz TAR_FILES/. # added basecall files


mkdir GENOME
cp ${ASSEMBLY_BASE_FOLDER}/${gff_file} GENOME/.
cp ${ASSEMBLY_BASE_FOLDER}/${genome_file} GENOME/.

#go ahead with unzipping and basecalling
cd TAR_FILES
for x in *.tar.gz
do
len=${#x}
folder=${x::len-7}
mkdir ${folder}
mv ${x} ${folder}/.
cd ${folder} 
tar -xopf ${x}&
cd $PBS_JOBFS/TAR_FILES
done

wait

rm */*.tar.gz


#now capture all the fastq for pass and fail separately plus the summary file
cd $PBS_JOBFS

mkdir albacore_fastq 
cd albacore_fastq

cat ${PBS_JOBFS}/TAR_FILES/*/out_1d/workspace/fail/*.fastq >> ${name}_fail.fastq
cat ${PBS_JOBFS}/TAR_FILES/*/out_1d/workspace/pass/*.fastq >> ${name}_pass.fastq
cat ${PBS_JOBFS}/TAR_FILES/*/out_1d/sequencing_summary.txt >> ${name}_sequencing_summary.txt

#remove TAR_FILES and zip up stuff
cd $PBS_JOBFS
rm -r TAR_FILES
tar -cvzf ${name}_albacore_output.tar.gz albacore_fastq
mv ${name}_albacore_output.tar.gz ${OUTPUT}/.


#now ngmlr is done go on with minimap
#deleted ngmlr script

#Now map the reads with minimap2 to compare mapping with ngmlr.
#mapping with minmap2
outminimap2=${PBS_JOBFS}/"minimap2/"
mkdir $outminimap2
cd $outminimap2
echo "Mapping with minimap2"
date
time 
~/myapps/minimap2/v2.7/minimap2/minimap2 -ax map-ont ${PBS_JOBFS}/albacore_fastq/${name}_pass.fastq ${PBS_JOBFS}/GENOME/${genome_file} > ${name}_pass.minimap2.out.sam
~/myapps/minimap2/v2.7/minimap2/minimap2 -ax map-ont ${PBS_JOBFS}/albacore_fastq/${name}_fail.fastq ${PBS_JOBFS}/GENOME/${genome_file} > ${name}_fail.minimap2.out.sam
~/myapps/minimap2/v2.7/minimap2/minimap2 -x map-ont ${PBS_JOBFS}/albacore_fastq/${name}_pass.fastq ${PBS_JOBFS}/GENOME/${genome_file} > ${name}_pass.minimap2.out.paf
~/myapps/minimap2/v2.7/minimap2/minimap2 -x map-ont ${PBS_JOBFS}/albacore_fastq/${name}_fail.fastq ${PBS_JOBFS}/GENOME/${genome_file} > ${name}_fail.minimap2.out.paf
echo "Done mapping with minimap2"
date



for x in *.sam
do
samtools view -bS -@ $threads ${x} > ${x}.bam
samtools sort -@ $threads ${x}.bam -o ${x}.out.bam
samtools index ${x}.out.bam
time /home/106/ap5514/myapps/qualimap_v2.2.1/qualimap bamqc -bam ${x}.out.bam -outdir ${PBS_JOBFS}/"qualimap_all/" -nt $threads -c --java-mem-size=$mem_size
time /home/106/ap5514/myapps/qualimap_v2.2.1/qualimap bamqc -bam ${x}.out.bam -outdir ${PBS_JOBFS}/"qualimap_gff/" -gff ${PBS_JOBFS}/GENOME/${gff_file} -nt $threads -c --java-mem-size=$mem_size
rm ${x}

NanoPlot --bam ${x}.out.bam --outdir $outnano --threads $threads --loglength --prefix bam

# stats on reads > various length (thanks to @gringer here: https://bioinformatics.stackexchange.com/questions/678/get-the-mapping-statistics-of-a-single-read-$
outbam=${x}.out.bam
samtools view -h $outbam |     awk -F'\t' '{if((/^@/) || (length($10)>1000)){print $0}}' |  samtools stats   | grep '^SN' | cut -f 2- > ${x}.stats_1k.txt
samtools view -h $outbam |     awk -F'\t' '{if((/^@/) || (length($10)>2000)){print $0}}' |  samtools stats   | grep '^SN' | cut -f 2- > ${x}.stats_2k.txt
samtools view -h $outbam |     awk -F'\t' '{if((/^@/) || (length($10)>10000)){print $0}}' | samtools stats   | grep '^SN' | cut -f 2- > ${x}.stats_10k.txt
samtools view -h $outbam |     awk -F'\t' '{if((/^@/) || (length($10)>20000)){print $0}}' | samtools stats   | grep '^SN' | cut -f 2- > ${x}.stats_20k.txt
samtools view -h $outbam |     awk -F'\t' '{if((/^@/) || (length($10)>100000)){print $0}}' | samtools stats  | grep '^SN' | cut -f 2- > ${x}.stats_100k.txt
samtools view -h $outbam |     awk -F'\t' '{if((/^@/) || (length($10)>200000)){print $0}}' | samtools stats  | grep '^SN' | cut -f 2- > ${x}.stats_200k.txt
done
#now move everything back to normal

cd ${PBS_JOBFS}

cp -r $outminimap2 ${OUTPUT}/.
cp -r $outnano ${OUTPUT}/.

